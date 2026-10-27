"""Named, versioned launch settings shared by Viewer and Godot."""
import json
import sqlite3
import uuid
from contextlib import closing


class PresetConflict(Exception):
    pass


class RunPresets:
    def __init__(self, store):
        self.store = store
        with closing(store.connect()) as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS run_presets (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL, settings TEXT NOT NULL, version INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)""")

    @staticmethod
    def decode(row):
        result = dict(row)
        del result["name_key"]
        result["settings"] = json.loads(result["settings"])
        return result

    def list(self):
        with closing(self.store.connect()) as db:
            return [self.decode(row) for row in db.execute("SELECT * FROM run_presets ORDER BY name_key,id")]

    def get(self, key):
        with closing(self.store.connect()) as db:
            row = db.execute("SELECT * FROM run_presets WHERE id=?", (key,)).fetchone()
            if row is None:
                raise KeyError(key)
            return self.decode(row)

    def save(self, value, jobs, key=None):
        if not isinstance(value, dict) or set(value) - {"name", "kind", "settings", "version"}:
            raise ValueError("Expected name, kind and settings")
        name = value.get("name")
        if not isinstance(name, str) or not 1 <= len(name.strip()) <= 80 or any(ord(c) < 32 for c in name):
            raise ValueError("Preset name must contain 1..80 characters without control characters")
        name = name.strip()
        kind = value.get("kind", "run")
        if kind not in ("run", "batch"):
            raise ValueError("Preset kind must be run or batch")
        settings, _total = jobs.validate_launch(kind, value.get("settings"))
        version = value.get("version")
        if key is not None and (type(version) is not int or version < 1):
            raise ValueError("Expected preset version")
        try:
            with closing(self.store.connect()) as db, db:
                if key is None:
                    key = uuid.uuid4().hex
                    db.execute("INSERT INTO run_presets(id,name,name_key,kind,settings,version) VALUES (?,?,?,?,?,1)",
                               (key, name, name.casefold(), kind, json.dumps(settings, ensure_ascii=False)))
                else:
                    changed = db.execute("""UPDATE run_presets SET name=?,name_key=?,kind=?,settings=?,version=version+1,
                        updated_at=CURRENT_TIMESTAMP WHERE id=? AND version=?""",
                        (name, name.casefold(), kind, json.dumps(settings, ensure_ascii=False), key, version)).rowcount
                    if not changed:
                        raise PresetConflict("Preset changed or was deleted. Reload before saving.")
                # Read in the same transaction so the response identifies this exact save.
                return self.decode(db.execute("SELECT * FROM run_presets WHERE id=?", (key,)).fetchone())
        except sqlite3.IntegrityError:
            raise PresetConflict("A preset with this name already exists") from None

    def delete(self, key, version):
        if type(version) is not int or version < 1:
            raise ValueError("Expected preset version")
        with closing(self.store.connect()) as db, db:
            if not db.execute("DELETE FROM run_presets WHERE id=? AND version=?", (key, version)).rowcount:
                raise PresetConflict("Preset changed or was deleted. Reload before deleting.")
