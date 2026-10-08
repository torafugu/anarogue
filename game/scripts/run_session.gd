extends Node

# Navigation and an in-flight job survive scene changes. Runs themselves live in SQLite.
var settings := {"seed": 424242, "strategy": "aggressive", "enemy_weight": 4, "item_weight": 2, "stairs_weight": 1, "max_turns": 5000}
var launch_handled := false
var job_id := ""
var replay_run_key := ""

func api_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--run-api="):
			return argument.trim_prefix("--run-api=").trim_suffix("/")
	var configured := OS.get_environment("ANAROGUE_RUN_API")
	return (configured if not configured.is_empty() else "http://127.0.0.1:8765").trim_suffix("/")
