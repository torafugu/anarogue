"""Whole-database deletion, confirmation, conflict and API boundary checks."""
import json
from pathlib import Path
import tempfile
import threading
from types import SimpleNamespace
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from run_store import RunStore, ClearConflict, make_server

REFERENCE = Path(__file__).resolve().parents[1] / 'examples/reference-v8/aggressive-seed-424242.jsonl'


class ClearRunsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.store = RunStore(Path(directory.name) / 'runs.sqlite3')
        self.key = self.store.import_file(REFERENCE)[0]
        self.counts = self.store.database_counts()
        self.jobs = SimpleNamespace(lock=threading.Lock(), jobs={})
        self.server = make_server(self.store, port=0, jobs=self.jobs, watch_enabled=True)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    def request(self, body=None, headers=None):
        request = Request(self.url + ('/api/database' if body is None else '/api/database/clear'),
                          data=None if body is None else json.dumps(body).encode(),
                          headers=headers or {'Content-Type': 'application/json'})
        try:
            with urlopen(request) as response:
                return response.status, json.load(response)
        except HTTPError as error:
            return error.code, json.load(error)

    def payload(self):
        return {'confirmation': 'DELETE', 'expected': self.counts}

    def test_delete_events_runs_and_summary_then_database_remains_usable(self):
        self.assertEqual(self.request()[1], {**self.counts, 'watch_enabled': True})
        self.jobs.jobs['finished'] = {'status': 'completed'}
        status, result = self.request(self.payload())
        self.assertEqual(status, 200)
        self.assertEqual(result, {'deleted_runs': 1, 'deleted_events': self.counts['events']})
        self.assertEqual(self.store.database_counts(), {'runs': 0, 'events': 0})
        self.assertEqual(self.jobs.jobs, {})
        self.assertEqual(self.store.stats()['groups'], [])
        with self.assertRaises(KeyError):
            self.store.get_run(self.key)
        self.assertTrue(REFERENCE.is_file())
        self.assertEqual(self.store.import_file(REFERENCE), [self.key])

    def test_confirmation_same_origin_content_type_and_integer_counts(self):
        for body in [{}, [], {'confirmation': 'delete', 'expected': self.counts},
                     {'confirmation': 'DELETE'}, {'confirmation': 'DELETE', 'expected': {'runs': True, 'events': 1}}]:
            self.assertEqual(self.request(body)[0], 400)
        self.assertEqual(self.request(self.payload(), {'Content-Type': 'application/json', 'Origin': 'https://other.example'})[0], 403)
        self.assertEqual(self.request(self.payload(), {'Content-Type': 'text/plain'})[0], 415)
        self.assertEqual(self.store.database_counts(), self.counts)

    def test_changed_totals_and_active_runs_are_rejected_without_deleting(self):
        for state in ('queued', 'running'):
            self.jobs.jobs['active'] = {'status': state}
            self.assertEqual(self.request(self.payload())[0], 409)
            self.assertEqual(self.store.database_counts(), self.counts)
        self.jobs.jobs.clear()
        stale = {'confirmation': 'DELETE', 'expected': {**self.counts, 'events': 0}}
        self.assertEqual(self.request(stale)[0], 409)
        self.assertEqual(self.store.database_counts(), self.counts)
        with self.assertRaises(ClearConflict):
            self.store.clear_runs({'runs': 0, 'events': 0})
        self.assertEqual(len(self.store.events(self.key)), self.counts['events'])

    def test_same_origin_browser_request_through_host_rewriting_proxy(self):
        headers = {'Content-Type': 'application/json', 'Origin': 'http://127.0.0.1:5173',
                   'Sec-Fetch-Site': 'same-origin'}
        self.assertEqual(self.request(self.payload(), headers)[0], 200)

    def test_empty_database_can_be_cleared(self):
        self.store.clear_runs(self.counts)
        self.counts = {'runs': 0, 'events': 0}
        self.assertEqual(self.request(self.payload()), (200, {'deleted_runs': 0, 'deleted_events': 0}))


if __name__ == '__main__':
    unittest.main()
