extends Control

var menu: VBoxContainer
var form: VBoxContainer
var preset_selector: OptionButton
var preset_summary: Label
var presets: Array = []
var reload_button: Button
var execute_button: Button
var cancel_button: Button
var batch_panel: VBoxContainer
var batch_progress: ProgressBar
var batch_summary: Label
var batch_current: Label
var batch_notice: Label
var status: Label
var request: HTTPRequest
var poll_timer: Timer
var request_kind := ""
var busy := false
var jobs_panel: VBoxContainer
var jobs_selector: OptionButton
var jobs_summary: Label
var jobs_status: Label
var jobs_request: HTTPRequest
var jobs_timer: Timer
var shared_jobs: Array = []
var jobs_loading := false
var jobs_offset := 0
var jobs_total := 0
var monitor_button: Button
var job_replay_button: Button
var jobs_previous: Button
var jobs_next: Button

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
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	create_progress_panel(layout)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
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
	button(menu, "Jobs", show_jobs, "JobsMenuButton")
	button(menu, "Replay", open_replay, "ReplayMenuButton")
	form = VBoxContainer.new()
	form.name = "RunForm"
	form.add_theme_constant_override("separation", 20)
	contents.add_child(form)
	form.hide()
	button(form, "Back", show_menu, "BackButton")
	form.add_child(label("Select a Run preset"))
	form.add_child(label("Create and edit named settings in the Web Viewer → Run presets. Select one here to run it."))
	preset_selector = OptionButton.new()
	preset_selector.name = "PresetSelector"
	preset_selector.custom_minimum_size.y = 88
	preset_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_selector.get_popup().theme = ui_theme
	preset_selector.item_selected.connect(select_preset)
	form.add_child(preset_selector)
	reload_button = button(form, "Reload presets", load_presets, "ReloadPresetsButton")
	preset_summary = label("")
	preset_summary.name = "PresetSummary"
	form.add_child(preset_summary)
	execute_button = button(form, "Run selected preset", execute_run, "ExecuteRunButton")
	execute_button.disabled = true
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
	create_jobs_panel(contents)
	if not RunSession.batch_snapshot.is_empty():
		show_batch_progress(RunSession.batch_snapshot)
	if not RunSession.job_id.is_empty():
		show_form()
		set_busy(true)
		status.text = "Checking your Run…"
		show_batch_notice("Checking latest progress…")
		poll_timer.start()
		poll_job()
	else:
		load_presets()

func create_progress_panel(parent: Node) -> void:
	batch_panel = VBoxContainer.new()
	batch_panel.name = "AutoRunProgress"
	batch_panel.add_theme_constant_override("separation", 8)
	parent.add_child(batch_panel)
	batch_summary = label("")
	batch_summary.name = "ProgressSummary"
	batch_summary.add_theme_font_size_override("font_size", 28)
	batch_panel.add_child(batch_summary)
	batch_progress = ProgressBar.new()
	batch_progress.name = "ProgressBar"
	batch_progress.custom_minimum_size.y = 28
	batch_progress.show_percentage = false
	batch_panel.add_child(batch_progress)
	batch_current = label("")
	batch_current.add_theme_font_size_override("font_size", 24)
	batch_panel.add_child(batch_current)
	batch_notice = label("")
	batch_notice.add_theme_font_size_override("font_size", 22)
	batch_panel.add_child(batch_notice)
	batch_notice.hide()
	cancel_button = button(batch_panel, "Stop after current Run", cancel_autorun, "CancelAutoRunButton")
	cancel_button.custom_minimum_size.y = 64
	cancel_button.add_theme_font_size_override("font_size", 24)
	cancel_button.hide()
	batch_panel.hide()

func show_batch_progress(data: Dictionary) -> void:
	RunSession.batch_snapshot = data.duplicate(true)
	var total := maxi(1, int(data.get("total", 1)))
	var completed := int(data.get("completed", 0))
	var failed := int(data.get("failed", 0))
	var finished := completed + failed
	var state := str(data.get("status", "queued"))
	batch_progress.max_value = total
	batch_progress.value = finished
	batch_summary.text = "AutoRun %s · %d/%d (%.1f%%)\nSaved %d · Failed %d" % [state, finished, total, 100.0 * finished / total, completed, failed]
	var current = data.get("current_settings")
	batch_current.visible = current is Dictionary and state == "running"
	if current is Dictionary:
		batch_current.text = "Run %d · %s · Enemy %d / Treasure %d / Stairs %d" % [mini(total, finished + 1), str(current["strategy"]).capitalize(), current["enemy_weight"], current["item_weight"], current["stairs_weight"]]
	cancel_button.visible = state in ["starting", "queued", "running"]
	cancel_button.disabled = state == "starting" or bool(data.get("cancel_requested", false))
	batch_panel.show()
	show_batch_notice("Stopping after the current Run…" if bool(data.get("cancel_requested", false)) and state == "running" else "")

func show_batch_notice(message: String) -> void:
	if RunSession.job_kind != "batch":
		return
	batch_notice.text = message
	batch_notice.visible = not message.is_empty()

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

func show_form() -> void:
	jobs_panel.hide()
	menu.hide()
	form.show()

func show_menu() -> void:
	if request_kind != "start":
		form.hide()
		jobs_panel.hide()
		menu.show()

func create_jobs_panel(parent: Node) -> void:
	jobs_panel = VBoxContainer.new()
	jobs_panel.name = "SharedJobs"
	jobs_panel.add_theme_constant_override("separation", 20)
	parent.add_child(jobs_panel)
	jobs_panel.hide()
	button(jobs_panel, "Back", show_menu, "JobsBackButton")
	jobs_panel.add_child(label("Shared jobs · all devices"))
	jobs_selector = OptionButton.new()
	jobs_selector.name = "JobSelector"
	jobs_selector.theme = preset_selector.theme
	jobs_selector.custom_minimum_size.y = 88
	jobs_selector.item_selected.connect(select_shared_job)
	jobs_panel.add_child(jobs_selector)
	jobs_summary = label("")
	jobs_panel.add_child(jobs_summary)
	monitor_button = button(jobs_panel, "Monitor selected job", monitor_shared_job, "MonitorJobButton")
	job_replay_button = button(jobs_panel, "Replay latest Run", replay_shared_job, "ReplayJobButton")
	button(jobs_panel, "Refresh jobs", refresh_jobs, "RefreshJobsButton")
	jobs_previous = button(jobs_panel, "Previous jobs", previous_jobs, "PreviousJobsButton")
	jobs_next = button(jobs_panel, "Next jobs", next_jobs, "NextJobsButton")
	jobs_status = label("")
	jobs_status.name = "JobsStatus"
	jobs_panel.add_child(jobs_status)
	jobs_request = HTTPRequest.new()
	jobs_request.timeout = 10
	jobs_request.request_completed.connect(shared_jobs_completed)
	add_child(jobs_request)
	jobs_timer = Timer.new()
	jobs_timer.wait_time = 2
	jobs_timer.timeout.connect(refresh_jobs)
	add_child(jobs_timer)
	monitor_button.disabled = true
	job_replay_button.disabled = true

func show_jobs() -> void:
	menu.hide()
	form.hide()
	jobs_panel.show()
	jobs_timer.start()
	refresh_jobs()

func refresh_jobs() -> void:
	if jobs_loading or not jobs_panel.visible:
		return
	jobs_loading = true
	if jobs_request.request(RunSession.api_url() + "/api/jobs?limit=20&offset=%d" % jobs_offset) != OK:
		jobs_loading = false
		jobs_status.text = "Jobs unavailable. Please retry."

func shared_jobs_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	jobs_loading = false
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary:
		jobs_status.text = "Jobs unavailable. Retrying…"
		return
	var wanted := ""
	if jobs_selector.selected >= 0 and jobs_selector.selected < shared_jobs.size():
		wanted = str(shared_jobs[jobs_selector.selected]["id"])
	shared_jobs = data.get("jobs", [])
	jobs_total = int(data.get("total", 0))
	jobs_selector.clear()
	var selected := 0
	for index in range(shared_jobs.size()):
		var job: Dictionary = shared_jobs[index]
		var preset: Dictionary = job.get("preset", {})
		var name := str(preset.get("name", str(job["kind"]).capitalize()))
		jobs_selector.add_item("%s · %s" % [name, "interrupted" if job.get("interrupted", false) else job["status"]])
		if job["id"] == wanted:
			selected = index
	if not shared_jobs.is_empty():
		jobs_selector.select(selected)
	select_shared_job(selected)
	jobs_previous.disabled = jobs_offset == 0
	jobs_next.disabled = jobs_offset + 20 >= jobs_total
	jobs_status.text = "%d shared jobs · refreshed automatically" % jobs_total

func select_shared_job(index: int) -> void:
	monitor_button.disabled = shared_jobs.is_empty()
	job_replay_button.disabled = true
	if shared_jobs.is_empty():
		jobs_summary.text = "No jobs yet. Start a saved preset in Viewer or Run."
		return
	var job: Dictionary = shared_jobs[index]
	jobs_summary.text = "%s\n%s\n%s" % [job["id"], job["status"], job.get("created_at", "")]
	if job["kind"] == "batch":
		jobs_summary.text += "\n%d/%d saved · %d failed" % [int(job.get("completed", 0)), int(job.get("total", 0)), int(job.get("failed", 0))]
	if job.get("error") is String:
		jobs_summary.text += "\n" + job["error"]
	job_replay_button.disabled = not job.get("run_id") is String or str(job.get("run_id", "")).is_empty()

func monitor_shared_job() -> void:
	if shared_jobs.is_empty() or not request_kind.is_empty():
		return
	var job: Dictionary = shared_jobs[jobs_selector.selected]
	RunSession.job_id = str(job["id"])
	RunSession.job_kind = str(job["kind"])
	RunSession.batch_snapshot.clear()
	show_form()
	set_busy(true)
	poll_timer.start()
	poll_job()

func replay_shared_job() -> void:
	if shared_jobs.is_empty():
		return
	var run = shared_jobs[jobs_selector.selected].get("run_id")
	if run is String and not run.is_empty():
		RunSession.replay_run_key = run
		open_replay()

func previous_jobs() -> void:
	if not jobs_loading:
		jobs_offset = maxi(0, jobs_offset - 20)
		refresh_jobs()

func next_jobs() -> void:
	if not jobs_loading and jobs_offset + 20 < jobs_total:
		jobs_offset += 20
		refresh_jobs()

func load_presets() -> void:
	if busy or not request_kind.is_empty():
		return
	request_kind = "presets"
	set_busy(true)
	status.text = "Loading presets…"
	if request.request(RunSession.api_url() + "/api/presets") != OK:
		request_kind = ""
		set_busy(false)
		status.text = "Could not load presets. Start the Run API and retry."

func selected_preset() -> Dictionary:
	var index := preset_selector.selected
	return presets[index] if index >= 0 and index < presets.size() else {}

func select_preset(_index: int) -> void:
	var preset := selected_preset()
	if preset.is_empty():
		preset_summary.text = "No presets yet. Create one in the Web Viewer, then Reload presets."
		execute_button.disabled = true
		return
	RunSession.preset_id = str(preset["id"])
	var settings: Dictionary = preset["settings"]
	var policy: String
	if preset["kind"] == "batch":
		policy = "AutoRun · %s\nEnemy %s / Treasure %s / Stairs %s" % [", ".join(settings["strategies"]), str(settings["enemy_weights"]), str(settings["item_weights"]), str(settings["stairs_weights"])]
	else:
		policy = "%s · Enemy %d / Treasure %d / Stairs %d" % [str(settings["strategy"]).capitalize(), settings["enemy_weight"], settings["item_weight"], settings["stairs_weight"]]
	preset_summary.text = "%s · v%d\n%s\nSeed %d · Max turns %d\nMap: Enemy %d%% / Treasure %d%% / Depth %d\nDSL: %s" % [preset["name"], preset["version"], policy, settings["seed"], settings["max_turns"], settings["enemy_amount"], settings["treasure_amount"], settings["map_depth"], "Default AI" if str(settings.get("dsl", "")).strip_edges().is_empty() else "Enabled; declared DSL weights override base values"]
	execute_button.text = "Run selected AutoRun preset" if preset["kind"] == "batch" else "Run selected preset"
	execute_button.disabled = busy

func set_busy(value: bool) -> void:
	busy = value
	preset_selector.disabled = value
	reload_button.disabled = value
	execute_button.disabled = value or selected_preset().is_empty()

func cancel_autorun() -> void:
	if not request_kind.is_empty() or RunSession.job_id.is_empty():
		return
	request_kind = "cancel"
	var error := request.request(RunSession.api_url() + "/api/jobs/" + RunSession.job_id.uri_encode() + "/cancel", ["Content-Type: application/json"], HTTPClient.METHOD_POST, "{}")
	if error != OK:
		request_kind = ""
		status.text = "Could not stop AutoRun. Please retry."
		show_batch_notice(status.text)

func execute_run() -> void:
	if busy or not request_kind.is_empty():
		return
	var preset := selected_preset()
	if preset.is_empty():
		return
	RunSession.job_kind = str(preset["kind"])
	RunSession.batch_snapshot.clear()
	batch_panel.hide()
	set_busy(true)
	status.text = "Starting %s…" % preset["name"]
	request_kind = "start"
	set_navigation_enabled(false)
	var error := request.request(RunSession.api_url() + "/api/presets/" + str(preset["id"]).uri_encode() + "/run", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"version": int(preset["version"])}))
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
		show_batch_notice(status.text)

func request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := request_kind
	request_kind = ""
	set_navigation_enabled(true)
	var data = JSON.parse_string(body.get_string_from_utf8()) if not body.is_empty() else null
	if result != HTTPRequest.RESULT_SUCCESS or not data is Dictionary or code < 200 or code >= 300:
		if kind == "cancel":
			status.text = "Could not stop AutoRun. Please retry."
			show_batch_notice(status.text)
			return
		if kind == "poll" and code != 404:
			status.text = "Could not check Run. Retrying…"
			show_batch_notice(status.text)
			return
		poll_timer.stop()
		RunSession.job_id = ""
		set_busy(false)
		if kind == "presets":
			presets.clear()
			preset_selector.clear()
			select_preset(-1)
		status.text = str(data.get("error", "Run API unavailable. Start tools/run_store.py serve.")) if data is Dictionary else "Run API unavailable. Start tools/run_store.py serve."
		if kind in ["poll", "start"] and RunSession.job_kind == "batch" and not RunSession.batch_snapshot.is_empty():
			var snapshot: Dictionary = RunSession.batch_snapshot.duplicate(true)
			snapshot["status"] = "unavailable"
			show_batch_progress(snapshot)
			show_batch_notice(status.text)
		return
	if kind == "presets":
		presets = data.get("presets", [])
		preset_selector.clear()
		var selection := 0
		for index in range(presets.size()):
			var preset: Dictionary = presets[index]
			preset_selector.add_item("%s · %s · v%d" % [preset["name"], "AutoRun" if preset["kind"] == "batch" else "Run", preset["version"]])
			if preset["id"] == RunSession.preset_id:
				selection = index
		if not presets.is_empty():
			preset_selector.select(selection)
		set_busy(false)
		select_preset(selection)
		status.text = "%d presets loaded. Settings are edited in the Web Viewer." % presets.size()
		return
	if kind == "start":
		RunSession.job_id = str(data["id"])
		poll_timer.start()
	if str(data.get("kind", "run")) == "batch":
		update_autorun_status(data)
		return
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

func update_autorun_status(data: Dictionary) -> void:
	RunSession.job_kind = "batch"
	show_batch_progress(data)
	var progress := "%d/%d Runs saved" % [int(data.get("completed", 0)), int(data.get("total", 0))]
	var state := str(data.get("status", ""))
	cancel_button.disabled = bool(data.get("cancel_requested", false))
	status.text = "AutoRun %s: %s" % [state, progress]
	var current = data.get("current_settings")
	if current is Dictionary:
		status.text += "\n%s · Enemy %d / Treasure %d / Stairs %d" % [str(current["strategy"]).capitalize(), current["enemy_weight"], current["item_weight"], current["stairs_weight"]]
	if bool(data.get("cancel_requested", false)) and state == "running":
		status.text += "\nStopping after the current Run…"
	if state in ["completed", "cancelled", "failed"]:
		poll_timer.stop()
		RunSession.job_id = ""
		set_busy(false)
		if state == "failed":
			status.text += "\n" + str(data.get("error", "Unknown error"))
		status.text += "\nSaved results are available in Replay and Viewer."
		show_batch_notice((str(data.get("error", "Unknown error")) + "\n" if state == "failed" else "") + "Saved results are available in Replay and Viewer.")
		if presets.is_empty():
			load_presets()

func set_navigation_enabled(value: bool) -> void:
	form.get_node("BackButton").disabled = not value
	form.get_node("FormReplayButton").disabled = not value

func open_replay() -> void:
	if request_kind == "start":
		return
	get_tree().change_scene_to_file("res://scenes/replay.tscn")
