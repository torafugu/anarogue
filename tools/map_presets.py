"""Reusable map configurations, independently versioned from player strategies."""
import json
import sqlite3
import uuid
from contextlib import closing


class PresetConflict(Exception):
    pass


MAP_DEFAULTS = {"enemy_amount": 100, "treasure_amount": 100, "map_depth": 5}


def validate_map(value):
    if not isinstance(value, dict) or set(value) != set(MAP_DEFAULTS):
        raise ValueError("Map settings require enemy_amount, treasure_amount and map_depth")
    for key, number in value.items():
        minimum, maximum = (1, 100) if key == "map_depth" else (0, 500)
        if type(number) is not int or not minimum <= number <= maximum:
            raise ValueError(f"{key} must be an integer in {minimum}..{maximum}")
    return dict(value)


def preset_name(value):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= 80 or any(ord(c) < 32 for c in value):
        raise ValueError("Preset name must contain 1..80 characters without control characters")
    return value.strip()


class MapPresets:
    def __init__(self, store):
        self.store = store
        with closing(store.connect()) as db, db:
            fresh = not db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='map_presets'").fetchone()
            db.execute("""CREATE TABLE IF NOT EXISTS map_presets (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE,
                settings TEXT NOT NULL, version INTEGER NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)""")
            db.execute("CREATE TABLE IF NOT EXISTS map_preset_versions (id TEXT NOT NULL, version INTEGER NOT NULL, snapshot TEXT NOT NULL, PRIMARY KEY(id,version))")
            db.execute("BEGIN IMMEDIATE")
            if fresh:
                self.ensure(db, MAP_DEFAULTS)

    @staticmethod
    def decode(row):
        result = dict(row)
        del result["name_key"]
        result["settings"] = json.loads(result["settings"])
        return result

    def ensure(self, db, settings):
        """Deduplicate legacy configurations in the caller's transaction."""
        for row in db.execute("SELECT * FROM map_presets ORDER BY created_at,id"):
            if json.loads(row["settings"]) == settings:
                return self.decode(row)
        base = "Default map" if settings == MAP_DEFAULTS else "Map E%d T%d D%d" % tuple(settings[k] for k in MAP_DEFAULTS)
        name, suffix = base, 2
        while db.execute("SELECT 1 FROM map_presets WHERE name_key=?", (name.casefold(),)).fetchone():
            name, suffix = f"{base} ({suffix})", suffix + 1
        key = uuid.uuid4().hex
        db.execute("INSERT INTO map_presets(id,name,name_key,settings,version) VALUES (?,?,?,?,1)",
                   (key, name, name.casefold(), json.dumps(settings)))
        snapshot = self.decode(db.execute("SELECT * FROM map_presets WHERE id=?", (key,)).fetchone())
        self.archive(db, snapshot)
        return snapshot

    def list(self):
        with closing(self.store.connect()) as db:
            return [self.decode(row) for row in db.execute("SELECT * FROM map_presets ORDER BY name_key,id")]

    def get(self, key, db=None):
        if db is None:
            with closing(self.store.connect()) as connection:
                return self.get(key, connection)
        row = db.execute("SELECT * FROM map_presets WHERE id=?", (key,)).fetchone()
        if row is None:
            raise KeyError(key)
        return self.decode(row)

    @staticmethod
    def archive(db, snapshot):
        db.execute("INSERT OR IGNORE INTO map_preset_versions(id,version,snapshot) VALUES (?,?,?)",
                   (snapshot["id"], snapshot["version"], json.dumps(snapshot, ensure_ascii=False)))

    def resolve(self, reference, db=None):
        if not isinstance(reference, dict) or set(reference) != {"id", "version"} or not isinstance(reference["id"], str) or type(reference["version"]) is not int or reference["version"] < 1:
            raise ValueError("Select a Map preset id and version")
        if db is None:
            with closing(self.store.connect()) as connection:
                return self.resolve(reference, connection)
        self.get(reference["id"], db)
        row = db.execute("SELECT snapshot FROM map_preset_versions WHERE id=? AND version=?",
                         (reference["id"], reference["version"])).fetchone()
        if row is None:
            raise KeyError(reference["id"])
        return json.loads(row[0])

    def save(self, value, key=None):
        if not isinstance(value, dict) or set(value) - {"name", "settings", "version"}:
            raise ValueError("Expected Map preset name and settings")
        name = preset_name(value.get("name"))
        settings = validate_map(value.get("settings"))
        version = value.get("version")
        if key is not None and (type(version) is not int or version < 1):
            raise ValueError("Expected Map preset version")
        try:
            with closing(self.store.connect()) as db, db:
                if key is None:
                    key = uuid.uuid4().hex
                    db.execute("INSERT INTO map_presets(id,name,name_key,settings,version) VALUES (?,?,?,?,1)",
                               (key, name, name.casefold(), json.dumps(settings)))
                elif not db.execute("""UPDATE map_presets SET name=?,name_key=?,settings=?,version=version+1,
                        updated_at=CURRENT_TIMESTAMP WHERE id=? AND version=?""",
                        (name, name.casefold(), json.dumps(settings), key, version)).rowcount:
                    raise PresetConflict("Map preset changed or was deleted. Reload before saving.")
                snapshot = self.get(key, db)
                self.archive(db, snapshot)
                return snapshot
        except sqlite3.IntegrityError:
            raise PresetConflict("A Map preset with this name already exists") from None

    def delete(self, key, version):
        if type(version) is not int or version < 1:
            raise ValueError("Expected Map preset version")
        with closing(self.store.connect()) as db, db:
            db.execute("BEGIN IMMEDIATE")
            if self.get(key, db)["version"] != version:
                raise PresetConflict("Map preset changed. Reload before deleting.")
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='run_presets'").fetchone():
                if db.execute("SELECT 1 FROM run_presets WHERE json_extract(map_preset,'$.id')=?", (key,)).fetchone():
                    raise PresetConflict("Map preset is used by a Run preset. Select another Map in those Run presets before deleting.")
            db.execute("DELETE FROM map_presets WHERE id=?", (key,))
            db.execute("DELETE FROM map_preset_versions WHERE id=?", (key,))
