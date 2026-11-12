#!/usr/bin/env node
// PR clock from GitHub's job records: queue apart from execution, by cohort.
// Usage: node scripts/ci_time_report.mjs [count]
import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const BUDGET_MINUTES = 8;
const MAC_JOBS = ['unit', 'ui-smoke', 'signed-handoff', 'release-dryrun'];

const time = value => {
  const parsed = typeof value === 'string' ? Date.parse(value) : NaN;
  return Number.isFinite(parsed) ? parsed : null;
};
const minutes = (from, to) => (to - from) / 60_000;
const ran = job => job?.conclusion === 'success' && time(job.started_at) !== null && time(job.completed_at) !== null;
const duration = job => (ran(job) ? minutes(time(job.started_at), time(job.completed_at)) : 0);

/** Null for a run that is not a complete, successful gate. */
export function measureRun(run) {
  const byName = new Map(run.jobs.map(job => [job.name, job]));
  const gate = byName.get('gate');
  const changes = byName.get('changes');
  // A rerun's clock starts at its own attempt, not at the first one.
  const created = time(run.run_started_at ?? run.created_at);
  if (!ran(gate) || !ran(changes) || created === null) return null;
  // Execution is the dependency path changes → slowest macOS job → gate, so runner waits between jobs
  // count as queue, not as the work this repository asks for.
  const execution = duration(changes) + Math.max(0, ...MAC_JOBS.map(name => duration(byName.get(name)))) + duration(gate);
  const cohort = ran(byName.get('release-dryrun')) ? 'packaging' : ran(byName.get('unit')) ? 'code' : 'docs';
  return { cohort, execution, wall: minutes(created, time(gate.completed_at)) };
}

export function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1))];
}

export function summarize(measured) {
  const cohorts = {};
  for (const row of measured.filter(Boolean)) (cohorts[row.cohort] ??= []).push(row);
  return Object.fromEntries(Object.entries(cohorts).sort().map(([name, rows]) => {
    const execution = rows.map(row => row.execution);
    const wall = rows.map(row => row.wall);
    return [name, {
      n: rows.length, executionP50: percentile(execution, 0.5), executionP95: percentile(execution, 0.95),
      wallP50: percentile(wall, 0.5), wallP95: percentile(wall, 0.95),
      withinBudget: percentile(execution, 0.95) <= BUDGET_MINUTES,
    }];
  }));
}

export function render(summary) {
  const fixed = value => value.toFixed(2);
  const lines = ['| Cohort | N | Execution p50 | Execution p95 | With queue p50 | With queue p95 | p95 within 8 min |',
    '|---|---|---|---|---|---|---|'];
  for (const [name, row] of Object.entries(summary)) {
    lines.push(`| ${name} | ${row.n} | ${fixed(row.executionP50)} | ${fixed(row.executionP95)} | ${fixed(row.wallP50)} | ` +
      `${fixed(row.wallP95)} | ${row.withinBudget ? 'yes' : 'no'} |`);
  }
  return `${lines.join('\n')}\n`;
}

function gh(path) {
  return JSON.parse(execFileSync('gh', ['api', path], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 }));
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); } catch { return false; }
}

if (isMain()) {
  const count = Number(process.argv[2] ?? 40);
  if (!Number.isSafeInteger(count) || count < 1 || count > 100) {
    console.error('count must be an integer within 1...100');
    process.exit(64);
  }
  const repo = 'repos/johnny4young/secreteo';
  const runs = gh(`${repo}/actions/workflows/ci.yml/runs?event=pull_request&status=success&per_page=${count}`).workflow_runs;
  const measured = runs.map(run => measureRun({
    created_at: run.created_at, run_started_at: run.run_started_at,
    jobs: gh(`${repo}/actions/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=50`).jobs,
  }));
  const first = runs.at(-1)?.created_at ?? '-';
  const last = runs[0]?.created_at ?? '-';
  process.stdout.write(`Successful pull request runs of ci.yml, ${first} to ${last}, minutes.\n\n${render(summarize(measured))}`);
}
