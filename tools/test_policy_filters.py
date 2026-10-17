import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import urlopen

from run_store import RunStore, make_server


class PolicyFilterTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / "runs.sqlite3")
        policies = [
            ("aggressive_v1", {"enemy_weight": 0, "item_weight": 1, "stairs_weight": 2, "temperature": 8}),
            ("aggressive_v1", {"enemy_weight": 0, "item_weight": 3, "stairs_weight": 2, "temperature": 8}),
            ("cautious_v1", {"enemy_weight": 0, "item_weight": 1, "stairs_weight": 2, "temperature": 8}),
            ("aggressive_v1", {"enemy_weight": 4, "item_weight": 1, "stairs_weight": 2, "temperature": 8}),
            ("aggressive_v1", {"enemy_weight": "0", "item_weight": 1, "stairs_weight": 2, "temperature": 8}),
            ("aggressive_v1", {"item_weight": 1, "stairs_weight": 2, "temperature": 8}),
            ("aggressive_v1", {"enemy_weight": 0, "item_weight": 1, "stairs_weight": 2, "temperature": 4}),
        ]
        for index, (strategy, policy) in enumerate(policies):
            start = {"run_id": str(index), "event": "run_start", "sequence": 1, "strategy_id": strategy,
                     "scenario_seed": 42, "player_state": {"score": index}, "details": {"goal_policy": policy}}
            self.store.import_text(json.dumps(start))

    def test_zero_missing_string_and_combined_filters(self):
        filters = {"strategy_id": "aggressive_v1", "enemy_weight": "0", "stairs_weight": "2", "temperature": "8"}
        runs = self.store.list_runs(filters)
        self.assertEqual(runs["total"], 2)
        self.assertEqual({run["goal_policy"]["item_weight"] for run in runs["runs"]}, {1, 3})
        self.assertEqual(sum(group["runs"] for group in self.store.stats(filters)["groups"]), 2)
        analyzed = self.store.weight_analysis(filters)["cohorts"][0]["strategies"]
        self.assertEqual(len(analyzed), 1)
        self.assertEqual(analyzed[0]["n"], 2)
        self.assertEqual(analyzed[0]["axes"]["enemy_weight"]["undefined_reason"], "constant_weight")
        self.assertEqual([point["weight"] for point in analyzed[0]["axes"]["item_weight"]["values"]], [1, 3])
        self.assertEqual(self.store.list_runs({**filters, "item_weight": 1})["total"], 1)
        self.assertEqual(self.store.list_runs({"enemy_weight": 0})["total"], 4)
        self.assertEqual(self.store.list_runs({"enemy_weight": ""})["total"], 7)
        self.assertEqual(self.store.list_runs({"enemy_weight": 1000})["total"], 0)
        self.assertEqual(self.store.list_runs(filters, limit=1, offset=1)["total"], 2)
        self.assertEqual(len(self.store.list_runs(filters, limit=1, offset=1)["runs"]), 1)

    def test_http_filter_consistency_and_invalid_values(self):
        server = make_server(self.store, port=0)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            base = f"http://127.0.0.1:{server.server_port}"
            query = urlencode({"strategy_id": "aggressive_v1", "enemy_weight": 0, "item_weight": 3, "stairs_weight": 2, "temperature": 8})
            for endpoint in ("runs", "stats", "weight-analysis"):
                with urlopen(f"{base}/api/{endpoint}?{query}") as response:
                    data = json.load(response)
                count = data["total"] if endpoint == "runs" else sum(group["runs"] for group in data["groups"]) if endpoint == "stats" else sum(strategy["n"] for cohort in data["cohorts"] for strategy in cohort["strategies"])
                self.assertEqual(count, 1)
                for invalid in ("-1", "1001", "1.5", "true", "0 OR 1=1"):
                    with self.subTest(endpoint=endpoint, value=invalid), self.assertRaises(HTTPError) as error:
                        urlopen(f"{base}/api/{endpoint}?{urlencode({'enemy_weight': invalid})}")
                    self.assertEqual(error.exception.code, 400)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
