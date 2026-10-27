extends SceneTree

func _init() -> void:
	run_tests.call_deferred()

func wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func change_preset(preset: Dictionary, method: int) -> int:
	var request := HTTPRequest.new()
	root.add_child(request)
	var value: Dictionary = {"version": int(preset["version"])}
	if method == HTTPClient.METHOD_PUT:
		var settings: Dictionary = preset["settings"].duplicate(true)
		for field in settings:
			if settings[field] is float:
				settings[field] = int(settings[field])
		value.merge({"name": preset["name"], "kind": preset["kind"], "settings": settings})
	assert(request.request(OS.get_environment("ANAROGUE_TEST_API") + "/api/presets/" + preset["id"], ["Content-Type: application/json"], method, JSON.stringify(value)) == OK)
	var response: Array = await request.request_completed
	request.queue_free()
	return response[1]

func run_tests() -> void:
	OS.set_environment("ANAROGUE_RUN_API", OS.get_environment("ANAROGUE_TEST_API"))
	assert(change_scene_to_file("res://scenes/home.tscn") == OK)
	await process_frame
	await process_frame
	var home = current_scene
	assert(home.menu.visible and not home.form.visible)
	assert(await wait_for(func(): return not home.busy))
	assert(home.presets.size() == 2)
	assert(home.find_children("*", "SpinBox", true, false).is_empty())
	assert(home.find_children("*", "CodeEdit", true, false).is_empty())
	home.show_form()
	for index in range(home.presets.size()):
		if home.presets[index]["name"] == "Cautious counter":
			home.preset_selector.select(index)
			home.select_preset(index)
	assert(home.preset_summary.text.contains("Cautious counter"))
	assert(home.preset_summary.text.contains("Treasure 7"))
	if OS.get_environment("ANAROGUE_EXPECT_FAILURE") != "1":
		assert(await change_preset(home.selected_preset(), HTTPClient.METHOD_PUT) == 200)
		home.execute_button.pressed.emit()
		assert(await wait_for(func(): return not home.busy))
		assert(home.status.text.contains("Preset changed"), home.status.text)
		assert(root.get_node("RunSession").job_id.is_empty())
		home.reload_button.pressed.emit()
		assert(await wait_for(func(): return not home.busy))
	home.execute_button.pressed.emit()
	assert(home.busy and home.execute_button.disabled and home.reload_button.disabled)
	assert(home.form.get_node("BackButton").disabled)
	if OS.get_environment("ANAROGUE_EXPECT_FAILURE") == "1":
		assert(await wait_for(func(): return not home.busy))
		assert(home.status.text.begins_with("Run failed:"), home.status.text)
		assert(not home.execute_button.disabled)
		home.open_replay()
		assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
		print("Preset launcher recovers from simulator failure and keeps Replay available.")
		quit(0)
		return
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
	var viewer = current_scene
	assert(await wait_for(func(): return not viewer.catalog_runs.is_empty()))
	var metadata: Dictionary = {}
	for entry in viewer.catalog_runs:
		if entry["id"] == viewer.selected_catalog_run:
			metadata = entry
	assert(metadata["scenario_seed"] == 42 and metadata["strategy_id"] == "cautious_v1")
	assert(metadata["preset"]["name"] == "Cautious counter" and metadata["preset"]["version"] == 2)
	assert(metadata["goal_policy"]["item_weight"] == 7)
	assert(metadata["execution_settings"]["dsl"].contains("Optional"))
	assert(metadata["execution_settings"]["enemy_amount"] == 200)
	assert(metadata["execution_settings"]["map_depth"] == 8)
	viewer.open_home()
	await process_frame
	await process_frame
	home = current_scene
	assert(await wait_for(func(): return not home.busy))
	assert(home.selected_preset()["name"] == "Cautious counter")
	home.reload_button.pressed.emit()
	assert(await wait_for(func(): return not home.busy))
	assert(home.presets.size() == 2 and not home.execute_button.disabled)
	# A deleted selection cannot silently launch an outdated local copy.
	for preset in home.presets:
		assert(await change_preset(preset, HTTPClient.METHOD_DELETE) == 200)
	home.execute_button.pressed.emit()
	assert(await wait_for(func(): return not home.busy))
	assert(home.status.text.contains("Preset not found"))
	home.reload_button.pressed.emit()
	assert(await wait_for(func(): return not home.busy))
	assert(home.presets.is_empty() and home.execute_button.disabled)
	assert(home.preset_summary.text.contains("Create one in the Web Viewer"))
	print("Preset launcher passed: shared presets, read-only selection, Rust/API/SQLite/Replay, snapshot and navigation.")
	quit(0)
