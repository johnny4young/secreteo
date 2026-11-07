"""Closed admission for model-only observations, not an ASR quality threshold."""

from __future__ import annotations

import math

import dictation_corpus as corpus


def number(value, maximum):
    return type(value) in (int, float) and 0 <= value <= maximum and math.isfinite(value)


def validate_score(score, *, speech_expected):
    corpus.exact_keys(score, 'wordErrorRate characterErrorRate referenceWords hypothesisWords '
                     'exactReferenceMatch legacyCleanupChangedText', 'model score schema mismatch')
    for key in ('wordErrorRate', 'characterErrorRate'):
        # Replay can legitimately exceed 100% error. Admission must not censor it.
        corpus.require(number(score[key], 1_000_000), 'invalid model error rate')
    for key in ('referenceWords', 'hypothesisWords'):
        corpus.require(corpus.integer(score[key], 0, 1_000_000), 'invalid model word count')
    for key in ('exactReferenceMatch', 'legacyCleanupChangedText'):
        corpus.require(type(score[key]) is bool, 'invalid model score flag')
    reference, hypothesis = score['referenceWords'], score['hypothesisWords']
    if reference:
        # The producer uses unit-cost Levenshtein edits. Reconstruct only the
        # integer count implied by WER; this does not verify the private text.
        edits = score['wordErrorRate'] * reference
        rounded = round(edits)
        corpus.require(math.isclose(edits, rounded, rel_tol=0, abs_tol=1e-8)
                       and abs(reference - hypothesis) <= rounded <= max(reference, hypothesis),
                       'inconsistent model word edits')
        # Words and characters come from one normalized string, so a zero rate is
        # exact and shared: roundoff cannot hide an edit, and CER cannot disagree.
        corpus.require((score['wordErrorRate'] == 0) == (rounded == 0) == (score['characterErrorRate'] == 0),
                       'inconsistent zero-edit score')
        if hypothesis == 0:
            corpus.require(score['wordErrorRate'] == score['characterErrorRate'] == 1,
                           'empty speech output must retain all deletions')
    else:
        # Preserve the existing Swift producer's empty-reference sentinel.
        # This is NOT a defined no-speech WER or a population incidence rate.
        expected = int(hypothesis > 0)
        corpus.require(score['wordErrorRate'] == score['characterErrorRate'] == expected,
                       'inconsistent empty-reference score')
    if score['exactReferenceMatch']:
        corpus.require(score['wordErrorRate'] == score['characterErrorRate'] == 0
                       and score['referenceWords'] == score['hypothesisWords'], 'inconsistent exact match')
    # The known source decides whether a lexical reference exists; internal
    # score consistency cannot establish that scope.
    corpus.require((reference > 0) == speech_expected, 'model reference scope does not match public source')

