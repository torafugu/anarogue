extends Control

var menu: VBoxContainer
var form: VBoxContainer
var strategy: OptionButton
var inputs: Dictionary = {}
var execute_button: Button
var status: Label
var request: HTTPRequest
var poll_timer: Timer
var request_kind := ""
var busy := false

func _ready() -> void:
	# Apply an explicit offline replay launch once, preserving later Home navigation.
	if not RunSession.launch_handled:
		RunSession.launch_handled = true
		for argument in OS.get_cmdline_user_args():
			if argument == "--replay" or argument.begins_with("--replay="):
				open_replay.call_deferred()
				return
	var background := ColorRect.new()
	background.color = Color("#15171d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 40
	margin.theme = ui_theme
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 24)
	scroll.add_child(contents)
	var title := label("AnaRogue")
	title.add_theme_font_size_override("font_size", 64)
	contents.add_child(title)
	menu = VBoxContainer.new()
	menu.name = "MainMenu"
	menu.add_theme_constant_override("separation", 24)
	contents.add_child(menu)
	menu.add_child(label("Create a new Run or replay a saved Run."))
	button(menu, "Run", show_form, "RunMenuButton")
	button(menu, "Replay", open_replay, "ReplayMenuButton")
	form = VBoxContainer.new()
	form.name = "RunForm"
	form.add_theme_constant_override("separation", 20)
	contents.add_child(form)
	form.hide()
	button(form, "Back", show_menu, "BackButton")
	form.add_child(label("Run settings"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 16)
	form.add_child(grid)
	grid.add_child(label("Strategy"))
	strategy = OptionButton.new()
	strategy.get_popup().theme = ui_theme
	strategy.name = "Strategy"
	strategy.add_item("Aggressive")
	strategy.add_item("Cautious")
	strategy.custom_minimum_size.y = 88
	strategy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(strategy)
	strategy.select(1 if RunSession.settings["strategy"] == "cautious" else 0)
	strategy.item_selected.connect(strategy_changed)
	number_field(grid, "Seed", "seed", 0, 4294967295)
	number_field(grid, "Enemy weight", "enemy_weight", 0, 1000)
	number_field(grid, "Treasure weight", "item_weight", 0, 1000)
	number_field(grid, "Stairs weight", "stairs_weight", 0, 1000)
	number_field(grid, "Max turns", "max_turns", 1, 100000)
	form.add_child(label("Weights affect goal selection alongside benefit and danger. At least one weight must be positive."))
	execute_button = button(form, "Run", execute_run, "ExecuteRunButton")
	button(form, "Replay", open_replay, "FormReplayButton")
	status = label("")
	status.name = "RunStatus"
	form.add_child(status)
	request = HTTPRequest.new()
	add_child(request)
	request.timeout = 10
	request.request_completed.connect(request_completed)
	poll_timer = Timer.new()
	add_child(poll_timer)
	poll_timer.wait_time = 1
	poll_timer.timeout.connect(poll_job)
	if not RunSession.job_id.is_empty():
		show_form()
		set_busy(true)
		status.text = "Checking your Run…"
		poll_timer.start()
		poll_job()

func label(text: String) -> Label:
	var control := Label.new()
	control.text = text
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return control

func button(parent: Node, text: String, callback: Callable, node_name: String) -> Button:
	var control := Button.new()
	control.text = text
	control.name = node_name
	control.custom_minimum_size.y = 88
	control.pressed.connect(callback)
	parent.add_child(control)
	return control

func number_field(grid: GridContainer, text: String, field: String, minimum: int, maximum: int) -> void:
	grid.add_child(label(text))
	var input := SpinBox.new()
	input.name = field.to_pascal_case()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = RunSession.settings[field]
	input.custom_minimum_size = Vector2(360, 88)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(input)
	inputs[field] = input
	input.value_changed.connect(func(value): RunSession.settings[field] = int(value))

func show_form() -> void:
	menu.hide()
	form.show()

func show_menu() -> void:
	if request_kind == "start":
		return
	form.hide()
	menu.show()

func strategy_changed(index: int) -> void:
	RunSession.settings["strategy"] = "cautious" if index == 1 else "aggressive"
	inputs["enemy_weight"].value = 1 if index == 1 else 4
	inputs["item_weight"].value = 2
	inputs["stairs_weight"].value = 4 if index == 1 else 1

func current_settings() -> Dictionary:
	# Commit typed text even when the virtual keyboard still has focus.
	for field in inputs:
		var input: SpinBox = inputs[field]
		if input.get_line_edit().has_focus():
			input.apply()
		RunSession.settings[field] = int(input.value)
	return RunSession.settings.duplicate()

func set_busy(value: bool) -> void:
	busy = value
	execute_button.disabled = value
	strategy.disabled = value
	for input in inputs.values():
		input.editable = not value

func execute_run() -> void:
	if busy:
		return
	var settings := current_settings()
	if int(settings["enemy_weight"]) + int(settings["item_weight"]) + int(settings["stairs_weight"]) == 0:
		status.text = "At least one goal weight must be positive."
		return
	set_busy(true)
	status.text = "Starting Run…"
	request_kind = "start"
	set_navigation_enabled(false)
	var error := request.request(RunSession.api_url() + "/api/jobs", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(settings))
	if error != OK:
		request_kind = ""
		set_navigation_enabled(true)
		set_busy(false)
		status.text = "Could not start Run (error %d)." % error

func poll_job() -> void:
	if not request_kind.is_empty() or RunSession.job_id.is_empty():
		return
	request_kind = "poll"
	var error := request.request(RunSession.api_url() + "/api/jobs/" + RunSession.job_id.uri_encode())
	if error != OK:
		request_kind = ""
		status.text = "Connection lost. Retrying…"

func request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := request_kind
	request_kind = ""
	set_navigation_enabled(true)
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or not data is Dictionary or code < 200 or code >= 300:
		if kind == "poll" and code != 404:
			status.text = "Could not check Run. Retrying…"
			return
		poll_timer.stop()
		RunSession.job_id = ""
		set_busy(false)
		status.text = str(data.get("error", "Run API unavailable. Start tools/run_store.py serve.")) if data is Dictionary else "Run API unavailable. Start tools/run_store.py serve."
		return
	if kind == "start":
		RunSession.job_id = str(data["id"])
		poll_timer.start()
	match str(data.get("status", "")):
		"queued": status.text = "Run queued…"
		"running": status.text = "Running… Results will open when the Run finishes."
		"failed":
			poll_timer.stop()
			RunSession.job_id = ""
			set_busy(false)
			status.text = "Run failed: " + str(data.get("error", "Unknown error"))
		"completed":
			poll_timer.stop()
			RunSession.job_id = ""
			RunSession.replay_run_key = str(data["run_id"])
			open_replay()

func set_navigation_enabled(value: bool) -> void:
	form.get_node("BackButton").disabled = not value
	form.get_node("FormReplayButton").disabled = not value

func open_replay() -> void:
	if request_kind == "start":
		return
	get_tree().change_scene_to_file("res://scenes/replay.tscn")
