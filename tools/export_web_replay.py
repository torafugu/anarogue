"""Export the shared Godot Replay into the Viewer (Godot 4.5 templates required)."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    print(result.stdout, end="")
    print(result.stderr, end="")
    if result.returncode or "SCRIPT ERROR:" in result.stdout + result.stderr:
        raise SystemExit("Godot Web export/import failed; see errors above")


def main():
    godot = os.environ.get("GODOT") or shutil.which("godot") or shutil.which("godot4")
    if not godot:
        raise SystemExit("Set GODOT to Godot 4.5 with its Web export templates installed")
    presets = ROOT / "game/export_presets.cfg"
    original = presets.read_bytes() if presets.exists() else None
    output = ROOT / "viewer/public/replay/index.html"
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(ROOT / "game/web-export.cfg", presets)
        run([godot, "--headless", "--path", str(ROOT / "game"), "--editor", "--import", "--quit"])
        run([godot, "--headless", "--path", str(ROOT / "game"), "--export-release", "Web Replay", str(output)])
    finally:
        if original is None:
            presets.unlink(missing_ok=True)
        else:
            presets.write_bytes(original)
    if not output.is_file() or not output.with_suffix(".wasm").is_file():
        raise SystemExit("Web export failed: install matching Godot 4.5 export templates")
    print(f"Web Replay ready: {output}")


if __name__ == "__main__":
    main()
