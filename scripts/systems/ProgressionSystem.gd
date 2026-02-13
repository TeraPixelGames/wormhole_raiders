extends Node
class_name ProgressionSystem

const SAVE_PATH: String = "user://progress.cfg"

@onready var state: RunState = get_parent().get_node("RunState")
@onready var bus: EventBus = get_parent().get_node("EventBus")

@export var enable_daily_seed: bool = true
@export var daily_seed_offset: int = 7001

var high_score: int = 0
var runs_played: int = 0
var _last_score: int = 0
var unlocked_themes: PackedStringArray = PackedStringArray(["default"])
var unlocked_skins: PackedStringArray = PackedStringArray(["starter"])

func _ready() -> void:
	_load_progress()
	bus.score_changed.connect(_on_score_changed)
	bus.run_started.connect(_on_run_started)
	bus.run_ended.connect(_on_run_ended)
	bus.emit_signal("high_score_changed", high_score)

func choose_seed(fallback_seed: int) -> int:
	if enable_daily_seed:
		return get_daily_seed()
	return fallback_seed

func get_daily_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system()
	var year: int = int(d.get("year", 2026))
	var month: int = int(d.get("month", 1))
	var day: int = int(d.get("day", 1))
	return year * 10000 + month * 100 + day + daily_seed_offset

func get_high_score() -> int:
	return high_score

func get_runs_played() -> int:
	return runs_played

func _on_run_started(_seed: int) -> void:
	_last_score = 0

func _on_score_changed(score: int) -> void:
	_last_score = max(_last_score, score)

func _on_run_ended(_reason: String) -> void:
	runs_played += 1
	if _last_score > high_score:
		high_score = _last_score
		bus.emit_signal("high_score_changed", high_score)
	_unlock_cosmetics()
	_save_progress()

func _unlock_cosmetics() -> void:
	if high_score >= 300 and not unlocked_themes.has("sunset"):
		unlocked_themes.append("sunset")
	if high_score >= 900 and not unlocked_themes.has("magenta_core"):
		unlocked_themes.append("magenta_core")
	if runs_played >= 8 and not unlocked_skins.has("chrome_capsule"):
		unlocked_skins.append("chrome_capsule")

func _load_progress() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(SAVE_PATH)
	if err != OK:
		return
	high_score = int(cfg.get_value("meta", "high_score", high_score))
	runs_played = int(cfg.get_value("meta", "runs_played", runs_played))
	var saved_themes: Variant = cfg.get_value("meta", "unlocked_themes", unlocked_themes)
	if saved_themes is PackedStringArray:
		unlocked_themes = saved_themes
	var saved_skins: Variant = cfg.get_value("meta", "unlocked_skins", unlocked_skins)
	if saved_skins is PackedStringArray:
		unlocked_skins = saved_skins

func _save_progress() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("meta", "high_score", high_score)
	cfg.set_value("meta", "runs_played", runs_played)
	cfg.set_value("meta", "unlocked_themes", unlocked_themes)
	cfg.set_value("meta", "unlocked_skins", unlocked_skins)
	cfg.save(SAVE_PATH)
