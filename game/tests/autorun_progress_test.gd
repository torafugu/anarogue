extends SceneTree

func _init() -> void:
	run_tests.call_deferred()

func run_tests() -> void:
	var session = root.get_node("RunSession")
	session.launch_handled = true
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 640), Vector2i(640, 480), Vector2i(480, 800)]:
		session.job_id = ""
		session.batch_snapshot.clear()
		var viewport := SubViewport.new()
		viewport.size = dimensions
		root.add_child(viewport)
		var home = load("res://scripts/home.gd").new()
		viewport.add_child(home)
		# Progress layout is independent of the preset catalogue's HTTP request.
		home.request.cancel_request()
		home.request_kind = ""
		home.presets = [{"id": "layout", "kind": "batch", "name": "Layout", "version": 1, "settings": {}}]
		home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		home.show_form()
		session.job_kind = "batch"
		home.set_busy(true)
		var snapshot := {"kind": "batch", "status": "running", "total": 2000, "completed": 500, "failed": 0,
			"current_settings": {"strategy": "cautious", "enemy_weight": 1000, "item_weight": 1000, "stairs_weight": 1000}}
		home.update_autorun_status(snapshot)
		await process_frame
		await process_frame
		assert(home.batch_progress.value == 500 and home.batch_progress.max_value == 2000)
		assert(home.batch_summary.text.contains("500/2000 (25.0%)"))
		assert(home.batch_current.text.contains("Run 501") and home.batch_current.text.contains("Cautious"))
		var panel_rect: Rect2 = home.batch_panel.get_global_rect()
		assert(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel_rect), "Progress fits %s: %s" % [dimensions, panel_rect])
		var scroll: ScrollContainer = home.find_child("SettingsScroll", true, false)
		scroll.scroll_vertical = 10000
		await process_frame
		assert(home.batch_panel.get_global_rect() == panel_rect, "Progress remains fixed while scrolling")
		assert(not panel_rect.intersects(scroll.get_global_rect()), "Progress and settings do not overlap")
		home.request_kind = "poll"
		home.request_completed(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		assert(home.batch_progress.value == 500 and home.batch_notice.text.contains("Retrying"))
		snapshot["cancel_requested"] = true
		home.update_autorun_status(snapshot)
		assert(home.cancel_button.disabled and home.batch_notice.text.contains("Stopping"))
		snapshot["status"] = "cancelled"
		home.update_autorun_status(snapshot)
		assert(home.batch_progress.value == 500 and not home.cancel_button.visible and not home.busy)
		assert(home.batch_summary.text.contains("cancelled"))
		snapshot["status"] = "failed"
		snapshot["failed"] = 1
		snapshot["error"] = "Simulator failed"
		home.update_autorun_status(snapshot)
		assert(home.batch_progress.value == 501 and home.batch_summary.text.contains("Saved 500 · Failed 1"))
		assert(home.batch_notice.text.contains("Simulator failed") and not home.cancel_button.visible)
		snapshot["status"] = "completed"
		snapshot["completed"] = 2000
		snapshot["failed"] = 0
		home.update_autorun_status(snapshot)
		assert(home.batch_progress.value == 2000 and home.batch_summary.text.contains("100.0%"))
		home.queue_free()
		await process_frame
		var restored = load("res://scripts/home.gd").new()
		viewport.add_child(restored)
		assert(restored.batch_progress.value == 2000 and restored.batch_panel.visible, "Progress survives scene changes")
		viewport.free()
	print("AutoRun progress passed: 2,000 Runs, percentage, fixed layout at four sizes, reconnect, stop and scene restoration.")
	quit(0)
