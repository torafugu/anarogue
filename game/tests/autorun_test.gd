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
	assert(not url.is_empty(), "Run through tools/test_run_launcher_api.py")
	OS.set_environment("ANAROGUE_RUN_API", url)
	assert(change_scene_to_file("res://scenes/home.tscn") == OK)
	await process_frame
	await process_frame
	var home = current_scene
	home.show_form()
	assert(home.batch_total(home.batch_settings()) == 248)
	assert(home.batch_count.text.begins_with("248 Runs"))
	for input in home.batch_inputs.values():
		input.text = "0"
	home.autorun_button.pressed.emit()
	assert(not home.busy and home.status.text.contains("1–2,000"))
	home.batch_inputs["enemy_weights"].text = "invalid"
	assert(home.batch_settings().is_empty())
	for input in home.batch_inputs.values():
		input.text = "0,1,1"
	assert(home.batch_total(home.batch_settings()) == 14)
	home.inputs["seed"].value = 42
	home.inputs["max_turns"].value = 2
	home.autorun_button.pressed.emit()
	assert(home.busy and home.execute_button.disabled and home.autorun_button.disabled)
	assert(home.form.get_node("BackButton").disabled)
	assert(await wait_for(func(): return not root.get_node("RunSession").job_id.is_empty()))
	assert(root.get_node("RunSession").job_kind == "batch")
	home.open_replay()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run")))
	current_scene.open_home()
	await process_frame
	await process_frame
	home = current_scene
	assert(home.form.visible and home.busy and home.cancel_button.visible)
	assert(await wait_for(func(): return not home.busy))
	assert(home.status.text.contains("14/14 Runs saved"), home.status.text)
	assert(home.status.text.begins_with("AutoRun completed"))
	assert(root.get_node("RunSession").job_id.is_empty())
	assert(not home.execute_button.disabled and not home.autorun_button.disabled and not home.cancel_button.visible)
	var request := HTTPRequest.new()
	root.add_child(request)
	assert(request.request(url + "/api/runs?scenario_seed=42") == OK)
	var response: Array = await request.request_completed
	var data: Dictionary = JSON.parse_string(response[3].get_string_from_utf8())
	assert(response[1] == 200 and data["total"] == 14)
	var strategies := {}
	for run in data["runs"]:
		strategies[run["strategy_id"]] = true
		assert(run["turns"] <= 2)
	assert(strategies.size() == 2)
	request.queue_free()
	print("AutoRun integration passed: validation, 14 combinations, both Strategies, navigation, progress and DB.")
	quit(0)
