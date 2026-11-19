"""Two-build matrix comparison over synthetic receipts; no row here is ASR evidence."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts/compare_dictation_controller_matrix.py'
sys.path.append(str(ROOT / 'scripts'))
import dictation_corpus as corpus
import compare_dictation_controller_matrix as comparison

CASES = {'en-short-chat.clean': ('en', 2.0), 'stress-en-short-domain.clean': ('stress', 1.5),
         'es-long-email.clean': ('es', 12.0)}


def row(case, attempt, text, wer, schema):
    cohort, seconds = CASES[case]
    stop = seconds + 0.1
    value = {'caseID': case, 'pass': attempt, 'cohort': cohort, 'inputSeconds': seconds,
             'runtimeState': 'reused-engine' if attempt == 2 or case != 'en-short-chat.clean' else 'first-engine-load',
             'pipelineCompleted': True,
             'proposedOutputScore': {'wordErrorRate': wer, 'characterErrorRate': wer / 2,
                                     'referenceWords': 3, 'hypothesisWords': len(text.split())},
             'controller': {'elapsedSeconds': {'runtimeReady': 0.08 if attempt == 1 else 0.001,
                                               'stopRequested': stop, 'inputEnded': stop + 0.26,
                                               'transcriptionEnded': stop + 0.36, 'deliveryStarted': stop + 0.37}}}
    if schema == 2:
        value['proposedText'] = text
    return value


def write_run(root, texts, *, schema=2, manifest='b' * 64, outcome='observed', cells=None):
    root.mkdir()
    rows = cells if cells is not None else [
        row(case, attempt, texts.get(case, 'same words'), 1.0 if case in texts else 0.0, schema)
        for attempt in (1, 2) for case in CASES]
    identity = {'corpusSHA256': 'a' * 64, 'manifestSHA256': manifest}
    (root / 'matrix-request.json').write_text(json.dumps({
        'kind': 'dictation-controller-matrix-request', 'testBinarySHA256': 'c' * 64,
        'cohorts': [{'id': 'cohort-0000', 'cases': list(CASES)}], **identity}))
    (root / 'matrix-outcome.json').write_text(json.dumps({'outcome': outcome, 'observedCells': len(rows) // 2}))
    (root / 'cohort-0000').mkdir()
    (root / 'cohort-0000/model.json').write_text(json.dumps({
        'kind': 'dictation-controller-model-observation', 'schemaVersion': schema, 'cells': rows, **identity}))
    return root


class DictationControllerComparisonTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def cli(self, *arguments):
        return subprocess.run([sys.executable, '-I', str(SCRIPT), *map(str, arguments)],
                              capture_output=True, text=True, timeout=60, check=False)

    def test_reports_cohort_quality_latency_and_every_changed_text(self):
        before = write_run(self.root / 'before', {})
        after = write_run(self.root / 'after', {'stress-en-short-domain.clean': 'Цдаком'})
        report = comparison.compare(before, after)
        self.assertEqual(report['cells'], 6)
        self.assertEqual(report['cellsWithHigherWER'], 2)
        self.assertEqual(report['quality']['after']['stress']['meanWER'], 1.0)
        self.assertEqual(report['quality']['before']['stress']['meanWER'], 0.0)
        self.assertEqual(report['changedTexts'], [{'caseID': 'stress-en-short-domain.clean', 'passes': [1, 2],
                                                   'before': 'same words', 'after': 'Цдаком'}])
        latency = report['latencySeconds']['after']
        self.assertEqual(latency['trigger -> runtimeReady (cold) [all]']['n'], 1)
        self.assertAlmostEqual(latency['stop -> inputEnded [all]']['p50'], 0.26)
        self.assertEqual(latency['stop -> deliveryStarted [long]']['n'], 2)
        self.assertEqual(latency['stop -> deliveryStarted [short]']['n'], 3)
        result = self.cli(before, after)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('stress-en-short-domain.clean pass 1,2', result.stdout)
        self.assertIn('after  "Цдаком"', result.stdout)
        self.assertEqual(json.loads(self.cli(before, after, '--json').stdout)['changedTexts'][0]['after'], 'Цдаком')

    def test_schema_one_receipts_compare_scores_but_say_text_was_not_recorded(self):
        before = write_run(self.root / 'before', {}, schema=1)
        after = write_run(self.root / 'after', {})
        report = comparison.compare(before, after)
        self.assertFalse(report['textRecorded'])
        self.assertIsNone(report['changedTexts'])
        self.assertIn('not recorded', self.cli(before, after).stdout)

    def test_empty_input_fails_without_printing_a_report(self):
        empty = self.root / 'empty'
        empty.mkdir()
        valid = write_run(self.root / 'valid', {})
        for arguments in ((empty, empty), (empty, valid), (valid, empty)):
            with self.subTest(arguments=arguments):
                result = self.cli(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, '')
                self.assertIn('matrix comparison:', result.stderr)
        no_cells = write_run(self.root / 'no-cells', {}, cells=[])
        result = self.cli(no_cells, no_cells)
        self.assertEqual((result.returncode, result.stdout), (2, ''))

    def test_mismatched_or_unobserved_matrices_are_refused(self):
        before = write_run(self.root / 'before', {})
        others = {
            'other-audio': {'manifest': 'd' * 64},
            'unobserved': {'outcome': 'incomplete'},
            'fewer-cells': {'cells': [row(case, attempt, 'same words', 0.0, 2)
                                      for attempt in (1, 2) for case in list(CASES)[:2]]},
        }
        for name, options in others.items():
            with self.subTest(name=name):
                with self.assertRaises(corpus.CorpusError):
                    comparison.compare(before, write_run(self.root / name, {}, **options))
        malformed = write_run(self.root / 'malformed', {})
        receipt = json.loads((malformed / 'cohort-0000/model.json').read_text())
        del receipt['cells'][0]['proposedOutputScore']
        (malformed / 'cohort-0000/model.json').write_text(json.dumps(receipt))
        result = self.cli(before, malformed)
        self.assertEqual((result.returncode, result.stdout), (2, ''))


if __name__ == '__main__':
    unittest.main()
