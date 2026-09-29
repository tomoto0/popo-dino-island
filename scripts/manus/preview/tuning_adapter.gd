extends "res://scripts/manus/preview/tuning_transport.gd"

func store() -> Variant:
	return get_node_or_null("/root/TuningStore")

func settings() -> Array:
	return store().get_settings()

func requested(setting: Dictionary) -> Variant:
	return store().get_requested_value(str(setting.key))

func active(setting: Dictionary) -> Variant:
	return store().get_value(str(setting.key))

func commit(patch: Dictionary) -> bool:
	var by_id := {}
	for setting: Dictionary in settings(): by_id[str(setting.id)] = setting
	var mapped := {}
	for id: String in patch: mapped[by_id[id].key] = float(patch[id])
	return store().set_values(mapped)

func control_for(setting: Dictionary) -> Dictionary:
	var localized := setting.duplicate(true)
	localized["category_key"] = "tuning.category." + str(setting.category)
	return super.control_for(localized)
