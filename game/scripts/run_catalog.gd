extends Node

signal catalog_updated(runs: Array)
signal run_loaded(run_key: String, events: Array)
signal request_failed(kind: String, message: String)

var api_url := "http://127.0.0.1:8765"
var list_request := HTTPRequest.new()
var event_request := HTTPRequest.new()
var timer := Timer.new()
var listing := false
var pages: Array = []
var requested_run := ""

func _ready() -> void:
	list_request.timeout = 4
	event_request.timeout = 15
	add_child(list_request)
	add_child(event_request)
	add_child(timer)
	list_request.request_completed.connect(list_completed)
	event_request.request_completed.connect(events_completed)
	timer.wait_time = 3
	timer.timeout.connect(refresh)

func start(url: String) -> void:
	api_url = url.trim_suffix("/")
	timer.start()
	refresh()

func refresh() -> void:
	if listing:
		return
	listing = true
	pages = []
	request_page(0)

func request_page(offset: int) -> void:
	var error := list_request.request("%s/api/runs?limit=500&offset=%d" % [api_url, offset])
	if error != OK:
		listing = false
		request_failed.emit("catalog", "Run API unavailable (error %d)." % error)

func list_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("runs") is Array:
		listing = false
		request_failed.emit("catalog", "Run API unavailable. Start tools/run_store.py serve.")
		return
	pages.append_array(data["runs"])
	if pages.size() < int(data.get("total", pages.size())) and not data["runs"].is_empty():
		request_page(pages.size())
	else:
		listing = false
		catalog_updated.emit(pages)

func load_run(run_key: String) -> void:
	event_request.cancel_request()
	requested_run = run_key
	var error := event_request.request("%s/api/runs/%s/events" % [api_url, run_key.uri_encode()])
	if error != OK:
		request_failed.emit("run", "Could not request Run (error %d)." % error)

func events_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not data is Dictionary or not data.get("events") is Array:
		request_failed.emit("run", "Could not load selected Run. Please select it again.")
		return
	run_loaded.emit(requested_run, data["events"])
