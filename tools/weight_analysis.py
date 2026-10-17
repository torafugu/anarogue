"""Descriptive weight/Score analysis; no external statistics dependencies."""
import hashlib
import json
import math

WEIGHTS = ("enemy_weight", "item_weight", "stairs_weight")


class Axis:
    def __init__(self):
        self.n = 0
        self.x = self.y = self.xx = self.yy = self.xy = 0.0
        self.values = {}

    def add(self, weight, score, unfinished):
        self.n += 1
        dx, dy = weight - self.x, score - self.y
        self.x += dx / self.n
        self.y += dy / self.n
        self.xx += dx * (weight - self.x)
        self.yy += dy * (score - self.y)
        self.xy += dx * (score - self.y)
        point = self.values.setdefault(weight, {"weight": weight, "n": 0, "mean_score": 0.0, "unfinished": 0})
        point["n"] += 1
        point["mean_score"] += (score - point["mean_score"]) / point["n"]
        point["unfinished"] += int(unfinished)

    def result(self):
        reason = ("fewer_than_two_runs" if self.n < 2 else "constant_weight" if self.xx <= 0
                  else "constant_score" if self.yy <= 0 else None)
        r = None if reason else max(-1.0, min(1.0, self.xy / math.sqrt(self.xx * self.yy)))
        return {"n": self.n, "pearson_r": r, "undefined_reason": reason,
                "values": [self.values[value] for value in sorted(self.values)]}


def analyze_runs(rows):
    cohorts = {}
    excluded = 0
    for row in rows:
        policy = row["goal_policy"]
        score = row["score"]
        if not isinstance(policy, dict) or any(type(policy.get(key)) not in (int, float) or not math.isfinite(policy[key]) or policy[key] < 0
               for key in WEIGHTS) or type(score) not in (int, float) or not math.isfinite(score):
            excluded += 1
            continue
        conditions = {key: row[key] for key in ("scenario_seed", "scenario_id", "simulation_version", "schema_version", "code_revision")}
        conditions["max_turns"] = row.get("execution_settings", {}).get("max_turns")
        conditions["other_policy"] = {key: value for key, value in policy.items() if key not in WEIGHTS}
        key = json.dumps(conditions, sort_keys=True, separators=(",", ":"))
        cohort = cohorts.setdefault(key, {"id": hashlib.sha256(key.encode()).hexdigest()[:16],
                                          "conditions": conditions, "strategies": {}})
        strategy = cohort["strategies"].setdefault(row["strategy_id"], {
            "strategy_id": row["strategy_id"], "n": 0, "unfinished": 0,
            "axes": {weight: Axis() for weight in WEIGHTS}})
        unfinished = row["status"] == "unfinished"
        strategy["n"] += 1
        strategy["unfinished"] += int(unfinished)
        for weight in WEIGHTS:
            strategy["axes"][weight].add(policy[weight], score, unfinished)
    result = []
    for key in sorted(cohorts):
        cohort = cohorts[key]
        strategies = []
        for name in sorted(cohort["strategies"]):
            strategy = cohort["strategies"][name]
            strategies.append({**strategy, "axes": {weight: axis.result() for weight, axis in strategy["axes"].items()}})
        result.append({**cohort, "strategies": strategies})
    result.sort(key=lambda cohort: -sum(strategy["n"] for strategy in cohort["strategies"]))
    return {"cohorts": result, "excluded_runs": excluded}
