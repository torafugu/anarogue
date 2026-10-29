"""Drive the actual Godot launcher through the API, Rust, SQLite and Replay."""
import os
import shutil
import subprocess
import tempfile
import threading
import time
from pathlib import Path

from run_jobs import RunJobs
from run_store import RunStore, make_server
from run_presets import RunPresets


def main():
    root = Path(__file__).resolve().parents[1]
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    binary = Path(os.environ.get("ANAROGUE_RUST_BINARY", root / "simulation-core/target/release/anarogue-sim"))
    if not godot or not binary.is_file():
        raise SystemExit("Set GODOT and ANAROGUE_RUST_BINARY to built executables")
    for failure in (False, True):
        exercise(root, godot, binary, failure)
    exercise(root, godot, binary, False, "res://tests/autorun_test.gd")
    exercise(root, godot, binary, False, "res://tests/shared_jobs_test.gd")


def exercise(root, godot, binary, failure, script="res://tests/run_launcher_test.gd"):
    with tempfile.TemporaryDirectory() as directory:
        store = RunStore(Path(directory) / "runs.sqlite3")
        store.import_file(root / "examples/reference-v8/aggressive-seed-424242.jsonl")
        jobs = RunJobs(store, root / "missing-simulator" if failure else binary)
        presets = RunPresets(store)
        presets.save({"name": "Cautious counter", "settings": {"seed": 42, "strategy": "cautious", "enemy_weight": 3, "item_weight": 7, "stairs_weight": 2, "max_turns": 20, "enemy_amount": 200, "treasure_amount": 50, "map_depth": 8,
                     **({"dsl": 'rule "Optional" { when self.hp_percent < 0 do wait }'} if not failure else {})}}, jobs)
        presets.save({"name": "Sweep 14", "kind": "batch", "settings": {"seed": 42, "max_turns": 2, "enemy_weights": [0, 1], "item_weights": [0, 1], "stairs_weights": [0, 1]}}, jobs)
        if script.endswith("shared_jobs_test.gd"):
            simulate = jobs.simulate
            def slow(settings):
                time.sleep(.1)
                return simulate(settings)
            jobs.simulate = slow
            jobs.submit_batch({"max_turns": 2, "enemy_weights": [0, 1, 2], "item_weights": [0, 1, 2], "stairs_weights": [0, 1, 2]})
        server = make_server(store, port=0, jobs=jobs)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            env = {**os.environ, "ANAROGUE_TEST_API": f"http://127.0.0.1:{server.server_port}", "ANAROGUE_EXPECT_FAILURE": "1" if failure else "0"}
            subprocess.run([godot, "--headless", "--path", str(root / "game"), "--script",
                            script], env=env, check=True, timeout=45)
        finally:
            server.shutdown()
            server.server_close()
            jobs.close()


if __name__ == "__main__":
    main()
