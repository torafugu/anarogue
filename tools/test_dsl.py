"""DSL validation must happen before queueing or saving a Run."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from run_jobs import RunJobs
from run_store import RunStore, make_server

ROOT = Path(__file__).resolve().parents[1]
BINARY = Path(os.environ.get("ANAROGUE_RUST_BINARY", ROOT / "simulation-core/target/debug/anarogue-sim"))

@unittest.skipUnless(BINARY.is_file(), "Build the Rust CLI first")
class DslTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.store = RunStore(Path(self.directory.name) / 'runs.sqlite3')
        self.jobs = RunJobs(self.store, BINARY)
        self.addCleanup(self.jobs.close)

    def finish(self, accepted):
        for _ in range(500):
            job = self.jobs.get(accepted['id'])
            if job['status'] in ('completed', 'failed'):
                self.assertEqual(job['status'], 'completed', job)
                return job
            time.sleep(.01)
        self.fail('Run did not finish')

    def test_invalid_dsl_is_rejected_before_acceptance_and_persistence(self):
        for source in ['policy { treasure_weigth = 4 }', 'rule "x" { when self.hp == bow do wait }', 'rule "x" { when self.weapon == archer do wait }', 'rule "x" { do shoot target }']:
            with self.subTest(source=source), self.assertRaisesRegex(ValueError, 'line .*column'):
                self.jobs.submit({'dsl': source})
        self.assertEqual(self.jobs.jobs, {})
        self.assertEqual(self.store.database_counts(), {'runs': 0, 'events': 0})

    def test_partial_overrides_source_trace_and_profile_separation(self):
        source = 'policy { treasure_weight = 7 } rule "Hold" { do wait }'
        job = self.finish(self.jobs.submit({'dsl': source, 'max_turns': 3, 'strategy': 'cautious'}))
        row = self.store.get_run(job['run_id'])
        events = self.store.events(job['run_id'])
        self.assertEqual(row['goal_policy']['item_weight'], 7)
        self.assertEqual(row['goal_policy']['stairs_weight'], 4)
        self.assertEqual(row['execution_settings']['dsl'], source)
        self.assertEqual(events[0]['details']['dsl']['source'], source)
        self.assertIn('dsl-v1:', row['code_revision'])
        decisions = [e for e in events if e['event'] == 'decision']
        self.assertEqual(len(decisions), 3)
        self.assertTrue(all(e['details']['action']['type'] == 'wait' for e in decisions))
        self.assertTrue(all('Hold: selected' in e['details']['reason'] for e in decisions))
        other = self.finish(self.jobs.submit({'dsl': 'rule "Other" { do wait }', 'max_turns': 3}))
        self.assertNotEqual(row['code_revision'], self.store.get_run(other['run_id'])['code_revision'])

    def test_http_validate_does_not_enqueue_and_run_checks_without_validate_button(self):
        server = make_server(self.store, port=0, jobs=self.jobs)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close); self.addCleanup(server.shutdown)
        def post(path, dsl):
            request = Request(f'http://127.0.0.1:{server.server_port}{path}', data=json.dumps({'dsl':dsl}).encode(), headers={'Content-Type':'application/json'})
            return urlopen(request)
        with post('/api/dsl/validate', 'rule "Hold" { do wait }') as response:
            self.assertTrue(json.load(response)['valid'])
        with self.assertRaises(HTTPError) as caught:
            post('/api/jobs', 'rule "Typo" { when self.hpp < 5 do wait }')
        self.assertEqual(caught.exception.code, 400)
        self.assertEqual(self.jobs.jobs, {})
        self.assertEqual(self.store.database_counts()['runs'], 0)

    def test_autorun_applies_dsl_and_rejects_zero_effective_weights(self):
        job = self.finish(self.jobs.submit_batch({'strategies':['aggressive','cautious'], 'enemy_weights':[1], 'item_weights':[2], 'stairs_weights':[1], 'max_turns':2, 'dsl':'rule "Hold" { do wait }'}))
        self.assertEqual(job['completed'], 2)
        with self.assertRaises(ValueError):
            self.jobs.submit_batch({'enemy_weights':[0,1], 'item_weights':[1], 'stairs_weights':[1], 'dsl':'policy { treasure_weight = 0 stairs_weight = 0 }'})

    def test_cli_validation_never_creates_database_and_policy_can_rescue_zero_base(self):
        database = Path(self.directory.name) / 'not-created.sqlite3'
        result = subprocess.run([str(BINARY), '--db', str(database), '--dsl-stdin', 'yes'], input='policy { bad = 1 }', capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(database.exists())
        report = self.jobs.validate_dsl({'enemy_weight':0, 'item_weight':0, 'stairs_weight':0, 'dsl':'policy { stairs_weight = 1 }'})
        self.assertEqual(report['effective_policy']['stairs_weight'],1)
        job = self.finish(self.jobs.submit({'enemy_weight':0, 'item_weight':0, 'stairs_weight':0, 'dsl':'policy { stairs_weight = 1 }', 'max_turns':2}))
        self.assertEqual(self.store.get_run(job['run_id'])['goal_policy']['stairs_weight'], 1)

if __name__ == '__main__':
    unittest.main()
