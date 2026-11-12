import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BUDGET_MINUTES, measureRun, percentile, render, summarize } from '../../scripts/ci_time_report.mjs';

const at = minute => new Date(Date.UTC(2026, 10, 11, 12, 0, minute * 60)).toISOString().replace('.000Z', 'Z');
const job = (name, start, end, conclusion = 'success') =>
  ({ name, started_at: at(start), completed_at: at(end), conclusion });
const run = (jobs, created = 0) => ({ created_at: at(created), jobs });

test('execution follows the slowest macOS job and leaves runner waits out', () => {
  const measured = measureRun(run([
    job('changes', 0, 0.5),
    job('unit', 9, 12), // waited 8.5 minutes for a runner
    job('ui-smoke', 1, 6),
    job('release-dryrun', 0, 0, 'skipped'),
    job('gate', 12, 12.25),
  ]));
  assert.equal(measured.cohort, 'code');
  assert.equal(measured.execution, 0.5 + 5 + 0.25);
  assert.equal(measured.wall, 12.25);
});

test('a rerun counts its queue from its own attempt', () => {
  const rerun = measureRun({ ...run([job('changes', 30, 31), job('unit', 31, 34), job('gate', 34, 35)]), run_started_at: at(29) });
  assert.equal(rerun.wall, 6);
});

test('cohorts separate packaging, code and docs-only runs', () => {
  const docs = measureRun(run([job('changes', 0, 1), job('unit', 0, 0, 'skipped'), job('gate', 1, 1.5)]));
  const packaging = measureRun(run([job('changes', 0, 1), job('unit', 1, 4), job('release-dryrun', 1, 10), job('gate', 10, 10.5)]));
  assert.deepEqual([docs.cohort, packaging.cohort], ['docs', 'packaging']);
  assert.equal(packaging.execution, 1 + 9 + 0.5);
});

test('a run without a successful gate or changes job is not measured', () => {
  assert.equal(measureRun(run([job('changes', 0, 1), job('gate', 1, 2, 'failure')])), null);
  assert.equal(measureRun(run([job('gate', 1, 2)])), null);
  assert.equal(measureRun({ created_at: 'not a time', jobs: [job('changes', 0, 1), job('gate', 1, 2)] }), null);
});

test('percentiles use the nearest rank and an empty set has none', () => {
  const values = Array.from({ length: 20 }, (_, index) => index + 1);
  assert.equal(percentile(values, 0.5), 10);
  assert.equal(percentile(values, 0.95), 19);
  assert.equal(percentile([], 0.95), null);
});

test('the summary says whether each cohort keeps p95 within the budget', () => {
  const rows = [...Array(19).fill({ cohort: 'code', execution: 6, wall: 7 }), { cohort: 'code', execution: 30, wall: 31 },
    { cohort: 'packaging', execution: BUDGET_MINUTES + 1, wall: 12 }];
  const summary = summarize([...rows, null]);
  assert.equal(summary.code.n, 20);
  assert.equal(summary.code.executionP95, 6);
  assert.equal(summary.code.withinBudget, true);
  assert.equal(summary.packaging.withinBudget, false);
  assert.match(render(summary), /\| packaging \| 1 \| 9\.00 \| 9\.00 \| 12\.00 \| 12\.00 \| no \|/);
});
