extends Node
## Local, offline save profile. Written to user://nightsave.json.
##
## Only meta-progression lives here; per-shift state is intentionally volatile.

const SAVE_PATH := "user://nightsave.json"
const SAVE_VERSION := 1


func default_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"money": 0,
		"shifts_completed": 0,
		"unlocked_shift": 1,
		"endless_unlocked": false,
		"endless_best": 0,
		"stats": {
			"customers_served": 0,
			"humans_approved": 0,
			"entities_rejected": 0,
			"humans_rejected": 0,
			"entities_approved": 0,
			"scans": 0,
			"shifts_played": 0,
			"best_accuracy": 0.0,
		},
		"discovered_anomalies": [],
		"notebook_seen_tips": [],
		"settings_dirty": false,
	}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_profile() -> Dictionary:
	var profile := default_profile()
	if not FileAccess.file_exists(SAVE_PATH):
		return profile
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: could not open save file for reading.")
		return profile
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveManager: save file corrupt, using defaults.")
		return profile
	# Merge so new fields added in later versions get defaults.
	for key in profile.keys():
		if not parsed.has(key):
			parsed[key] = profile[key]
	if typeof(parsed.get("stats")) == TYPE_DICTIONARY:
		for stat_key in profile["stats"].keys():
			if not parsed["stats"].has(stat_key):
				parsed["stats"][stat_key] = profile["stats"][stat_key]
	return parsed


func save_profile(profile: Dictionary) -> void:
	profile["version"] = SAVE_VERSION
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: could not open save file for writing.")
		return
	file.store_string(JSON.stringify(profile, "\t"))
	file.close()
	Events.save_completed.emit()


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
