import json
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.request import urlopen

from run_store import RunStore, make_server


class MeanMetricsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / 'runs.sqlite3')

    def add_run(self, name, score, finished=False, enemy=0, strategy='aggressive_v1'):
        player = dict(score=score, level=score, gold=score)
        events = [dict(run_id=name, sequence=1, event='run_start', strategy_id=strategy,
                       scenario_seed=42, player_state=player,
                       details=dict(goal_policy=dict(enemy_weight=enemy, item_weight=1, stairs_weight=2, temperature=8)))]
        for kind, details in [('decision', {}), ('battle_result', dict(result='enemy_defeated')),
                              ('battle_result', dict(result='player_hit', damage=score)),
                              ('item_result', dict(result='item_picked_up')),
                              ('item_result', dict(result='item_used', healed=score))]:
            events.append(dict(run_id=name, sequence=len(events)+1, event=kind, turn=score,
                               depth=score, player_state=player, details=details))
        if finished:
            events.append(dict(run_id=name, sequence=len(events)+1, event='battle_result',
                               turn=score, depth=score, player_state=player, details=dict(result='dungeon_cleared')))
        return self.store.import_text('\n'.join(map(json.dumps, events)))[0]

    def test_all_metrics_and_historical_decisions(self):
        key = self.add_run('a', 2, finished=True)
        self.add_run('b', 5)
        # Rust and previously imported summaries may not store Decisions.
        with self.store.connect() as db:
            db.execute("UPDATE runs SET summary=json_remove(summary, '$.decisions') WHERE id=?", (key,))
        data = self.store.mean_metrics()
        self.assertEqual((data['runs'], data['unfinished']), (2, 1))
        self.assertEqual(data['means'], dict(score=3.5, level=3.5, turns=3.5, max_depth=3.5,
            kills=1, damage_taken=3.5, gold=3.5, decisions=1, potions_picked_up=1, potions_used=1, hp_healed=3.5))
        self.assertEqual(self.store.mean_metrics(dict(status='cleared'))['means']['score'], 2)

    def test_filters_and_all_rows_over_pagination(self):
        for i in range(105):
            self.add_run(str(i), 2)
        self.add_run('different-weight', 900, enemy=1)
        self.add_run('different-strategy', 900, strategy='cautious_v1')
        filters = dict(strategy_id='aggressive_v1', enemy_weight='0', item_weight='1', stairs_weight='2', temperature='8', scenario_seed='42')
        result = self.store.mean_metrics(filters)
        self.assertEqual((result['runs'], result['means']['score']), (105, 2))
        empty = self.store.mean_metrics({**filters, 'scenario_seed': '43'})
        self.assertEqual((empty['runs'], empty['unfinished']), (0, 0))
        self.assertTrue(all(value is None for value in empty['means'].values()))
        server = make_server(self.store, port=0)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            with urlopen(f'http://127.0.0.1:{server.server_port}/api/mean-metrics?enemy_weight=0&strategy_id=aggressive_v1&limit=1&offset=100') as response:
                self.assertEqual(json.load(response), result)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
