"""Admission and report of the v3 against Ultra comparison, with synthetic receipts only."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / 'scripts'))
import dictation_corpus as corpus
import run_dictation_model_comparison as comparison
from test_dictation_materialization import NAMES, SpeechDouble
from materialize_dictation_corpus import materialize


class DictationModelComparisonTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.shared = tempfile.TemporaryDirectory()
        cls.audio = Path(cls.shared.name) / 'audio'
        materialize(cls.audio, NAMES, SpeechDouble())
        cls.digest = corpus.read_json(cls.audio / 'manifest.json')[1]

    @classmethod
    def tearDownClass(cls):
        cls.shared.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'tests.xctest').mkdir()
        (self.root / 'models').mkdir()
        (self.root / 'xctest').touch()
        self.cases = ['en-decimal-contrast.clean', 'en-payment-negation.clean']
        self.mutate = lambda receipt: None
        self.failed = set()

    def score(self, words, errors=0):
        return {'wordErrorRate': errors / words, 'characterErrorRate': errors / words, 'referenceWords': words,
                'hypothesisWords': words, 'exactReferenceMatch': errors == 0, 'legacyCleanupChangedText': False}

    def invoke(self, arguments, **options):
        env = options['env']
        model = env['SECRETEO_ASR_COMPARE_MODEL']
        cells = []
        for case in env['SECRETEO_ASR_COMPARE_CASES'].split(','):
            failed = (model, case) in self.failed
            cells.append({'model': comparison.MODELS[model], 'caseID': case, 'group': 'g', 'shape': 'clean',
                          'critical': False, 'score': None if failed else self.score(8 if 'decimal' in case else 5),
                          'failure': 'engineEndedEarly' if failed else None, 'inputSeconds': 1,
                          'firstUpdateSeconds': None, 'completionSeconds': None, 'inputEndSeconds': None})
        receipt = {'kind': 'dictation-model-comparison-observation', 'schemaVersion': 2,
                   'corpus': 'public-synthetic', 'corpusSHA256': corpus.CORPUS_SHA256,
                   'manifestSHA256': self.digest, 'feed': 'realtime-100ms-bounded-pcm',
                   'models': [{'model': comparison.MODELS[model], 'revision': '0' * 40, 'loadSeconds': 1,
                               'footprintBeforeLoadBytes': 1, 'footprintAfterLoadBytes': 2,
                               'footprintAfterCellsBytes': 2, 'peakFootprintBytes': 3}],
                   'cells': cells}
        self.mutate(receipt)
        Path(env['SECRETEO_ASR_COMPARE_OUTPUT']).write_text(json.dumps(receipt))
        return subprocess.CompletedProcess(arguments, 0)

    def run_comparison(self, invoke=None):
        return comparison.run(self.audio, self.root / 'models', self.root / 'tests.xctest', self.root / 'xctest',
                              self.root / 'run', self.cases, invoke=invoke or self.invoke)

    def outcome(self):
        return json.loads((self.root / 'run/outcome.json').read_text())['outcome']

    def test_a_failed_cell_counts_the_words_the_scorer_counts(self):
        self.failed = {('ultra', 'en-decimal-contrast.clean')}
        result = self.run_comparison()
        self.assertEqual(result['outcome'], 'observed')
        self.assertEqual(self.outcome(), 'observed')
        # The scorer counts 8 words in "0.05, not 0.5"; a plain split counts 6.
        self.assertAlmostEqual(result['models']['ultra']['wordErrorRate'], 8 / 13)

    def test_a_receipt_for_another_manifest_is_refused(self):
        self.mutate = lambda receipt: receipt.update(manifestSHA256='0' * 64)
        self.assertEqual(self.run_comparison()['outcome'], 'invalid-observation')
        self.assertEqual(self.outcome(), 'invalid-observation')

    def test_malformed_receipts_end_as_a_refusal_not_a_traceback(self):
        mutations = [
            lambda receipt: receipt['cells'][0].update(score={}),
            lambda receipt: receipt.update(cells='not a list'),
            lambda receipt: receipt['cells'].__setitem__(0, 'not a cell'),
            lambda receipt: receipt.update(models=['not a model']),
        ]
        for index, mutation in enumerate(mutations):
            with self.subTest(index=index):
                self.mutate = mutation
                self.assertEqual(self.run_comparison()['outcome'], 'invalid-observation')
                self.assertEqual(self.outcome(), 'invalid-observation')
            self.reset_run()

    def reset_run(self):
        for path in sorted((self.root / 'run').glob('*')):
            path.unlink()
        (self.root / 'run').rmdir()

    def test_a_failed_launch_still_publishes_its_outcome(self):
        def fail(arguments, **options):
            return subprocess.CompletedProcess(arguments, 1)
        result = self.run_comparison(fail)
        self.assertEqual(result['outcome'], 'tests-failed')
        self.assertEqual(self.outcome(), 'tests-failed')

    def test_the_decision_names_why_a_cohort_did_not_count(self):
        def summary(rates):
            return {'wordErrorRateByCohort': rates, 'criticalCellsWithErrors': 0,
                    'peakFootprintBytes': 1, 'warmLoadSeconds': 1}
        decision = comparison.decide('field-microphone', summary({'en': 0.2, 'es': 0.0}),
                                     summary({'en': 0.1, 'es': 0.0}))
        self.assertEqual(decision['verdict'], 'stay-opt-in')
        self.assertEqual(decision['failedCriteria'], ['es has no v3 errors to reduce', 'mixed not measured'])


if __name__ == '__main__':
    unittest.main()
