extends Node

# Navigation and an in-flight job survive scene changes. Runs themselves live in SQLite.
var settings := {"seed": 424242, "strategy": "aggressive", "enemy_weight": 4, "item_weight": 2, "stairs_weight": 1, "max_turns": 5000, "enemy_amount": 100, "treasure_amount": 100, "map_depth": 5}
var launch_handled := false
var dsl_source := ""
var job_id := ""
var job_kind := "run"
var batch_snapshot: Dictionary = {}
var batch_values := {"enemy_weights": "0,1,2,3,4", "item_weights": "0,1,2,3,4", "stairs_weights": "0,1,2,3,4"}
var replay_run_key := ""

func api_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--run-api="):
			return argument.trim_prefix("--run-api=").trim_suffix("/")
	var configured := OS.get_environment("ANAROGUE_RUN_API")
	return (configured if not configured.is_empty() else "http://127.0.0.1:8765").trim_suffix("/")
