extends Node

# Navigation and an in-flight job survive scene changes. Runs themselves live in SQLite.
var preset_id := ""
var launch_handled := false
var job_id := ""
var job_kind := "run"
var batch_snapshot: Dictionary = {}
var replay_run_key := ""

func api_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--run-api="):
			return argument.trim_prefix("--run-api=").trim_suffix("/")
	var configured := OS.get_environment("ANAROGUE_RUN_API")
	return (configured if not configured.is_empty() else "http://127.0.0.1:8765").trim_suffix("/")
