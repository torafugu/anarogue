"""Map reuse, legacy migration, version pinning and validation."""
from contextlib import closing
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

from map_presets import MapPresets, PresetConflict
from run_jobs import validate_settings
from run_presets import RunPresets
from run_store import RunStore


class MapPresetTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / "runs.sqlite3")
        self.jobs = SimpleNamespace(validate_launch=lambda kind, value: (validate_settings(value), 1))

    def test_migrates_unique_legacy_maps_without_changing_launch_settings(self):
        with closing(self.store.connect()) as db, db:
            db.execute("""CREATE TABLE run_presets(id TEXT PRIMARY KEY,name TEXT,name_key TEXT UNIQUE,
                kind TEXT,settings TEXT,version INTEGER,created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP)""")
            for key, enemy in [("a", 200), ("b", 200), ("c", 0)]:
                db.execute("INSERT INTO run_presets(id,name,name_key,kind,settings,version) VALUES (?,?,?,'run',?,7)",
                           (key, key, key, json.dumps(validate_settings({"enemy_amount": enemy, "map_depth": 8}))))
        presets = RunPresets(self.store)
        a, b, c = presets.list()
        self.assertEqual(a["map_preset"], b["map_preset"])
        self.assertNotEqual(a["map_preset"]["id"], c["map_preset"]["id"])
        self.assertEqual(a["version"], 7)
        self.assertEqual(a["settings"], validate_settings({"enemy_amount": 200, "map_depth": 8}))
        self.assertEqual(RunPresets(self.store).list(), presets.list())
        self.assertEqual(len(presets.maps.list()), 3)

    def test_run_presets_pin_maps_and_keep_old_versions_editable(self):
        presets = RunPresets(self.store)
        maps = presets.maps
        one = maps.save({"name": "Dense", "settings": {"enemy_amount": 250, "treasure_amount": 50, "map_depth": 10}})
        ref = {"id": one["id"], "version": 1}
        run = presets.save({"name": "Bow", "settings": {"strategy": "cautious"}, "map_preset": ref}, self.jobs)
        other = presets.save({"name": "Melee", "settings": {}, "map_preset": ref}, self.jobs)
        two = maps.save({"name": "Dense v2", "version": 1, "settings": {"enemy_amount": 500, "treasure_amount": 0, "map_depth": 20}}, one["id"])
        self.assertEqual(presets.get(run["id"])["map_preset"], one)
        edited = presets.save({"name": "Bow edited", "settings": {"max_turns": 123}, "version": 1, "map_preset": ref}, self.jobs, run["id"])
        self.assertEqual(edited["settings"]["map_depth"], 10)
        updated = presets.save({"name": "Bow updated", "settings": {}, "version": 2,
                                "map_preset": {"id": one["id"], "version": 2}}, self.jobs, run["id"])
        self.assertEqual(updated["map_preset"], two)
        self.assertEqual(updated["settings"]["enemy_amount"], 500)
        self.assertEqual(presets.get(other["id"])["map_preset"], one)
        with self.assertRaises(PresetConflict):
            maps.delete(one["id"], 2)
        presets.delete(run["id"], 3)
        presets.delete(other["id"], 1)
        maps.delete(one["id"], 2)
        with self.assertRaises(KeyError):
            maps.resolve(ref)
        self.assertEqual(RunPresets(self.store).maps.list(), maps.list())

    def test_map_validation_conflicts_and_invalid_references_do_not_save_runs(self):
        presets = RunPresets(self.store)
        maps = presets.maps
        original = maps.list()[0]
        for key, number in [("map_depth", 0), ("map_depth", 101), ("enemy_amount", 501), ("treasure_amount", -1), ("enemy_amount", True)]:
            with self.assertRaises(ValueError):
                maps.save({"name": "Bad", "settings": {**original["settings"], key: number}})
        with self.assertRaises(PresetConflict):
            maps.save({"name": original["name"].upper(), "settings": original["settings"]})
        with self.assertRaises(PresetConflict):
            maps.save({"name": "Stale", "settings": original["settings"], "version": 2}, original["id"])
        with self.assertRaises(KeyError):
            presets.save({"name": "Missing", "settings": {}, "map_preset": {"id": "missing", "version": 1}}, self.jobs)
        with self.assertRaises(ValueError):
            presets.save({"name": "Mismatch", "settings": {"enemy_amount": 0}, "map_preset": {"id": original["id"], "version": 1}}, self.jobs)
        self.assertEqual(presets.list(), [])
        self.assertEqual(len(maps.list()), 1)


if __name__ == "__main__":
    unittest.main()
