import unittest
from compare_strategies import aggregate, metrics, parse_seeds


class ComparisonTests(unittest.TestCase):
    def summary(self, seed=1, strategy='aggressive', outcome='dungeon_cleared'):
        return dict(scenario_seed=seed, strategy_id=strategy + '_v1', outcome=outcome,
                    turns=50, final_depth=5 if outcome == 'dungeon_cleared' else 2,
                    final_level=2, final_score=10, final_hp=10)

    def event(self, result, **details):
        return dict(event='battle_result', details=dict(result=result, enemy_id='b', enemy_type='brute', **details))

    def test_damage_is_actual_hp_loss_and_windups_resolve_once(self):
        events = [self.event('enemy_windup'), self.event('player_hit', player_hp_before=2, player_hp_after=0, damage=8),
                  self.event('enemy_windup'), self.event('enemy_strike_missed'),
                  self.event('enemy_windup'), self.event('enemy_defeated'),
                  self.event('enemy_windup'), dict(event='floor_descend', details={}),
                  self.event('enemy_windup')]
        row = metrics(self.summary(), events)
        self.assertEqual(row['damage_taken'], 2)
        self.assertEqual(row['brute_windups'], 5)
        self.assertEqual([row['brute_hits'], row['brute_misses'], row['brute_interrupted'],
                          row['brute_left_on_descent'], row['brute_unresolved']], [1, 1, 1, 1, 1])

    def test_paired_outcomes_do_not_hide_different_clear_subsets(self):
        rows = [metrics(self.summary(1, 'aggressive'), []), metrics(self.summary(1, 'cautious', 'player_defeated'), []),
                metrics(self.summary(2, 'aggressive', 'turn_limit'), []), metrics(self.summary(2, 'cautious'), [])]
        stats, pairs = aggregate(rows)
        self.assertEqual(stats['aggressive']['clear_rate'], .5)
        self.assertEqual(stats['aggressive']['turn_limit'], 1)
        self.assertEqual(pairs['both_clear'], 0)
        self.assertEqual(pairs['aggressive_only_clear'], 1)
        self.assertEqual(pairs['cautious_only_clear'], 1)
        with self.assertRaises(ValueError):
            aggregate(rows[:-1])
        with self.assertRaises(ValueError):
            aggregate(rows + [rows[0]])

    def test_seeds_are_unique_and_bounded(self):
        self.assertEqual(parse_seeds('3,1-2'), [1, 2, 3])
        for value in ['1,1', '3-1', '-1', '4294967296', '0-4294967295', '']:
            with self.assertRaises(ValueError):
                parse_seeds(value)


if __name__ == '__main__':
    unittest.main()
