extends Node
## Loads and indexes all gameplay data. Nothing here is hard-coded balance.
##
## Data files are plain JSON so they can be tuned (or replaced) without
## touching a single script.

const DATA_DIR := "res://data/"

var products: Array = []
var impossible_items: Array = []
var anomalies: Array = []
var harmless_traits: Array = []
var personalities: Array = []
var questions: Array = []
var entity_lines: Dictionary = {}
var shifts: Array = []
var endless_config: Dictionary = {}
var environmental_events: Array = []
var jumpscares: Array = []

var _product_by_id: Dictionary = {}
var _anomaly_by_id: Dictionary = {}
var _personality_by_id: Dictionary = {}


func _ready() -> void:
	_load_all()


func _load_all() -> void:
	var p := _read_json("products.json")
	products = p.get("products", [])
	impossible_items = p.get("impossible_items", [])

	var a := _read_json("anomalies.json")
	anomalies = a.get("anomalies", [])
	harmless_traits = a.get("harmless_traits", [])

	var pers := _read_json("personalities.json")
	personalities = pers.get("personalities", [])
	questions = pers.get("questions", [])
	entity_lines = pers.get("entity_lines", {})

	var s := _read_json("shifts.json")
	shifts = s.get("shifts", [])
	endless_config = s.get("endless", {})

	var h := _read_json("horror_events.json")
	environmental_events = h.get("environmental", [])
	jumpscares = h.get("jumpscares", [])

	for product in products:
		_product_by_id[product["id"]] = product
	for item in impossible_items:
		_product_by_id[item["id"]] = item
	for anomaly in anomalies:
		_anomaly_by_id[anomaly["id"]] = anomaly
	for personality in personalities:
		_personality_by_id[personality["id"]] = personality

	_validate()


func _read_json(filename: String) -> Dictionary:
	var path := DATA_DIR + filename
	if not FileAccess.file_exists(path):
		push_error("GameData: missing data file %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("GameData: could not open %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s is not valid JSON" % path)
		return {}
	return parsed


func _validate() -> void:
	if products.is_empty():
		push_error("GameData: no products loaded.")
	if anomalies.is_empty():
		push_error("GameData: no anomalies loaded.")
	if shifts.is_empty():
		push_error("GameData: no shifts loaded.")
	var focuses := {}
	for anomaly in anomalies:
		focuses[anomaly.get("focus", "")] = true
	for focus in ["hands", "eyes", "face", "mouth", "neck"]:
		if not focuses.has(focus):
			push_warning("GameData: no anomalies use focus '%s'." % focus)


# --- Products ---------------------------------------------------------------

func get_product(id: String) -> Dictionary:
	return _product_by_id.get(id, {})


func all_products() -> Array:
	return products


func random_products(count: int, rng: RandomNumberGenerator, exclude: Array = []) -> Array:
	var pool: Array = []
	for product in products:
		if not exclude.has(product["id"]):
			pool.append(product)
	var picked: Array = []
	for i in range(mini(count, pool.size())):
		var idx := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked


func random_impossible_item(rng: RandomNumberGenerator) -> Dictionary:
	if impossible_items.is_empty():
		return {}
	return impossible_items[rng.randi_range(0, impossible_items.size() - 1)]


func price_string(cents: int) -> String:
	return "$%d.%02d" % [int(cents / 100.0), cents % 100]


# --- Anomalies --------------------------------------------------------------

func get_anomaly(id: String) -> Dictionary:
	return _anomaly_by_id.get(id, {})


func anomalies_for_focus(focus: String) -> Array:
	var result: Array = []
	for anomaly in anomalies:
		if anomaly.get("focus", "") == focus:
			result.append(anomaly)
	return result


func get_trait(id: String) -> Dictionary:
	for entry in harmless_traits:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


## Picks anomalies valid for a shift: respects min_obviousness and blocked focuses.
func roll_anomalies(count: int, shift_data: Dictionary, rng: RandomNumberGenerator) -> Array:
	var min_obv: int = int(shift_data.get("min_obviousness", 1))
	var blocked: Array = shift_data.get("excluded_focus", [])
	var pool: Array = []
	for anomaly in anomalies:
		if int(anomaly.get("obviousness", 2)) < min_obv:
			continue
		if blocked.has(anomaly.get("focus", "")):
			continue
		pool.append(anomaly)

	var chosen: Array = []
	var used_focus := {}
	pool.shuffle()
	for anomaly in pool:
		if chosen.size() >= count:
			break
		var focus: String = anomaly.get("focus", "")
		if used_focus.has(focus):
			continue
		chosen.append(anomaly)
		used_focus[focus] = true
	while chosen.size() < count and not pool.is_empty():
		var extra: Dictionary = pool.pop_back()
		if not chosen.has(extra):
			chosen.append(extra)
	if chosen.is_empty() and not anomalies.is_empty():
		chosen.append(anomalies[rng.randi_range(0, anomalies.size() - 1)])
	return chosen


func random_harmless_trait(rng: RandomNumberGenerator) -> Dictionary:
	if harmless_traits.is_empty():
		return {}
	return harmless_traits[rng.randi_range(0, harmless_traits.size() - 1)]


# --- People -----------------------------------------------------------------

func get_personality(id: String) -> Dictionary:
	if _personality_by_id.has(id):
		return _personality_by_id[id]
	return personalities[0] if not personalities.is_empty() else {}


func random_personality(rng: RandomNumberGenerator) -> Dictionary:
	if personalities.is_empty():
		return {}
	return personalities[rng.randi_range(0, personalities.size() - 1)]


func personality_line(personality_id: String, key: String, rng: RandomNumberGenerator) -> String:
	var personality := get_personality(personality_id)
	var answers: Dictionary = personality.get("questions", {})
	var lines: Array = answers.get(key, [])
	if lines.is_empty():
		return "..."
	return str(lines[rng.randi_range(0, lines.size() - 1)])


func personality_greeting(personality_id: String, rng: RandomNumberGenerator) -> String:
	var personality := get_personality(personality_id)
	var lines: Array = personality.get("greeting", [])
	if lines.is_empty():
		return "..."
	return str(lines[rng.randi_range(0, lines.size() - 1)])


func entity_line(key: String, rng: RandomNumberGenerator) -> String:
	var lines: Array = entity_lines.get(key, [])
	if lines.is_empty():
		return "..."
	return str(lines[rng.randi_range(0, lines.size() - 1)])


# --- Shifts -----------------------------------------------------------------

func shift_count() -> int:
	return shifts.size()


func get_shift(index: int) -> Dictionary:
	if shifts.is_empty():
		return {}
	var clamped := clampi(index, 1, shifts.size())
	return shifts[clamped - 1]


## Builds a synthetic shift config for endless mode round N (1-based).
func endless_shift(round_index: int) -> Dictionary:
	var cfg := endless_config
	var customer_count: int = int(cfg.get("base_customers", 8) + int(cfg.get("customers_per_round", 1.5) * (round_index - 1)))
	var chance: float = minf(
		float(cfg.get("max_entity_chance", 0.65)),
		float(cfg.get("base_entity_chance", 0.42)) + float(cfg.get("entity_chance_per_round", 0.03)) * (round_index - 1)
	)
	return {
		"index": 100 + round_index,
		"name": "Endless %d" % round_index,
		"title": "Overtime",
		"briefing": ["No clock. No closing time. Keep going until something goes wrong."],
		"customers": customer_count,
		"entity_chance": chance,
		"max_entities": 3,
		"min_anomalies": 2 if round_index > 2 else 1,
		"max_anomalies": 3 if round_index > 4 else 2,
		"min_entities": int(cfg.get("min_entities", 1)),
		"min_obviousness": int(cfg.get("base_obviousness", 2)) if round_index <= 2 else 1,
		"excluded_focus": [],
		"harmless_trait_chance": 0.45,
		"items_min": int(cfg.get("items_min", 4)),
		"items_max": int(cfg.get("items_max", 7)),
		"patience_scale": 0.9,
		"time_limit": int(cfg.get("time_limit", 720)),
		"horror_level": mini(4, 1 + int(round_index / 2.0)),
		"penalty_mode": "fail",
		"pay_per_customer": int(cfg.get("pay_per_customer", 40)),
		"entity_bonus": int(cfg.get("entity_bonus", 300)),
		"wrong_fine": int(cfg.get("wrong_fine", 150)),
		"endless": true,
		"night_for_horror": mini(5, round_index),
	}


# --- Horror -----------------------------------------------------------------

func environmental_events_for_night(night: int) -> Array:
	var result: Array = []
	for event in environmental_events:
		if int(event.get("min_night", 1)) <= night:
			result.append(event)
	return result


func jumpscares_for_night(night: int) -> Array:
	var result: Array = []
	for scare in jumpscares:
		if int(scare.get("min_night", 1)) <= night:
			result.append(scare)
	return result
