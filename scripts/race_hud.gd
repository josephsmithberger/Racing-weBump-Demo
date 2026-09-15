class_name RaceHUD extends CanvasLayer

@export var race_manager: RaceManager
@export var view_camera: Node3D

var _audio: RaceAudio

# UI references
@onready var lap_badge: PanelContainer = %LapBadge
@onready var lap_label: Label = %LapLabel

@onready var timer_badge: PanelContainer = %TimerBadge
@onready var timer_label: Label = %TimerLabel
@onready var best_label: Label = %BestLabel

@onready var countdown_container: Control = %CountdownContainer
@onready var countdown_banner: ColorRect = %CountdownBanner
@onready var countdown_label: Label = %CountdownLabel

@onready var split_toast: PanelContainer = %SplitToast
@onready var split_label: Label = %SplitLabel

@onready var final_lap_banner: Control = %FinalLapBanner
@onready var final_lap_label: Label = %FinalLapLabel

@onready var finish_banner: Control = %FinishBanner
@onready var finish_label: Label = %FinishLabel
@onready var flash_rect: ColorRect = %FlashRect

@onready var results_screen: Control = %ResultsScreen
@onready var results_card: PanelContainer = %ResultsCard
@onready var result_total_time: Label = %ResultTotalTime
@onready var leaderboard_rows: VBoxContainer = %LeaderboardRows
@onready var result_best_lap: Label = %ResultBestLap
@onready var ghost_sync_label: Label = %GhostSyncLabel
@onready var retry_button: Button = %RetryButton
@onready var title_button: Button = %TitleButton

func _ready() -> void:
	# Add procedural audio synthesizer
	_audio = RaceAudio.new()
	add_child(_audio)
	
	# Initial visibility
	countdown_container.visible = false
	split_toast.visible = false
	final_lap_banner.visible = false
	finish_banner.visible = false
	flash_rect.visible = false
	results_screen.visible = false
	
	# Connect buttons
	retry_button.pressed.connect(_on_retry_pressed)
	title_button.pressed.connect(_on_title_pressed)
	retry_button.mouse_entered.connect(_on_button_hover)
	title_button.mouse_entered.connect(_on_button_hover)
	retry_button.mouse_entered.connect(func(): _animate_btn(retry_button, 1.06))
	retry_button.mouse_exited.connect(func(): _animate_btn(retry_button, 1.0))
	title_button.mouse_entered.connect(func(): _animate_btn(title_button, 1.06))
	title_button.mouse_exited.connect(func(): _animate_btn(title_button, 1.0))
	
	# Connect to RaceManager
	if race_manager == null:
		race_manager = get_node_or_null("../RaceManager") as RaceManager
	
	if race_manager:
		race_manager.countdown_tick.connect(_on_countdown_tick)
		race_manager.race_started.connect(_on_race_started)
		race_manager.lap_completed.connect(_on_lap_completed)
		race_manager.final_lap_started.connect(_on_final_lap_started)
		race_manager.race_finished.connect(_on_race_finished)
		race_manager.timer_updated.connect(_on_timer_updated)
	
	_update_lap_display(1, 3)
	best_label.text = "BEST: --:--.--"

func _process(_delta: float) -> void:
	if results_screen.visible and race_manager:
		var recorder := race_manager.get_node_or_null("GhostRecorder") as GhostRecorder
		if recorder:
			ghost_sync_label.text = recorder.result_message

func format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.--"
	var minutes: int = int(seconds / 60.0)
	var secs: int = int(fmod(seconds, 60.0))
	var centis: int = int(fmod(seconds, 1.0) * 100.0)
	return "%02d:%02d.%02d" % [minutes, secs, centis]

func _on_timer_updated(lap_time: float, _total_time: float) -> void:
	timer_label.text = format_time(lap_time)

func _update_lap_display(lap: int, max_laps: int) -> void:
	if lap >= max_laps:
		lap_label.text = "FINAL LAP"
	else:
		lap_label.text = "LAP %d/%d" % [lap, max_laps]

# ==========================================
# 3-2-1-GO COUNTDOWN (SAKURAI IMPACT STYLE)
# ==========================================

func _on_countdown_tick(num: int) -> void:
	countdown_container.visible = true
	countdown_label.text = str(num)
	_audio.play_countdown()
	
	# Color and slant style per number
	var col: Color = Color("#FFB300") # 3 = Amber Gold
	var slant: float = -0.1
	if num == 2:
		col = Color("#00E5FF") # 2 = Cyan Blue
		slant = 0.08
	elif num == 1:
		col = Color("#FF1744") # 1 = Fiery Red
		slant = -0.12
	
	countdown_label.modulate = col
	countdown_banner.color = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.6)
	
	# Animate banner slice
	countdown_banner.pivot_offset = countdown_banner.size / 2.0
	countdown_banner.scale = Vector2(0.0, 1.0)
	var banner_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(countdown_banner, "scale", Vector2(1.0, 1.0), 0.15)
	
	# Sakurai scale slam: 2.6x -> 0.95x -> 1.0x with overshoot
	countdown_label.pivot_offset = countdown_label.size / 2.0
	countdown_label.scale = Vector2(2.6, 2.6)
	countdown_label.rotation = slant * 1.5
	
	var slam_tween = create_tween().set_parallel(true)
	slam_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slam_tween.tween_property(countdown_label, "scale", Vector2(1.0, 1.0), 0.35)
	slam_tween.tween_property(countdown_label, "rotation", slant, 0.35)
	
	if view_camera and view_camera.has_method("shake"):
		view_camera.shake(0.2, 0.2)

func _on_race_started() -> void:
	countdown_container.visible = true
	countdown_label.text = "GO!"
	countdown_label.modulate = Color("#76FF03") # Electric Lime
	countdown_banner.color = Color(0.05, 0.3, 0.05, 0.8)
	_audio.play_go()
	
	# High impact screen shake on GO
	if view_camera and view_camera.has_method("shake"):
		view_camera.shake(0.5, 0.4)
	
	countdown_label.pivot_offset = countdown_label.size / 2.0
	countdown_label.scale = Vector2(3.2, 3.2)
	countdown_label.rotation = -0.08
	
	var go_tween = create_tween()
	go_tween.set_parallel(true)
	go_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	go_tween.tween_property(countdown_label, "scale", Vector2(1.1, 1.1), 0.28)
	go_tween.tween_property(countdown_banner, "scale", Vector2(1.2, 1.2), 0.28)
	
	# Dismiss GO after short hang
	go_tween.chain().set_parallel(true)
	go_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	go_tween.tween_property(countdown_label, "scale", Vector2(0.4, 0.4), 0.25).set_delay(0.45)
	go_tween.tween_property(countdown_container, "modulate:a", 0.0, 0.25).set_delay(0.45)
	go_tween.chain().tween_callback(func():
		countdown_container.visible = false
		countdown_container.modulate.a = 1.0
	)

# ==========================================
# LAP PROGRESSION & FINAL LAP ALERT
# ==========================================

func _on_lap_completed(completed_lap: int, lap_time: float, is_best: bool) -> void:
	_audio.play_lap()
	var next_lap = completed_lap + 1
	var max_laps = race_manager.max_laps if race_manager else 3
	_update_lap_display(next_lap, max_laps)
	
	if race_manager and race_manager.best_lap_time > 0.0:
		best_label.text = "BEST: " + format_time(race_manager.best_lap_time)
	
	# Bounce lap badge
	lap_badge.pivot_offset = lap_badge.size / 2.0
	var badge_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	badge_tween.tween_property(lap_badge, "scale", Vector2(1.35, 1.35), 0.15)
	badge_tween.tween_property(lap_badge, "scale", Vector2(1.0, 1.0), 0.2)
	
	# Show split toast notification
	split_toast.visible = true
	var best_tag: String = " [BEST!]" if is_best else ""
	split_label.text = "LAP %d: %s%s" % [completed_lap, format_time(lap_time), best_tag]
	split_label.modulate = Color("#FFEA00") if is_best else Color("#FFFFFF")
	
	split_toast.pivot_offset = split_toast.size / 2.0
	split_toast.scale = Vector2(0.8, 0.8)
	split_toast.modulate.a = 0.0
	
	var toast_tween = create_tween()
	toast_tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	toast_tween.tween_property(split_toast, "scale", Vector2(1.0, 1.0), 0.2)
	toast_tween.tween_property(split_toast, "modulate:a", 1.0, 0.2)
	
	# Fade out toast after 2.2 seconds
	toast_tween.chain().tween_interval(2.0)
	toast_tween.chain().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	toast_tween.tween_property(split_toast, "modulate:a", 0.0, 0.3)
	toast_tween.chain().tween_callback(func(): split_toast.visible = false)

func _on_final_lap_started() -> void:
	_audio.play_final_lap()
	final_lap_banner.visible = true
	final_lap_banner.modulate.a = 1.0
	
	# Camera rumble
	if view_camera and view_camera.has_method("shake"):
		view_camera.shake(0.4, 0.35)
	
	# Diagonal caution banner sweeps across
	final_lap_banner.position.x = -1280.0
	var banner_tween = create_tween()
	banner_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(final_lap_banner, "position:x", 0.0, 0.3)
	
	# Pulse scale
	final_lap_label.pivot_offset = final_lap_label.size / 2.0
	var pulse_tween = create_tween().set_loops(3)
	pulse_tween.tween_property(final_lap_label, "scale", Vector2(1.15, 1.15), 0.15)
	pulse_tween.tween_property(final_lap_label, "scale", Vector2(1.0, 1.0), 0.15)
	
	# Slide out banner
	banner_tween.chain().tween_interval(1.2)
	banner_tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	banner_tween.tween_property(final_lap_banner, "position:x", 1280.0, 0.28)
	banner_tween.chain().tween_callback(func(): final_lap_banner.visible = false)

# ==========================================
# FINISH SEQUENCE & RESULTS SCREEN
# ==========================================

func _on_race_finished(total_time: float, lap_times: Array, best_lap_time: float) -> void:
	_audio.play_finish()
	lap_badge.hide()
	timer_badge.hide()
	countdown_container.visible = false
	final_lap_banner.visible = false
	split_toast.visible = false
	
	# Dramatic slow-mo freeze frame impact (Classic Smash "GAME!" / "FINISH!")
	Engine.time_scale = 0.25
	var time_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	time_tween.tween_interval(0.4)
	time_tween.tween_property(Engine, "time_scale", 1.0, 0.3)
	
	# White flash overlay
	flash_rect.visible = true
	flash_rect.modulate = Color(1, 1, 1, 0.85)
	var flash_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	flash_tween.tween_property(flash_rect, "modulate:a", 0.0, 0.4)
	flash_tween.tween_callback(func(): flash_rect.visible = false)
	
	# Camera intense impact shake
	if view_camera and view_camera.has_method("shake"):
		view_camera.shake(0.8, 0.5)
	
	# Huge "FINISH!" banner slam diagonally across screen
	finish_banner.visible = true
	finish_banner.modulate.a = 1.0
	finish_label.pivot_offset = finish_label.size / 2.0
	finish_label.scale = Vector2(3.5, 3.5)
	finish_label.rotation = -0.12
	
	var finish_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	finish_tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	finish_tween.tween_property(finish_label, "scale", Vector2(1.0, 1.0), 0.32)
	finish_tween.tween_property(finish_label, "rotation", -0.06, 0.32)
	
	# Hold FINISH! banner, then transition into Results Card
	finish_tween.chain().tween_interval(1.4)
	finish_tween.chain().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	finish_tween.tween_property(finish_banner, "modulate:a", 0.0, 0.3)
	finish_tween.chain().tween_callback(func():
		finish_banner.visible = false
		_show_results(total_time, lap_times, best_lap_time)
	)

func _show_results(total_time: float, lap_times: Array, best_lap_time: float) -> void:
	results_screen.visible = true
	results_screen.modulate.a = 0.0
	
	var player_position := 1
	for row in race_manager.leaderboard:
		if row.id == "player":
			player_position = row.position
	result_total_time.text = "YOU PLACED %d / %d  ·  %s" % [player_position, race_manager.leaderboard.size(), format_time(total_time)]
	for child in leaderboard_rows.get_children():
		child.queue_free()
	for row in race_manager.leaderboard:
		_add_leaderboard_row(row)
	var splits: PackedStringArray = []
	for lap in lap_times:
		splits.append(format_time(lap))
	result_best_lap.text = "YOUR LAPS  " + "  /  ".join(splits) + "\nBEST LAP  " + format_time(best_lap_time)
	var recorder := race_manager.get_node_or_null("GhostRecorder") as GhostRecorder
	ghost_sync_label.text = recorder.result_message if recorder else ""

	# Animate card sliding in with diagonal spring overshoot
	results_card.pivot_offset = results_card.size / 2.0
	results_card.scale = Vector2(0.6, 0.6)
	results_card.rotation = 0.06
	
	var card_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	card_tween.set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_tween.tween_property(results_screen, "modulate:a", 1.0, 0.25)
	card_tween.tween_property(results_card, "scale", Vector2(1.0, 1.0), 0.35)
	card_tween.tween_property(results_card, "rotation", 0.0, 0.35)
	
	retry_button.grab_focus()

func _add_leaderboard_row(row: Dictionary) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.23, 0.28, 1) if row.id == "player" else Color(0.09, 0.11, 0.17, 1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	panel.add_child(columns)
	var rank := Label.new()
	rank.text = "%02d" % row.position
	rank.custom_minimum_size.x = 38
	rank.add_theme_font_size_override("font_size", 24)
	columns.add_child(rank)
	var swatch := ColorRect.new()
	swatch.color = row.color
	swatch.custom_minimum_size = Vector2(6, 40)
	columns.add_child(swatch)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(identity)
	var driver := Label.new()
	driver.text = row.display_name + (" (YOU)" if row.id == "player" else "")
	driver.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	driver.add_theme_font_size_override("font_size", 21)
	identity.add_child(driver)
	var car := Label.new()
	car.text = "%s · %s" % [CarPresets.get_preset_by_id(row.car_body).name, row.kind]
	car.add_theme_font_size_override("font_size", 13)
	car.modulate = Color(0.68, 0.75, 0.83)
	identity.add_child(car)
	var status := Label.new()
	status.text = row.status
	status.custom_minimum_size.x = 95
	status.modulate = Color.GOLD if row.status == "Estimated" else Color(0.68, 0.75, 0.83)
	columns.add_child(status)
	var time := Label.new()
	time.text = ("≈ " if row.status == "Estimated" else "") + format_time(row.time)
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time.custom_minimum_size.x = 140
	time.add_theme_font_size_override("font_size", 22)
	columns.add_child(time)
	leaderboard_rows.add_child(panel)

func _on_button_hover() -> void:
	_audio.play_hover()

func _on_retry_pressed() -> void:
	_audio.play_click()
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

func _on_title_pressed() -> void:
	_audio.play_click()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")

func _animate_btn(btn: Button, target_scale: float) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(btn, "scale", Vector2(target_scale, target_scale), 0.15)
