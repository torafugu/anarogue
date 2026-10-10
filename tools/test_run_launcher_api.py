"""Drive the actual Godot launcher through the API, Rust, SQLite and Replay."""
import os
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from run_jobs import RunJobs
from run_store import RunStore, make_server


def main():
    root = Path(__file__).resolve().parents[1]
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    binary = Path(os.environ.get("ANAROGUE_RUST_BINARY", root / "simulation-core/target/release/anarogue-sim"))
    if not godot or not binary.is_file():
        raise SystemExit("Set GODOT and ANAROGUE_RUST_BINARY to built executables")
    for failure in (False, True):
        exercise(root, godot, binary, failure)


def exercise(root, godot, binary, failure):
    with tempfile.TemporaryDirectory() as directory:
        store = RunStore(Path(directory) / "runs.sqlite3")
        store.import_file(root / "examples/reference-v8/aggressive-seed-424242.jsonl")
        jobs = RunJobs(store, root / "missing-simulator" if failure else binary)
        server = make_server(store, port=0, jobs=jobs)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            env = {**os.environ, "ANAROGUE_TEST_API": f"http://127.0.0.1:{server.server_port}", "ANAROGUE_EXPECT_FAILURE": "1" if failure else "0"}
            subprocess.run([godot, "--headless", "--path", str(root / "game"), "--script",
                            "res://tests/run_launcher_test.gd"], env=env, check=True, timeout=45)
        finally:
            server.shutdown()
            server.server_close()
            jobs.close()


if __name__ == "__main__":
    main()
