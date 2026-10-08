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
	assert(home.menu.visible and not home.form.visible)
	assert(home.menu.get_node("RunMenuButton").custom_minimum_size.y >= 88)
	home.menu.get_node("ReplayMenuButton").pressed.emit()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
	var old_key: String = current_scene.selected_catalog_run
	current_scene.get_node("SimulatorButton").pressed.emit()
	await process_frame
	await process_frame
	home = current_scene
	assert(home.menu.visible)
	home.menu.get_node("RunMenuButton").pressed.emit()
	assert(home.form.visible and not home.menu.visible)
	if OS.get_environment("ANAROGUE_EXPECT_FAILURE") == "1":
		home.execute_button.pressed.emit()
		assert(await wait_for(func(): return not home.busy))
		assert(home.status.text.begins_with("Run failed:"))
		assert(not home.execute_button.disabled and root.get_node("RunSession").job_id.is_empty())
		home.form.get_node("FormReplayButton").pressed.emit()
		assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
		print("Failed Run remains recoverable; existing Replay remains available.")
		quit(0)
		return
	home.strategy.select(1)
	home.strategy.item_selected.emit(1)
	assert(home.inputs["enemy_weight"].value == 1 and home.inputs["stairs_weight"].value == 4)
	for field in ["enemy_weight", "item_weight", "stairs_weight"]:
		home.inputs[field].value = 0
	home.execute_button.pressed.emit()
	assert(not home.busy and root.get_node("RunSession").job_id.is_empty())
	assert(home.status.text.contains("positive"))
	# Typed seed is committed even before focus leaves the input.
	home.inputs["seed"].get_line_edit().grab_focus()
	home.inputs["seed"].get_line_edit().text = "42"
	home.inputs["enemy_weight"].value = 3
	home.inputs["item_weight"].value = 7
	home.inputs["stairs_weight"].value = 2
	home.inputs["max_turns"].value = 20
	home.execute_button.pressed.emit()
	assert(home.busy and home.execute_button.disabled)
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
	var viewer = current_scene
	assert(viewer.selected_catalog_run != old_key)
	assert(viewer.replay.frames.size() > 0 and viewer.frame_index == 0)
	assert(root.get_node("RunSession").job_id.is_empty())
	var wanted: String = viewer.selected_catalog_run
	assert(await wait_for(func(): return not viewer.catalog_runs.is_empty()))
	var metadata: Dictionary = {}
	for entry in viewer.catalog_runs:
		if entry["id"] == wanted:
			metadata = entry
	assert(metadata["scenario_seed"] == 42 and metadata["strategy_id"] == "cautious_v1")
	assert(metadata["goal_policy"]["item_weight"] == 7)
	assert(metadata["turns"] <= 20)
	viewer.get_node("SimulatorButton").pressed.emit()
	await process_frame
	await process_frame
	home = current_scene
	assert(home.menu.visible and home.inputs["seed"].value == 42)
	home.menu.get_node("ReplayMenuButton").pressed.emit()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.catalog_runs.is_empty()))
	viewer = current_scene
	for index in range(viewer.run_selector.item_count):
		if viewer.run_selector.get_item_metadata(index) == old_key:
			viewer.select_run_at(index)
	assert(await wait_for(func(): return viewer.selected_catalog_run == old_key))
	# Once accepted, changing scenes preserves the running job and its settings.
	viewer.get_node("SimulatorButton").pressed.emit()
	await process_frame
	await process_frame
	home = current_scene
	home.show_form()
	home.execute_button.pressed.emit()
	assert(home.form.get_node("BackButton").disabled)
	assert(await wait_for(func(): return not root.get_node("RunSession").job_id.is_empty()))
	var job_id: String = root.get_node("RunSession").job_id
	home.form.get_node("FormReplayButton").pressed.emit()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and not current_scene.selected_catalog_run.is_empty()))
	assert(root.get_node("RunSession").job_id == job_id)
	current_scene.get_node("SimulatorButton").pressed.emit()
	await process_frame
	await process_frame
	home = current_scene
	assert(home.form.visible and home.busy)
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and root.get_node("RunSession").job_id.is_empty() and not current_scene.selected_catalog_run.is_empty()))
	assert(current_scene.selected_catalog_run != wanted)
	print("Run launcher integration passed: home, Replay, settings, Rust/API/DB, selected result and navigation.")
	quit(0)
