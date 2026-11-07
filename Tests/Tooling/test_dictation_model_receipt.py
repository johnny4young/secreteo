"""Score admission for model observations, never ASR evidence."""

from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.append(str(ROOT / 'scripts'))
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

    def test_inconsistent_scores_are_refused(self):
        def score(wer, cer, reference, hypothesis, exact=False):
            return dict(wordErrorRate=wer, characterErrorRate=cer, referenceWords=reference,
                        hypothesisWords=hypothesis, exactReferenceMatch=exact, legacyCleanupChangedText=False)
        cases = (
            (score(0.25, 0.1, 2, 2), True, 'inconsistent model word edits'),
            (score(0.5, 0, 2, 2), True, 'inconsistent zero-edit score'),
            (score(0, 0.1, 2, 2), True, 'inconsistent zero-edit score'),
            (score(1, 0.5, 2, 0), True, 'empty speech output must retain all deletions'),
            (score(0, 0, 0, 3), False, 'inconsistent empty-reference score'),
            (score(0.5, 0.2, 2, 2, exact=True), True, 'inconsistent exact match'),
        )
        for candidate, speech, message in cases:
            with self.subTest(message=message, score=candidate), self.assertRaisesRegex(corpus.CorpusError, message):
                receipt.validate_score(candidate, speech_expected=speech)

    def test_empty_reference_sentinels_are_admitted(self):
        for hypothesis, rate in ((0, 0), (3, 1)):
            receipt.validate_score(dict(wordErrorRate=rate, characterErrorRate=rate, referenceWords=0,
                                        hypothesisWords=hypothesis, exactReferenceMatch=False,
                                        legacyCleanupChangedText=False), speech_expected=False)


if __name__ == '__main__':
    unittest.main()
