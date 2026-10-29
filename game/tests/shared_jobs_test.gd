extends SceneTree

func _init() -> void:
	run_tests.call_deferred()

func wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func run_tests() -> void:
	OS.set_environment("ANAROGUE_RUN_API", OS.get_environment("ANAROGUE_TEST_API"))
	assert(change_scene_to_file("res://scenes/home.tscn") == OK)
	await process_frame
	await process_frame
	var home = current_scene
	assert(await wait_for(func(): return not home.busy))
	assert(root.get_node("RunSession").job_id.is_empty(), "This client did not start the server-side job")
	home.menu.get_node("JobsMenuButton").pressed.emit()
	assert(await wait_for(func(): return not home.shared_jobs.is_empty()))
	var key: String = home.shared_jobs[0]["id"]
	home.monitor_button.pressed.emit()
	assert(root.get_node("RunSession").job_id == key)
	assert(await wait_for(func(): return home.cancel_button.visible and home.request_kind.is_empty()))
	home.cancel_button.pressed.emit()
	assert(await wait_for(func(): return not home.busy))
	assert(home.batch_summary.text.contains("cancelled"), home.batch_summary.text)
	assert(home.batch_progress.value > 0 and home.batch_progress.value < 52)
	home.show_jobs()
	assert(await wait_for(func(): return not home.jobs_loading and home.shared_jobs[0]["status"] == "cancelled"))
	assert(not home.job_replay_button.disabled)
	var run_id: String = home.shared_jobs[0]["run_id"]
	home.job_replay_button.pressed.emit()
	assert(await wait_for(func(): return current_scene != null and current_scene.has_method("load_catalog_run") and current_scene.selected_catalog_run == run_id))
	print("Shared mobile jobs passed: discover external job, monitor/cancel, retained results and latest Replay.")
	quit(0)
