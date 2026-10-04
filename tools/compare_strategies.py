#!/usr/bin/env python3
"""Run both policies on identical seeds and write reproducible comparison artifacts."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
STRATEGIES = ('aggressive', 'cautious')
ENEMIES = ('melee', 'archer', 'brute')


def parse_seeds(value):
    seeds = []
    for part in value.split(','):
        bounds = part.strip().split('-')
        if len(bounds) == 1:
            seeds.append(int(bounds[0]))
        elif len(bounds) == 2 and int(bounds[0]) <= int(bounds[1]):
            if int(bounds[1]) - int(bounds[0]) > 9999:
                raise ValueError('limit each comparison to 10,000 seeds')
            seeds.extend(range(int(bounds[0]), int(bounds[1]) + 1))
        else:
            raise ValueError('use comma-separated seeds or ascending ranges, e.g. 1-50,301')
    if not seeds or len(seeds) != len(set(seeds)) or any(s < 0 or s > 0xffffffff for s in seeds):
        raise ValueError('seeds must be unique unsigned 32-bit integers')
    return sorted(seeds)


def metrics(summary, events):
    row = dict(summary)
    row.update(damage_taken=0, potions_used=0, bow_shots=0, brute_windups=0,
               brute_hits=0, brute_misses=0, brute_interrupted=0, brute_left_on_descent=0)
    row.update({f'kills_{kind}': 0 for kind in ENEMIES})
    pending = set()
    for event in events:
        d = event['details']
        if event['event'] in ('floor_start', 'floor_descend'):
            row['brute_left_on_descent'] += len(pending)
            pending.clear()
        if event['event'] == 'user_action' and d.get('action') == 'shoot':
            row['bow_shots'] += 1
        if event['event'] == 'item_result' and d.get('result') == 'item_used':
            row['potions_used'] += 1
        if event['event'] != 'battle_result':
            continue
        result, kind, enemy_id = d.get('result'), d.get('enemy_type'), d.get('enemy_id')
        if result == 'player_hit':
            row['damage_taken'] += d['player_hp_before'] - d['player_hp_after']
            if kind == 'brute':
                row['brute_hits'] += 1
                pending.discard(enemy_id)
        elif result == 'enemy_defeated':
            row[f'kills_{kind}'] += 1
            if enemy_id in pending:
                row['brute_interrupted'] += 1
                pending.remove(enemy_id)
        elif result == 'enemy_windup':
            row['brute_windups'] += 1
            pending.add(enemy_id)
        elif result == 'enemy_strike_missed':
            row['brute_misses'] += 1
            pending.discard(enemy_id)
    row['brute_unresolved'] = len(pending)
    assert row['brute_windups'] == sum(row[k] for k in (
        'brute_hits', 'brute_misses', 'brute_interrupted', 'brute_left_on_descent', 'brute_unresolved'))
    return row


def aggregate(rows):
    result = {}
    for strategy in STRATEGIES:
        runs = [r for r in rows if r['strategy_id'] == strategy + '_v1']
        if not runs:
            raise ValueError('both strategies require runs')
        clears = [r for r in runs if r['outcome'] == 'dungeon_cleared']
        result[strategy] = {
            'runs': len(runs), 'cleared': len(clears),
            'defeated': sum(r['outcome'] == 'player_defeated' for r in runs),
            'turn_limit': sum(r['outcome'] == 'turn_limit' for r in runs),
            'clear_rate': len(clears) / len(runs),
            'mean_clear_turns': statistics.mean(r['turns'] for r in clears) if clears else None,
            **{'mean_' + key: statistics.mean(r[key] for r in runs) for key in (
                'final_depth', 'turns', 'damage_taken', 'final_level', 'final_score', 'final_hp',
                'bow_shots', 'potions_used', 'kills_melee', 'kills_archer', 'kills_brute')},
            **{'total_' + key: sum(r[key] for r in runs) for key in (
                'brute_windups', 'brute_hits', 'brute_misses', 'brute_interrupted',
                'brute_left_on_descent', 'brute_unresolved')},
        }
    by_seed = {}
    for row in rows:
        pair = by_seed.setdefault(row['scenario_seed'], {})
        if row['strategy_id'] in pair:
            raise ValueError('duplicate strategy/seed pair')
        pair[row['strategy_id']] = row
    paired = dict(both_clear=0, aggressive_only_clear=0, cautious_only_clear=0, neither_clear=0,
                  aggressive_deeper=0, cautious_deeper=0, equal_depth=0)
    for pair in by_seed.values():
        if set(pair) != {'aggressive_v1', 'cautious_v1'}:
            raise ValueError('missing paired run')
        a, c = pair['aggressive_v1'], pair['cautious_v1']
        ac, cc = a['outcome'] == 'dungeon_cleared', c['outcome'] == 'dungeon_cleared'
        paired['both_clear' if ac and cc else 'aggressive_only_clear' if ac else
               'cautious_only_clear' if cc else 'neither_clear'] += 1
        paired['aggressive_deeper' if a['final_depth'] > c['final_depth'] else
               'cautious_deeper' if c['final_depth'] > a['final_depth'] else 'equal_depth'] += 1
    return result, paired


def write_report(output, parameters, rows):
    aggregates, paired = aggregate(rows)
    report = dict(simulation_version=7, randomness_version=1, parameters=parameters,
                  aggregates=aggregates, paired=paired, runs=rows)
    output.mkdir(parents=True, exist_ok=True)
    (output / 'comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    with (output / 'runs.csv').open('w', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader(); writer.writerows(rows)
    def fmt(v):
        return '—' if v is None else str(v) if isinstance(v, int) else f'{v:.2f}'
    lines = ['# Strategy comparison: simulation v7', '',
             f"Seeds: {', '.join(map(str, parameters['seeds']))}. Map: {parameters['width']}×{parameters['height']}. Budget: {parameters['max_turns']} turns.", '',
             '| Metric | Aggressive | Cautious |', '| --- | ---: | ---: |']
    fields = [('Clears / runs', None), ('Clear rate', 'clear_rate'),
              ('Defeats', 'defeated'), ('Turn limits', 'turn_limit'), ('Mean final depth', 'mean_final_depth'),
              ('Mean turns (clears only)', 'mean_clear_turns'), ('Mean HP lost (all runs)', 'mean_damage_taken'),
              ('Mean final level', 'mean_final_level'), ('Mean score', 'mean_final_score'),
              ('Mean Brute kills', 'mean_kills_brute'), ('Mean bow shots', 'mean_bow_shots'),
              ('Brute windups', 'total_brute_windups'), ('Brute hits', 'total_brute_hits'),
              ('Brute misses', 'total_brute_misses'), ('Brute interrupted by kill', 'total_brute_interrupted'),
              ('Brute windups left on descent', 'total_brute_left_on_descent'), ('Brute unresolved', 'total_brute_unresolved')]
    for label, key in fields:
        values = []
        for strategy in STRATEGIES:
            stats = aggregates[strategy]
            values.append(f"{stats['cleared']}/{stats['runs']}" if key is None else
                          f"{stats[key]:.0%}" if key == 'clear_rate' else fmt(stats[key]))
        lines.append(f'| {label} | {values[0]} | {values[1]} |')
    lines += ['', 'Paired outcomes: ' + ', '.join(f'{k}={v}' for k, v in paired.items()) + '.', '',
              'Both policies use identical seeds, layouts, initial enemies and items. Depth 5 means completion.',
              'These are descriptive results for the listed sample and map size, not a general balance claim.',
              'HP lost includes armor mitigation and clamps a lethal hit to remaining HP; healing can make cumulative loss exceed maximum HP.',
              'All-run damage and level averages include short defeated runs. Clear-only turns can compare different subsets of seeds.',
              'Raw per-run data and paired completion counts are supplied to make these differences visible.', '',
              'Source fingerprint (core + policy): `' + parameters['source_sha256'] + '`.', '']
    (output / 'README.md').write_text('\n'.join(lines))
    return aggregates, paired


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seeds', default='1-50')
    parser.add_argument('--width', type=int, default=44)
    parser.add_argument('--height', type=int, default=28)
    parser.add_argument('--max-turns', type=int, default=500)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'logs' / 'strategy-comparison')
    parser.add_argument('--log-dir', type=Path, help='retain replayable JSONL logs; otherwise use temporary files')
    parser.add_argument('--binary', type=Path, help='existing anarogue-sim executable; otherwise build release')
    args = parser.parse_args()
    try:
        seeds = parse_seeds(args.seeds)
    except ValueError as error:
        parser.error(str(error))
    if args.width < 15 or args.height < 15 or args.max_turns <= 0:
        parser.error('map dimensions must be at least 15 and max-turns positive')
    binary = args.binary
    if binary is None:
        subprocess.run(['cargo', 'build', '--release', '--manifest-path', str(ROOT / 'simulation-core/Cargo.toml')], check=True)
        binary = ROOT / 'simulation-core/target/release/anarogue-sim'
    binary = binary.resolve()
    source = b''.join((ROOT / path).read_bytes() for path in ['simulation-core/src/lib.rs', 'tools/compare_strategies.py'])
    parameters = dict(seeds=seeds, width=args.width, height=args.height, max_turns=args.max_turns,
                      source_sha256=hashlib.sha256(source).hexdigest())
    rows = []
    with tempfile.TemporaryDirectory(prefix='anarogue-comparison-') as temporary:
        log_dir = args.log_dir or Path(temporary)
        log_dir.mkdir(parents=True, exist_ok=True)
        for seed in seeds:
            for strategy in STRATEGIES:
                log = log_dir / f'{strategy}-{seed}.jsonl'
                run = subprocess.run([str(binary), '--strategy', strategy, '--seed', str(seed),
                    '--width', str(args.width), '--height', str(args.height), '--max-turns', str(args.max_turns),
                    '--output', str(log)], check=True, text=True, capture_output=True)
                summary = json.loads(run.stdout)
                events = [json.loads(line) for line in log.read_text().splitlines()]
                if not events or any(e['schema_version'] != 7 for e in events):
                    raise ValueError('comparison requires a simulation v7 binary')
                rows.append(metrics(summary, events))
            print(f'Compared seed {seed} ({len(rows)} runs)', flush=True)
    stats, paired = write_report(args.output_dir, parameters, rows)
    print(json.dumps(dict(output_dir=str(args.output_dir), aggregates=stats, paired=paired), indent=2))


if __name__ == '__main__':
    main()
