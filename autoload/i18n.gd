extends Node

signal locale_changed(locale: String)

const SUPPORTED_LOCALES := ["ja"]
const PREFERENCE_PATH := "user://language.cfg"
var _locale := "ja"
var _catalogs: Dictionary = {}


func _ready() -> void:
	for locale: String in SUPPORTED_LOCALES:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://localization/%s.json" % locale))
		assert(data is Dictionary, "Localization catalog must be an object: " + locale)
		_catalogs[locale] = data
	_locale = _initial_locale()
	TranslationServer.set_locale(_locale)
	_sync_web_locale()


func _initial_locale() -> String:
	var preference := ConfigFile.new()
	if preference.load(PREFERENCE_PATH) == OK:
		var saved := str(preference.get_value("language", "locale", ""))
		if saved in SUPPORTED_LOCALES:
			return saved
	var mirrored: Variant = _read_web_locale()
	if mirrored is String and mirrored in SUPPORTED_LOCALES:
		return mirrored
	return _default_locale()


func _read_web_locale() -> Variant:
	if OS.has_feature("web"):
		return JavaScriptBridge.eval("(() => { try { return localStorage.getItem('popo-language'); } catch (_) { return null; } })()", true)
	return null


func _default_locale() -> String:
	return locale_for_system(_system_locale())


## First-launch language follows the OS/browser language (on Web, OS.get_locale()
## reflects navigator.language). Overridable seam so tests never read the machine locale.
func _system_locale() -> String:
	return OS.get_locale()


## Any Chinese system locale (zh, zh_CN, zh-TW, zh_Hans…) maps to Simplified Chinese; all else to English.
static func locale_for_system(system_locale: String) -> String:
	return "ja"


func get_locale() -> String:
	return _locale


func set_locale(locale: String) -> bool:
	if locale not in SUPPORTED_LOCALES:
		return false
	var changed := locale != _locale
	_locale = locale
	TranslationServer.set_locale(locale)
	_sync_web_locale()
	var preference := ConfigFile.new()
	preference.set_value("language", "locale", locale)
	if preference.save(PREFERENCE_PATH) != OK:
		push_warning("Language preference could not be saved; it remains active for this session.")
	if changed:
		locale_changed.emit(locale)
	return true


func t(key: String, placeholders: Dictionary = {}) -> String:
	var active: Dictionary = _catalogs.get(_locale, {})
	var value := str(active.get(key, key))
	for token: Variant in placeholders:
		value = value.replace("{%s}" % str(token), str(placeholders[token]))
	return value


func catalog(locale: String) -> Dictionary:
	return (_catalogs.get(locale, {}) as Dictionary).duplicate(true)


func _sync_web_locale() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('popo-language', %s); } catch (_) {}" % JSON.stringify(_locale), true)
