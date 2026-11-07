"""Score admission for model observations, never ASR evidence."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import dictation_corpus as corpus
import dictation_model_receipt as receipt


class DictationModelReceiptTests(unittest.TestCase):
    def test_reference_scope_rejection_names_the_public_source(self):
        for speech in (True, False):
            score = dict(wordErrorRate=0, characterErrorRate=0, referenceWords=int(not speech),
                         hypothesisWords=int(not speech), exactReferenceMatch=True, legacyCleanupChangedText=False)
            with self.subTest(speech=speech), self.assertRaisesRegex(corpus.CorpusError, 'reference scope'):
                receipt.validate_score(score, speech_expected=speech)

    def test_word_edit_roundoff_preserves_legitimate_rates_and_empty_speech(self):
        for reference, hypothesis, edits in ((3, 2, 1), (999983, 999979, 333329),
                                              (1, 1000000, 1000000), (2, 0, 2)):
            score = dict(wordErrorRate=edits / reference, characterErrorRate=1,
                         referenceWords=reference, hypothesisWords=hypothesis,
                         exactReferenceMatch=False, legacyCleanupChangedText=False)
            receipt.validate_score(score, speech_expected=True)


if __name__ == '__main__':
    unittest.main()
