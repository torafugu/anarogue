"""Exercise the actual Godot HTTP client against a temporary SQLite Run API."""
import json
import os
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from run_store import RunStore, make_server


def main():
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        raise SystemExit("Set GODOT to your Godot 4 executable")
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as directory:
        store = RunStore(Path(directory) / "runs.sqlite3")
        template = [json.loads(line) for line in (root / "examples/reference-v8/aggressive-seed-424242.jsonl").read_text().splitlines()[:4]]
        for index in range(501):
            events = [{**event, "run_id": f"catalogue-test-{index}"} for event in template]
            store.import_text("\n".join(json.dumps(event) for event in events))
        server = make_server(store, port=0)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            env = {**os.environ, "ANAROGUE_TEST_API": f"http://127.0.0.1:{server.server_port}"}
            subprocess.run([godot, "--headless", "--path", str(root / "game"), "--script", "res://tests/run_catalog_test.gd"], env=env, check=True, timeout=30)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    main()
