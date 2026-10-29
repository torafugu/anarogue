"""Named, versioned launch settings shared by Viewer and Godot."""
import json
import sqlite3
import uuid
from map_presets import MapPresets, PresetConflict, MAP_DEFAULTS, preset_name
from contextlib import closing


class RunPresets:
    def __init__(self, store):
        self.store = store
        self.maps = MapPresets(store)
        with closing(store.connect()) as db, db:
            db.execute("""CREATE TABLE IF NOT EXISTS run_presets (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE,
                kind TEXT NOT NULL, settings TEXT NOT NULL, version INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)""")
            db.execute("BEGIN IMMEDIATE")
            if "map_preset" not in {row[1] for row in db.execute("PRAGMA table_info(run_presets)")}:
                db.execute("ALTER TABLE run_presets ADD COLUMN map_preset TEXT")
            for row in db.execute("SELECT id,settings FROM run_presets WHERE map_preset IS NULL").fetchall():
                settings = json.loads(row["settings"])
                snapshot = self.maps.ensure(db, {k: settings.get(k, v) for k, v in MAP_DEFAULTS.items()})
                db.execute("UPDATE run_presets SET map_preset=? WHERE id=?", (json.dumps(snapshot), row["id"]))

    @staticmethod
    def decode(row):
        result = dict(row)
        del result["name_key"]
        result["settings"] = json.loads(result["settings"])
        result["map_preset"] = json.loads(result["map_preset"])
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

    def validate(self, value, jobs):
        settings = value.get("settings")
        snapshot = None
        if "map_preset" in value:
            snapshot = self.maps.resolve(value["map_preset"])
            if not isinstance(settings, dict):
                raise ValueError("Expected Run settings")
            if any(k in settings and settings[k] != v for k, v in snapshot["settings"].items()):
                raise ValueError("Inline Map settings conflict with the selected Map preset")
            settings = {**settings, **snapshot["settings"]}
        normalized, total = jobs.validate_launch(value.get("kind", "run"), settings)
        return normalized, total, snapshot

    def save(self, value, jobs, key=None):
        if not isinstance(value, dict) or set(value) - {"name", "kind", "settings", "version", "map_preset"}:
            raise ValueError("Expected name, kind and settings")
        name = preset_name(value.get("name"))
        kind = value.get("kind", "run")
        if kind not in ("run", "batch"):
            raise ValueError("Preset kind must be run or batch")
        settings, _total, snapshot = self.validate(value, jobs)
        version = value.get("version")
        if key is not None and (type(version) is not int or version < 1):
            raise ValueError("Expected preset version")
        try:
            with closing(self.store.connect()) as db, db:
                db.execute("BEGIN IMMEDIATE")
                if snapshot is None:
                    snapshot = self.maps.ensure(db, {k: settings[k] for k in MAP_DEFAULTS})
                else:
                    snapshot = self.maps.resolve(value["map_preset"], db)
                if key is None:
                    key = uuid.uuid4().hex
                    db.execute("INSERT INTO run_presets(id,name,name_key,kind,settings,map_preset,version) VALUES (?,?,?,?,?,?,1)",
                               (key, name, name.casefold(), kind, json.dumps(settings, ensure_ascii=False), json.dumps(snapshot, ensure_ascii=False)))
                else:
                    changed = db.execute("""UPDATE run_presets SET name=?,name_key=?,kind=?,settings=?,map_preset=?,version=version+1,
                        updated_at=CURRENT_TIMESTAMP WHERE id=? AND version=?""",
                        (name, name.casefold(), kind, json.dumps(settings, ensure_ascii=False), json.dumps(snapshot, ensure_ascii=False), key, version)).rowcount
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
