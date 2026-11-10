#!/usr/bin/env node
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const ALWAYS = ['hygiene', 'legacy-tooling', 'lint', 'changes'];
const SCOPED = [['code', ['unit', 'ui-smoke']], ['delivery', ['signed-handoff']], ['release', ['release-dryrun']]];

export function failures(needs) {
  const problems = [];
  const result = job => needs?.[job]?.result;
  const describe = value => value == null ? 'None' : String(value);
  for (const job of ALWAYS) if (result(job) !== 'success') problems.push(`${job}: ${describe(result(job))}`);
  const scope = needs?.changes?.outputs;
  if (scope !== undefined && (scope === null || typeof scope !== 'object' || Array.isArray(scope))) {
    return [...problems, 'changes: invalid outputs'];
  }
  for (const [flag, jobs] of SCOPED) {
    for (const job of jobs) {
      const status = result(job);
      if (status !== 'success' && !(status === 'skipped' && scope?.[flag] === 'false')) {
        problems.push(`${job}: ${describe(status)}`);
      }
    }
  }
  return problems;
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); }
  catch { return false; }
}

if (isMain()) {
  try {
    const problems = failures(JSON.parse(process.argv[2]));
    for (const problem of problems) {
      const escaped = problem.replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
      console.log(`::error::${escaped}`);
    }
    if (problems.length) process.exitCode = 1;
  } catch {
    console.error('::error::Invalid needs JSON.');
    process.exitCode = 1;
  }
}
