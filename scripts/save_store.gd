extends Node
## Progress + account store. Guests save locally (user://). Registered players (username +
## password) also sync the same progress to the Manus database through /api/v1.
##
## Save model v1: {version, lives, coins, score, unlocked, stages: {id: {cleared, best, medals: [b,b,b]}}, updated}

signal save_failed
signal cloud_status_changed(status: String, detail: String)
signal account_changed

const VERSION := 1
const START_LIVES := 5
const MAX_LIVES := 99
const ACCOUNT_PATH := "user://popo_account.cfg"
const SETTINGS_PATH := "user://popo_prefs.cfg"
const API_SUFFIX := "/api/v1"
const USERNAME_REGEX := "^[A-Za-z0-9_]{3,16}$"

var data: Dictionary = {}
var username := ""          # empty = guest
var token := ""
var revision := 0
var api_root := ""
var read_only := false
var cloud_status := "offline"
var selected_stage := "w1_1"
var _sync_in_flight := false
var _sync_again := false
var _username_re := RegEx.new()


func _ready() -> void:
	_username_re.compile(USERNAME_REGEX)
	api_root = _derive_api_root()
	if OS.has_feature("web"):
		read_only = bool(JavaScriptBridge.eval("window.__MANUS_GAME_HISTORY__?.readOnly === true", true))
	_load_account()
	load_save()


# ---------------------------------------------------------------- account ------------------
func is_guest() -> bool:
	return username.is_empty()


func display_name() -> String:
	return "ゲスト" if is_guest() else username


func online_available() -> bool:
	return not api_root.is_empty() and not read_only


func valid_username(value: String) -> bool:
	return _username_re.search(value) != null


func valid_password(value: String) -> bool:
	if value.length() < 6 or value.length() > 64:
		return false
	for i in value.length():
		var c := value.unicode_at(i)
		if c < 0x21 or c > 0x7e:
			return false
	return true


func has_saved_session() -> bool:
	return not username.is_empty() and not token.is_empty()


func _load_account() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(ACCOUNT_PATH) == OK:
		username = str(cfg.get_value("account", "username", ""))
		token = str(cfg.get_value("account", "token", ""))
		if not valid_username(username):
			username = ""
			token = ""


func _store_account() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("account", "username", username)
	cfg.set_value("account", "token", token)
	cfg.save(ACCOUNT_PATH)


func play_as_guest() -> void:
	username = ""
	token = ""
	revision = 0
	_store_account()
	load_save()
	_set_status("offline", "")
	account_changed.emit()


## Register a new account, then adopt the current guest progress if the account is empty.
func register(name: String, password: String) -> Dictionary:
	if not valid_username(name):
		return {"ok": false, "error": "invalid_username"}
	if not valid_password(password):
		return {"ok": false, "error": "invalid_password"}
	var guest_data := data.duplicate(true) if is_guest() else {}
	var result := await _request("/auth/register", HTTPClient.METHOD_POST, {"username": name, "password": password}, false)
	if not result.ok:
		return result
	await _adopt_session(result.data, guest_data)
	return {"ok": true}


func login(name: String, password: String) -> Dictionary:
	if not valid_username(name) or not valid_password(password):
		return {"ok": false, "error": "invalid_credentials"}
	var result := await _request("/auth/login", HTTPClient.METHOD_POST, {"username": name, "password": password}, false)
	if not result.ok:
		return result
	await _adopt_session(result.data, {})
	return {"ok": true}


## Resume a remembered session. Returns ok=false (and drops the token) when it expired.
func resume_session() -> Dictionary:
	if not has_saved_session():
		return {"ok": false, "error": "no_session"}
	load_save()
	var result := await pull_cloud()
	if not result.ok and int(result.get("status", 0)) == 401:
		return result
	return {"ok": true, "offline": not result.ok}


func logout() -> void:
	if not token.is_empty() and online_available():
		await _request("/auth/logout", HTTPClient.METHOD_POST, {}, true)
	play_as_guest()


func _adopt_session(payload: Dictionary, guest_data: Dictionary) -> void:
	username = str(payload.get("username", ""))
	token = str(payload.get("token", ""))
	_store_account()
	load_save()
	var pulled := await pull_cloud()
	if pulled.ok and not guest_data.is_empty() and _progress_weight(guest_data) > _progress_weight(data):
		data = _merge(data, guest_data)
		save()
	account_changed.emit()


# ---------------------------------------------------------------- local save ---------------
func _save_path() -> String:
	return "user://popo_save_%s.json" % ("guest" if is_guest() else username.to_lower())


func _default_data() -> Dictionary:
	return {"version": VERSION, "lives": START_LIVES, "coins": 0, "score": 0, "unlocked": 1, "stages": {}, "updated": 0}


func load_save() -> void:
	data = _default_data()
	revision = 0
	var path := _save_path()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = _sanitize(parsed)
			revision = int((parsed as Dictionary).get("_revision", 0))


func _write_local() -> bool:
	var copy := data.duplicate(true)
	copy["_revision"] = revision
	var file := FileAccess.open(_save_path(), FileAccess.WRITE)
	if file == null:
		save_failed.emit()
		return false
	file.store_string(JSON.stringify(copy))
	return true


## Persist locally and (for accounts) queue a cloud upload.
func save() -> bool:
	data["updated"] = int(Time.get_unix_time_from_system())
	var ok := _write_local()
	if not is_guest():
		push_cloud()
	return ok


func _sanitize(raw: Dictionary) -> Dictionary:
	var clean := _default_data()
	clean.lives = clampi(int(raw.get("lives", START_LIVES)), 1, MAX_LIVES)
	clean.coins = clampi(int(raw.get("coins", 0)), 0, 99)
	clean.score = clampi(int(raw.get("score", 0)), 0, 99999999)
	clean.unlocked = clampi(int(raw.get("unlocked", 1)), 1, 24)
	clean.updated = int(raw.get("updated", 0))
	var stages: Variant = raw.get("stages", {})
	if stages is Dictionary:
		for id in stages:
			var entry: Variant = stages[id]
			if not entry is Dictionary or not str(id).begins_with("w"):
				continue
			var medals: Array = [false, false, false]
			var raw_medals: Variant = entry.get("medals", [])
			if raw_medals is Array:
				for i in mini(3, raw_medals.size()):
					medals[i] = bool(raw_medals[i])
			clean.stages[str(id)] = {"cleared": bool(entry.get("cleared", false)), "best": clampi(int(entry.get("best", 0)), 0, 9999999), "medals": medals}
	return clean


func _progress_weight(d: Dictionary) -> int:
	var weight := int(d.get("unlocked", 1)) * 1000
	var stages: Dictionary = d.get("stages", {})
	for id in stages:
		var entry: Dictionary = stages[id]
		for m in entry.get("medals", []):
			weight += 1 if m else 0
	return weight


## Union of two saves: never lose unlocked stages, medals or best scores.
func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := _sanitize(a)
	var other := _sanitize(b)
	out.unlocked = maxi(out.unlocked, other.unlocked)
	out.score = maxi(out.score, other.score)
	if int(other.updated) > int(out.updated):
		out.coins = other.coins
		out.lives = other.lives
	for id in other.stages:
		var theirs: Dictionary = other.stages[id]
		if not out.stages.has(id):
			out.stages[id] = theirs.duplicate(true)
			continue
		var mine: Dictionary = out.stages[id]
		mine.cleared = mine.cleared or theirs.cleared
		mine.best = maxi(mine.best, theirs.best)
		for i in 3:
			mine.medals[i] = mine.medals[i] or theirs.medals[i]
	out.updated = maxi(int(out.updated), int(other.updated))
	return out


# ---------------------------------------------------------------- progress API -------------
func lives() -> int:
	return int(data.lives)


func coins() -> int:
	return int(data.coins)


func total_score() -> int:
	return int(data.score)


func unlocked_count() -> int:
	return int(data.unlocked)


func stage_record(id: String) -> Dictionary:
	return (data.stages.get(id, {"cleared": false, "best": 0, "medals": [false, false, false]}) as Dictionary).duplicate(true)


func medal_total() -> int:
	var total := 0
	for id in data.stages:
		for m in data.stages[id].medals:
			total += 1 if m else 0
	return total


func cleared_count() -> int:
	var total := 0
	for id in data.stages:
		total += 1 if data.stages[id].cleared else 0
	return total


func is_unlocked(stage_index: int) -> bool:
	return stage_index < unlocked_count()


## Record a cleared stage. Returns {new_best, unlocked_next}.
func record_clear(id: String, stage_index: int, score: int, medals: Array, coins_now: int, lives_now: int, total_count: int) -> Dictionary:
	var record := stage_record(id)
	var new_best := score > int(record.best)
	record.cleared = true
	record.best = maxi(int(record.best), score)
	for i in mini(3, medals.size()):
		record.medals[i] = bool(record.medals[i]) or bool(medals[i])
	data.stages[id] = record
	var before := unlocked_count()
	data.unlocked = clampi(maxi(before, stage_index + 2), 1, total_count)
	data.coins = clampi(coins_now, 0, 99)
	data.lives = clampi(lives_now, 1, MAX_LIVES)
	data.score = int(data.score) + score
	save()
	return {"new_best": new_best, "unlocked_next": unlocked_count() > before}


## Called after losing every life: reset lives, keep unlocked stages and medals.
func game_over_reset() -> void:
	data.lives = START_LIVES
	data.coins = 0
	save()


func store_run_state(coins_now: int, lives_now: int) -> void:
	data.coins = clampi(coins_now, 0, 99)
	data.lives = clampi(lives_now, 1, MAX_LIVES)
	save()


# ---------------------------------------------------------------- cloud ---------------------
func _set_status(status: String, detail: String) -> void:
	cloud_status = status
	cloud_status_changed.emit(status, detail)


func pull_cloud() -> Dictionary:
	if is_guest() or not online_available():
		_set_status("offline", "")
		return {"ok": false, "error": "offline"}
	_set_status("syncing", "")
	var result := await _request("/save", HTTPClient.METHOD_GET, {}, true)
	if not result.ok:
		_set_status("error" if int(result.get("status", 0)) != 401 else "expired", str(result.get("error", "")))
		return result
	var payload: Dictionary = result.data
	var remote: Variant = payload.get("data")
	revision = int(payload.get("revision", 0))
	if remote is Dictionary:
		data = _merge(data, remote)
	_write_local()
	_set_status("synced", "")
	# Upload if the local copy had progress the cloud did not.
	if not remote is Dictionary or _progress_weight(data) > _progress_weight(remote) or int(data.score) != int((remote as Dictionary).get("score", -1)):
		push_cloud()
	return {"ok": true}


func push_cloud() -> void:
	if is_guest() or not online_available():
		return
	if _sync_in_flight:
		_sync_again = true
		return
	_sync_in_flight = true
	_set_status("syncing", "")
	var attempts := 0
	while attempts < 3:
		attempts += 1
		var payload := data.duplicate(true)
		var result := await _request("/save", HTTPClient.METHOD_PUT, {"revision": revision, "data": payload}, true)
		if result.ok:
			revision = int(result.data.get("revision", revision + 1))
			_write_local()
			_set_status("synced", "")
			break
		if int(result.get("status", 0)) == 409:
			var body: Dictionary = result.get("body", {})
			revision = int(body.get("revision", revision))
			var remote: Variant = body.get("data")
			if remote is Dictionary:
				data = _merge(data, remote)
			continue
		_set_status("expired" if int(result.get("status", 0)) == 401 else "error", str(result.get("error", "")))
		break
	_sync_in_flight = false
	if _sync_again:
		_sync_again = false
		push_cloud()


func _derive_api_root() -> String:
	if OS.has_feature("web"):
		var history_root := str(JavaScriptBridge.eval("window.__MANUS_GAME_HISTORY__?.apiRoot || ''", true))
		if history_root.contains("game-history.invalid"):
			return ""
		var origin := str(JavaScriptBridge.eval("window.location.origin", true))
		var path := str(JavaScriptBridge.eval("window.location.pathname", true))
		var preview_marker := path.find("/__manus__/game-preview/")
		if preview_marker >= 0:
			return origin + path.substr(0, preview_marker) + API_SUFFIX
		return origin + API_SUFFIX
	return OS.get_environment("POPO_API_ROOT")


func _request(path: String, method: HTTPClient.Method, payload: Dictionary, authed: bool) -> Dictionary:
	if api_root.is_empty():
		return {"ok": false, "error": "offline"}
	if read_only and method != HTTPClient.METHOD_GET:
		return {"ok": false, "error": "read_only"}
	var request := HTTPRequest.new()
	request.timeout = 15.0
	add_child(request)
	var headers := PackedStringArray(["Accept: application/json"])
	if authed and not token.is_empty():
		headers.append("Authorization: Bearer " + token)
		headers.append("X-Session-Token: " + token)
	var encoded := ""
	if method != HTTPClient.METHOD_GET:
		headers.append("Content-Type: application/json")
		encoded = JSON.stringify(payload)
	var start_error := request.request(api_root + path, headers, method, encoded)
	if start_error != OK:
		request.queue_free()
		return {"ok": false, "error": "network"}
	var reply: Array = await request.request_completed
	request.queue_free()
	if reply[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "network"}
	var status: int = reply[1]
	var parsed: Variant = JSON.parse_string((reply[3] as PackedByteArray).get_string_from_utf8())
	if not parsed is Dictionary:
		return {"ok": false, "status": status, "error": "server_unavailable"}
	if status == 401 and authed:
		token = ""
		_store_account()
	if status < 200 or status >= 300:
		return {"ok": false, "status": status, "error": str(parsed.get("error", "server_unavailable")), "body": parsed}
	return {"ok": true, "data": parsed}


## Japanese explanation for API error codes shown on the login card.
static func error_text(code: String) -> String:
	match code:
		"invalid_username": return "ユーザー名は半角英数字と _ で3〜16文字にしてください。"
		"invalid_password": return "パスワードは半角6〜64文字にしてください（スペース不可）。"
		"username_taken": return "そのユーザー名はすでに使われています。別の名前にしてください。"
		"invalid_credentials": return "ユーザー名かパスワードがちがいます。"
		"too_many_attempts": return "ログインの試行が多すぎます。しばらく待ってからもう一度どうぞ。"
		"registration_busy", "rate_limited": return "混み合っています。少し待ってからもう一度どうぞ。"
		"online_preview_requires_checkpoint": return "このプレビューではオンライン機能を使えません。ゲストで遊べます。"
		"offline", "network", "server_unavailable": return "サーバーにつながりません。ゲストで遊ぶこともできます。"
		"read_only": return "閲覧専用モードのため保存できません。"
		"session_invalid": return "ログインの有効期限が切れました。もう一度ログインしてください。"
	return "エラーが発生しました（%s）。" % code


# ---------------------------------------------------------------- preferences --------------
func pref(key: String, fallback: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		return cfg.get_value("prefs", key, fallback)
	return fallback


func set_pref(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("prefs", key, value)
	cfg.save(SETTINGS_PATH)
