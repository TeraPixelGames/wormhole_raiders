extends Node
#class_name AdManager

signal rewarded_loaded(ready: bool)
signal interstitial_loaded(ready: bool)
signal rewarded_granted()
signal rewarded_failed()
signal rewarded_closed()
signal interstitial_closed()

const APP_ID := "ca-app-pub-8413230766502262~7166483341"
const INTERSTITIAL_ID := "ca-app-pub-8413230766502262/6763158660"
const REWARDED_ID := "ca-app-pub-8413230766502262/8678767766"

@export var interstitial_every_n_runs: int = 3
@export var retry_base_seconds: float = 2.0
@export var retry_max_seconds: float = 20.0

var _admob: Object = null
var _rewarded_ad: Object = null
var _interstitial_ad: Object = null
var _initialized: bool = false
var _rewarded_ready: bool = false
var _interstitial_ready: bool = false
var _rewarded_retry_count: int = 0
var _interstitial_retry_count: int = 0
var _finalized_run_count: int = 0
var _rewarded_recently: bool = false

func _ready() -> void:
	initialize_ads()

func initialize_ads() -> void:
	if _initialized:
		return
	_initialized = true
	_admob = _find_mobile_ads_initializer()
	_plugin_initialize()
	preload_rewarded()
	preload_interstitial()

func is_rewarded_ready() -> bool:
	return _rewarded_ready

func is_interstitial_ready() -> bool:
	return _interstitial_ready

func preload_rewarded() -> void:
	_destroy_if_needed(_rewarded_ad)
	_rewarded_ad = null
	_rewarded_ready = false
	emit_signal("rewarded_loaded", false)
	var cb := _new_instance("RewardedAdLoadCallback")
	var loader := _new_instance("RewardedAdLoader")
	var request := _new_instance("AdRequest")
	if cb == null or loader == null or request == null:
		_schedule_rewarded_retry()
		return

	cb.set("on_ad_failed_to_load", func(_ad_error: Variant) -> void:
		_rewarded_ready = false
		emit_signal("rewarded_loaded", false)
		_schedule_rewarded_retry()
	)
	cb.set("on_ad_loaded", func(rewarded_ad: Object) -> void:
		_destroy_if_needed(_rewarded_ad)
		_rewarded_ad = rewarded_ad
		_attach_full_screen_callbacks(_rewarded_ad, true)
		_rewarded_ready = true
		_rewarded_retry_count = 0
		emit_signal("rewarded_loaded", true)
	)
	loader.call("load", REWARDED_ID, request, cb)

func preload_interstitial() -> void:
	_destroy_if_needed(_interstitial_ad)
	_interstitial_ad = null
	_interstitial_ready = false
	emit_signal("interstitial_loaded", false)
	var cb := _new_instance("InterstitialAdLoadCallback")
	var loader := _new_instance("InterstitialAdLoader")
	var request := _new_instance("AdRequest")
	if cb == null or loader == null or request == null:
		_schedule_interstitial_retry()
		return

	cb.set("on_ad_failed_to_load", func(_ad_error: Variant) -> void:
		_interstitial_ready = false
		emit_signal("interstitial_loaded", false)
		_schedule_interstitial_retry()
	)
	cb.set("on_ad_loaded", func(interstitial_ad: Object) -> void:
		_destroy_if_needed(_interstitial_ad)
		_interstitial_ad = interstitial_ad
		_attach_full_screen_callbacks(_interstitial_ad, false)
		_interstitial_ready = true
		_interstitial_retry_count = 0
		emit_signal("interstitial_loaded", true)
	)
	loader.call("load", INTERSTITIAL_ID, request, cb)

func show_rewarded_for_continue() -> void:
	if not _rewarded_ready:
		emit_signal("rewarded_failed")
		return
	_rewarded_ready = false
	if _rewarded_ad != null:
		var listener := _new_instance("OnUserEarnedRewardListener")
		if listener != null:
			listener.set("on_user_earned_reward", func(_rewarded_item: Variant) -> void:
				emit_signal("rewarded_granted")
			)
			_rewarded_ad.call("show", listener)
		else:
			_rewarded_ad.call("show")
	# When plugin callbacks are not wired yet, grant immediately in editor for iteration.
	if _rewarded_ad == null and OS.has_feature("editor"):
		emit_signal("rewarded_granted")
		emit_signal("rewarded_closed")
	preload_rewarded()

func maybe_show_interstitial_after_run() -> bool:
	_finalized_run_count += 1
	if _rewarded_recently:
		_rewarded_recently = false
		return false
	var capped : int = (_finalized_run_count % max(interstitial_every_n_runs, 1)) == 0
	if not capped or not _interstitial_ready:
		return false
	_interstitial_ready = false
	if _interstitial_ad != null:
		_interstitial_ad.call("show")
	else:
		emit_signal("interstitial_closed")
	preload_interstitial()
	return true

func mark_rewarded_continue_used() -> void:
	_rewarded_recently = true

func _find_mobile_ads_initializer() -> Object:
	var names := ["MobileAds", "AdMob", "Admob"]
	for n in names:
		if Engine.has_singleton(n):
			return Engine.get_singleton(n)
	return null

func _plugin_initialize() -> void:
	if _admob != null:
		if _admob.has_method("initialize"):
			_admob.call("initialize")
		elif _admob.has_method("init"):
			_admob.call("init")
		return

	var mobile_ads := _new_instance("MobileAds")
	if mobile_ads != null and mobile_ads.has_method("initialize"):
		mobile_ads.call("initialize")

func _schedule_rewarded_retry() -> void:
	_rewarded_retry_count += 1
	var delay : int = min(retry_base_seconds * pow(2.0, float(_rewarded_retry_count - 1)), retry_max_seconds)
	get_tree().create_timer(delay).timeout.connect(preload_rewarded)

func _schedule_interstitial_retry() -> void:
	_interstitial_retry_count += 1
	var delay : int = min(retry_base_seconds * pow(2.0, float(_interstitial_retry_count - 1)), retry_max_seconds)
	get_tree().create_timer(delay).timeout.connect(preload_interstitial)

func _new_instance(gd_class_name: String) -> Object:
	if not ClassDB.class_exists(gd_class_name):
		return null
	return ClassDB.instantiate(gd_class_name)

func _attach_full_screen_callbacks(ad_obj: Object, is_rewarded: bool) -> void:
	if ad_obj == null:
		return
	var cb := _new_instance("FullScreenContentCallback")
	if cb == null:
		return
	cb.set("on_ad_dismissed_full_screen_content", func() -> void:
		if is_rewarded:
			emit_signal("rewarded_closed")
		else:
			emit_signal("interstitial_closed")
	)
	cb.set("on_ad_failed_to_show_full_screen_content", func(_ad_error: Variant) -> void:
		if is_rewarded:
			emit_signal("rewarded_failed")
			emit_signal("rewarded_closed")
		else:
			emit_signal("interstitial_closed")
	)
	ad_obj.set("full_screen_content_callback", cb)

func _destroy_if_needed(ad_obj: Object) -> void:
	if ad_obj != null and ad_obj.has_method("destroy"):
		ad_obj.call("destroy")
