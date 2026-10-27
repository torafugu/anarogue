extends SceneTree

func _init() -> void:
	run_tests.call_deferred()

func wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func run_tests() -> void:
	var url := OS.get_environment("ANAROGUE_TEST_API")
	OS.set_environment("ANAROGUE_RUN_API", url)
	assert(change_scene_to_file("res://scenes/home.tscn") == OK)
	await process_frame
	await process_frame
	var home = current_scene
	assert(await wait_for(func(): return not home.busy))
	home.show_form()
	for index in range(home.presets.size()):
		if home.presets[index]["name"] == "Sweep 14":
			home.preset_selector.select(index)
			home.select_preset(index)
	assert(home.execute_button.text.contains("AutoRun"))
	home.execute_button.pressed.emit()
	assert(home.busy)
	assert(await wait_for(func(): return not root.get_node("RunSession").job_id.is_empty()))
	assert(root.get_node("RunSession").job_kind == "batch")
	home.open_replay()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run")))
	current_scene.open_home()
	await process_frame
	await process_frame
	home = current_scene
	assert(await wait_for(func(): return not home.busy))
	assert(home.batch_progress.value == 14 and home.batch_progress.max_value == 14)
	assert(home.batch_summary.text.contains("100.0%"))
	assert(root.get_node("RunSession").job_id.is_empty())
	assert(not home.execute_button.disabled)
	var request := HTTPRequest.new()
	root.add_child(request)
	assert(request.request(url + "/api/runs?scenario_seed=42") == OK)
	var response: Array = await request.request_completed
	var data: Dictionary = JSON.parse_string(response[3].get_string_from_utf8())
	assert(response[1] == 200 and data["total"] == 14)
	var strategies := {}
	for run in data["runs"]:
		strategies[run["strategy_id"]] = true
		assert(run["preset"]["name"] == "Sweep 14")
	assert(strategies.size() == 2)
	request.queue_free()
	print("Saved AutoRun preset passed: 14 combinations, both strategies, progress, navigation and snapshot.")
	quit(0)
