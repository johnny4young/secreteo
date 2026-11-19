#!/usr/bin/env python3
"""Compare two observed controller matrices of the same audio: quality, latency and changed text."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics
import sys
import unicodedata

sys.path.append(str(Path(__file__).resolve().parent))  # after the standard library: -I leaves this folder out

import dictation_corpus as corpus

SHORT_SECONDS, LONG_SECONDS = 4, 8
SEGMENTS = (
    ('trigger -> runtimeReady (cold)', 'cold', None, 'runtimeReady'),
    ('trigger -> runtimeReady (warm)', 'warm', None, 'runtimeReady'),
    ('stop -> inputEnded', 'warm', 'stopRequested', 'inputEnded'),
    ('inputEnded -> transcriptionEnded', 'warm', 'inputEnded', 'transcriptionEnded'),
    ('stop -> deliveryStarted', 'warm', 'stopRequested', 'deliveryStarted'),
)


def load(directory):
    """Rows of one observed matrix, keyed by (case, pass), plus its identity."""
    directory = Path(directory)
    request, _ = corpus.read_json(directory / 'matrix-request.json')
    outcome, _ = corpus.read_json(directory / 'matrix-outcome.json')
    corpus.require(type(request) is dict and request.get('kind') == 'dictation-controller-matrix-request',
                   'not a controller matrix request')
    corpus.require(type(outcome) is dict and outcome.get('outcome') == 'observed', 'matrix was not observed')
    cohorts = request.get('cohorts')
    corpus.require(type(cohorts) is list and cohorts, 'matrix has no cohorts')
    rows, texts = {}, True
    for cohort in cohorts:
        corpus.require(type(cohort) is dict and corpus.identifier(cohort.get('id')), 'invalid cohort identity')
        receipt, _ = corpus.read_json(directory / cohort['id'] / 'model.json', maximum_bytes=8_000_000)
        corpus.require(type(receipt) is dict and receipt.get('kind') == 'dictation-controller-model-observation'
                       and receipt.get('schemaVersion') in (1, 2)
                       and receipt.get('corpusSHA256') == request.get('corpusSHA256')
                       and receipt.get('manifestSHA256') == request.get('manifestSHA256'),
                       'cohort receipt belongs to another matrix')
        texts &= receipt['schemaVersion'] >= 2
        for row in receipt.get('cells') or []:
            key = (row['caseID'], row['pass'])
            corpus.require(key not in rows, 'duplicate matrix cell')
            rows[key] = row
    corpus.require(rows and len(rows) == 2 * outcome.get('observedCells', -1), 'matrix has missing cells')
    identity = {key: request.get(key) for key in ('corpusSHA256', 'manifestSHA256')}
    corpus.require(all(corpus.digest(value) for value in identity.values()), 'matrix has no audio identity')
    return {'identity': identity, 'rows': rows, 'texts': texts, 'testBinarySHA256': request.get('testBinarySHA256')}


def percentile(values, share):
    ordered = sorted(values)
    # Nearest rank, so the median does not move with the parity of the sample size.
    return ordered[max(0, math.ceil(share * len(ordered)) - 1)] if ordered else None


def quality(rows):
    """Second-pass mean WER/CER per cohort; an empty is a speech cell that offered no words."""
    cohorts = {}
    for row in rows.values():
        if row['pass'] == 2:
            cohorts.setdefault(row['cohort'], []).append(row)
    result = {}
    for cohort, cells in sorted(cohorts.items()):
        scores = [cell['proposedOutputScore'] for cell in cells]
        result[cohort] = {
            'cells': len(cells),
            'meanWER': statistics.fmean(score['wordErrorRate'] for score in scores),
            'meanCER': statistics.fmean(score['characterErrorRate'] for score in scores),
            'emptySpeech': sum(1 for score in scores if score['referenceWords'] and not score['hypothesisWords']),
        }
    return result


def latency(rows):
    groups = {'cold': [r for r in rows.values() if r['runtimeState'] == 'first-engine-load'],
              'warm': [r for r in rows.values() if r['runtimeState'] == 'reused-engine' and r['pipelineCompleted']]}
    result = {}
    for name, group, start, end in SEGMENTS:
        for length, keep in (('all', lambda s: True), ('short', lambda s: s < SHORT_SECONDS),
                             ('long', lambda s: s >= LONG_SECONDS)):
            values = []
            for row in groups[group]:
                phases = row['controller']['elapsedSeconds']
                if keep(row['inputSeconds']) and end in phases and (start is None or start in phases):
                    values.append(phases[end] - (phases[start] if start else 0))
            result[f'{name} [{length}]'] = {'n': len(values), 'p50': percentile(values, 0.5),
                                            'p95': percentile(values, 0.95)}
    return result


def changed_texts(before, after):
    changes = {}
    for key in sorted(before):
        old, new = before[key].get('proposedText'), after[key].get('proposedText')
        if unicodedata.normalize('NFC', old or '') != unicodedata.normalize('NFC', new or ''):
            changes.setdefault((key[0], old, new), []).append(key[1])
    return [{'caseID': case, 'passes': passes, 'before': old, 'after': new}
            for (case, old, new), passes in sorted(changes.items(), key=lambda item: item[0][0])]


def compare(before_directory, after_directory):
    before, after = load(before_directory), load(after_directory)
    corpus.require(before['identity'] == after['identity'], 'matrices used different corpus or audio')
    corpus.require(before['rows'].keys() == after['rows'].keys(), 'matrices observed different cells')
    wer = {name: {key: row['proposedOutputScore']['wordErrorRate'] for key, row in run['rows'].items()}
           for name, run in (('before', before), ('after', after))}
    return {
        'kind': 'dictation-controller-matrix-comparison', 'schemaVersion': 1,
        'attempts': len(before['rows']), **before['identity'],
        'testBinarySHA256': {'before': before['testBinarySHA256'], 'after': after['testBinarySHA256']},
        'quality': {'before': quality(before['rows']), 'after': quality(after['rows'])},
        'latencySeconds': {'before': latency(before['rows']), 'after': latency(after['rows'])},
        'attemptsWithLowerWER': sum(wer['after'][key] < wer['before'][key] for key in wer['before']),
        'attemptsWithHigherWER': sum(wer['after'][key] > wer['before'][key] for key in wer['before']),
        'textRecorded': before['texts'] and after['texts'],
        'changedTexts': changed_texts(before['rows'], after['rows']) if before['texts'] and after['texts'] else None,
    }


def render(report):
    milliseconds = lambda value: '-' if value is None else f'{value * 1000:.0f}'
    lines = [f"attempts {report['attempts']}  lower WER {report['attemptsWithLowerWER']}  "
             f"higher WER {report['attemptsWithHigherWER']}", '',
             f"{'cohort (pass 2)':16} {'WER before':>10} {'after':>7} {'CER before':>10} {'after':>7} "
             f"{'empty before':>12} {'after':>5}"]
    before, after = report['quality']['before'], report['quality']['after']
    for cohort in sorted(before.keys() | after.keys()):
        b, a = before.get(cohort, {}), after.get(cohort, {})
        lines.append(f"{cohort:16} {b.get('meanWER', 0):10.3f} {a.get('meanWER', 0):7.3f} "
                     f"{b.get('meanCER', 0):10.3f} {a.get('meanCER', 0):7.3f} "
                     f"{b.get('emptySpeech', 0):12} {a.get('emptySpeech', 0):5}")
    lines += ['', f"{'latency ms':42} {'n':>9} {'p50 before':>10} {'after':>6} {'p95 before':>10} {'after':>6}"]
    for name, b in report['latencySeconds']['before'].items():
        a = report['latencySeconds']['after'][name]
        lines.append(f"{name:42} {str(b['n']) + '/' + str(a['n']):>9} {milliseconds(b['p50']):>10} {milliseconds(a['p50']):>6} "
                     f"{milliseconds(b['p95']):>10} {milliseconds(a['p95']):>6}")
    lines.append('')
    if report['changedTexts'] is None:
        lines.append('changed text: not recorded (a schema 1 receipt has no proposed text)')
    else:
        lines.append(f"changed text: {len(report['changedTexts'])}")
        for change in report['changedTexts']:
            lines.append(f"{change['caseID']} pass {','.join(map(str, change['passes']))}")
            lines.append(f"  before {json.dumps(change['before'], ensure_ascii=False)}")
            lines.append(f"  after  {json.dumps(change['after'], ensure_ascii=False)}")
    return '\n'.join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('before', type=Path, help='Matrix output directory of the baseline build')
    parser.add_argument('after', type=Path, help='Matrix output directory of the candidate build')
    parser.add_argument('--json', action='store_true', help='Print the report as JSON')
    arguments = parser.parse_args(argv)
    try:
        report = compare(arguments.before, arguments.after)
        output = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) if arguments.json else render(report)
        output.encode('utf-8')
    except corpus.CorpusError as error:
        print(f'matrix comparison: {error}', file=sys.stderr)
        return 2
    except (OSError, KeyError, TypeError, AttributeError, ValueError, UnicodeError):
        print('matrix comparison: a receipt is incomplete or malformed', file=sys.stderr)
        return 2
    print(output)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
