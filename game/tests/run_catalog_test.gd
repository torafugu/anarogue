extends SceneTree

const Catalog := preload("res://scripts/run_catalog.gd")
const Viewer := preload("res://scripts/replay_viewer.gd")
var failure := ""
var listed: Array = []
var loaded: Array = []
var loaded_key := ""

func _init() -> void:
	run_tests.call_deferred()

func wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while not condition.call() and failure.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func run_tests() -> void:
	var url := OS.get_environment("ANAROGUE_TEST_API")
	if url.is_empty():
		printerr("Run via tools/test_run_api.py; ANAROGUE_TEST_API is required.")
		quit(1)
		return
	var catalog := Catalog.new()
	root.add_child(catalog)
	catalog.catalog_updated.connect(func(runs): listed = runs)
	catalog.run_loaded.connect(func(key, events): loaded_key = key; loaded = events)
	catalog.request_failed.connect(func(_kind, message): failure = message)
	catalog.start(url)
	if not await wait_for(func(): return listed.size() > 500):
		printerr("Catalogue pagination failed: ", failure)
		quit(1)
		return
	var key := str(listed[0]["id"])
	catalog.load_run(key)
	if not await wait_for(func(): return not loaded.is_empty()):
		printerr("Run events failed: ", failure)
		quit(1)
		return
	assert(loaded_key == key)
	var replay := preload("res://scripts/replay_log.gd").new()
	assert(replay.load_events(loaded) == OK and not replay.frames.is_empty())
	catalog.free()
	# Exercise the real default scene path, selection and polling preservation.
	OS.set_environment("ANAROGUE_RUN_API", url)
	var viewer := Viewer.new()
	root.add_child(viewer)
	if not await wait_for(func(): return not viewer.selected_catalog_run.is_empty()):
		printerr("Viewer did not load a database Run.")
		quit(1)
		return
	assert(not viewer.has_node("LogSelector") and not viewer.has_node("RefreshButton"))
	viewer.set_turn(1)
	viewer.playing = true
	viewer.auto_elapsed = -100  # Hold playback while checking background refresh.
	var selected: String = viewer.selected_catalog_run
	viewer.update_catalog(viewer.catalog_runs.duplicate(true))
	assert(viewer.turn_index == 1 and viewer.playing and viewer.selected_catalog_run == selected)
	var more: Array = viewer.catalog_runs.duplicate(true)
	more[0]["score"] += 1
	viewer.update_catalog(more)
	assert(viewer.turn_index == 1 and viewer.playing and viewer.selected_catalog_run == selected)
	viewer.select_run_at(1)
	if not await wait_for(func(): return viewer.selected_catalog_run != selected):
		printerr("Viewer did not switch Runs.")
		quit(1)
		return
	assert(viewer.turn_index == 0 and not viewer.playing and viewer.displayed_log_turn == 0)
	viewer.free()
	print("Run API integration tests passed (pagination, replay, polling and selection).")
	quit(0)
