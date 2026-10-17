import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import urlopen

from run_store import RunStore, make_server
from weight_analysis import analyze_runs


def row(weight, score, strategy="aggressive_v1", **changes):
    result = {"scenario_seed": 42, "scenario_id": "scenario-42", "simulation_version": 8,
              "schema_version": 8, "code_revision": "test", "strategy_id": strategy,
              "status": "cleared", "score": score,
              "goal_policy": {"enemy_weight": weight, "item_weight": 1, "stairs_weight": 2, "temperature": 8}}
    result.update(changes)
    return result


class WeightAnalysisTests(unittest.TestCase):
    def test_exact_correlations_means_and_strategy_separation(self):
        rows = [row(x, 10 * x) for x in range(3)] + [row(x, 20 - 10 * x, "cautious_v1") for x in range(3)]
        data = analyze_runs(rows)
        self.assertEqual(len(data["cohorts"]), 1)
        aggressive, cautious = data["cohorts"][0]["strategies"]
        self.assertAlmostEqual(aggressive["axes"]["enemy_weight"]["pearson_r"], 1)
        self.assertAlmostEqual(cautious["axes"]["enemy_weight"]["pearson_r"], -1)
        axis = aggressive["axes"]["item_weight"]
        self.assertEqual(axis["undefined_reason"], "constant_weight")
        self.assertEqual(axis["values"], [{"weight": 1, "n": 3, "mean_score": 10, "unfinished": 0}])

    def test_constant_score_small_sample_and_invalid_weights(self):
        one = analyze_runs([row(1, 10)])["cohorts"][0]["strategies"][0]
        self.assertEqual(one["axes"]["enemy_weight"]["undefined_reason"], "fewer_than_two_runs")
        constant = analyze_runs([row(1, 10), row(2, 10)])["cohorts"][0]["strategies"][0]
        self.assertEqual(constant["axes"]["enemy_weight"]["undefined_reason"], "constant_score")
        self.assertIsNone(constant["axes"]["enemy_weight"]["pearson_r"])
        invalid = [row(1, 10, goal_policy={}), row(True, 10), row(float("nan"), 10), row(-1, 10), row(1, 10, goal_policy=None)]
        data = analyze_runs(invalid)
        self.assertEqual(data, {"cohorts": [], "excluded_runs": 5})
        json.dumps(data, allow_nan=False)

    def test_curved_relation_can_have_zero_linear_correlation(self):
        axis = analyze_runs([row(0, 0), row(1, 10), row(2, 0)])["cohorts"][0]["strategies"][0]["axes"]["enemy_weight"]
        self.assertAlmostEqual(axis["pearson_r"], 0)
        self.assertEqual([point["mean_score"] for point in axis["values"]], [0, 10, 0])

    def test_conditions_are_separated(self):
        rows = [row(1, 10), row(1, 10, scenario_seed=43), row(1, 10, code_revision="other"),
                row(1, 10, simulation_version=9), row(1, 10, schema_version=9),
                row(1, 10, execution_settings={"max_turns": 20}), row(1, 10, execution_settings={"max_turns": 40}),
                row(1, 10, goal_policy={"enemy_weight": 1, "item_weight": 1, "stairs_weight": 2, "temperature": 4})]
        self.assertEqual(len(analyze_runs(rows)["cohorts"]), len(rows))

    def test_full_factorial_marginal_means_average_other_weights(self):
        rows = []
        for enemy in range(3):
            for treasure in range(3):
                for stairs in range(3):
                    rows.append(row(enemy, 10 * enemy + 2 * treasure - stairs,
                                    goal_policy={"enemy_weight": enemy, "item_weight": treasure, "stairs_weight": stairs}))
        axis = analyze_runs(rows)["cohorts"][0]["strategies"][0]["axes"]["enemy_weight"]
        self.assertEqual([point["n"] for point in axis["values"]], [9, 9, 9])
        self.assertEqual([round(point["mean_score"], 9) for point in axis["values"]], [1, 11, 21])

    def test_http_uses_all_runs_ignores_outcome_filter_and_records_turn_limit(self):
        with tempfile.TemporaryDirectory() as directory:
            store = RunStore(Path(directory) / "runs.sqlite3")
            for index in range(110):
                start = {"event": "run_start", "run_id": f"r{index}", "sequence": 1,
                         "scenario_seed": 42, "strategy_id": "aggressive_v1", "schema_version": 8,
                         "player_state": {"score": index}, "details": {"goal_policy": {
                             "enemy_weight": index, "item_weight": 1, "stairs_weight": 2, "temperature": 8}}}
                key = store.import_text(json.dumps(start))[0]
                store.record_execution_settings(key, {"max_turns": 5000})
            server = make_server(store, port=0)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            try:
                with urlopen(f"http://127.0.0.1:{server.server_port}/api/weight-analysis?scenario_seed=42&status=cleared&limit=1") as response:
                    data = json.load(response)
                cohort = data["cohorts"][0]
                strategy = cohort["strategies"][0]
                self.assertEqual(cohort["conditions"]["max_turns"], 5000)
                self.assertEqual((strategy["n"], strategy["unfinished"]), (110, 110))
                self.assertAlmostEqual(strategy["axes"]["enemy_weight"]["pearson_r"], 1)
                self.assertEqual(store.weight_analysis({"scenario_seed": 99})["cohorts"], [])
                self.assertEqual(store.weight_analysis({"strategy_id": "cautious_v1"})["cohorts"], [])
                reopened = RunStore(store.path)
                self.assertEqual(reopened.weight_analysis()["cohorts"][0]["conditions"]["max_turns"], 5000)
            finally:
                server.shutdown()
                server.server_close()


if __name__ == "__main__":
    unittest.main()
