#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const WORKFLOW = '.github/workflows/ci.yml';
const isSHA = value => typeof value === 'string' && value.length === 40 && /^[0-9a-f]{40}$/.test(value);
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const positiveInteger = value => Number.isSafeInteger(value) && value > 0;

export function ghApi(path) {
  const bytes = execFileSync('gh', ['api', path], {
    stdio: ['ignore', 'pipe', 'pipe'], timeout: 15_000, maxBuffer: 4 * 1024 * 1024,
  });
  return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes));
}

function completePage(value, key) {
  return record(value) && Array.isArray(value[key]) && value[key].every(record)
    && value[key].length <= 100 && value.total_count === value[key].length ? value[key] : null;
}

function newestRun(payload, head) {
  const listed = completePage(payload, 'workflow_runs');
  if (!listed || listed.some(run => typeof run.path !== 'string' || !run.path || !positiveInteger(run.id))) return null;
  const runs = listed.filter(run => run.path === WORKFLOW);
  if (!runs.length) return null;
  const newest = runs.reduce((left, right) => left.id > right.id ? left : right);
  if (runs.filter(run => run.id === newest.id).length !== 1) return null;
  if (newest.head_sha !== head || newest.event !== 'pull_request' || newest.status !== 'completed'
      || newest.conclusion !== 'success' || !positiveInteger(newest.run_attempt)
      || typeof newest.html_url !== 'string' || !newest.html_url || /[\x00-\x20\x7f]/.test(newest.html_url)) return null;
  return newest;
}

export function proof(api, repo, sha) {
  if (typeof repo !== 'string' || repo.trim() !== repo || !/^[A-Za-z0-9_-]+\/[A-Za-z0-9_.-]+$/.test(repo)
      || ['.', '..'].includes(repo.split('/')[1]) || !isSHA(sha)) return null;
  const associated = api(`repos/${repo}/commits/${sha}/pulls?per_page=100`);
  // No total is supplied for this endpoint. A full page may hide another matching merge.
  if (!Array.isArray(associated) || associated.length >= 100 || !associated.every(record)) return null;
  const pulls = associated.filter(pull => pull.merge_commit_sha === sha && typeof pull.merged_at === 'string'
    && Number.isFinite(Date.parse(pull.merged_at)));
  if (pulls.length !== 1 || !record(pulls[0].head) || !isSHA(pulls[0].head.sha)) return null;
  const head = pulls[0].head.sha;
  const mergedTree = api(`repos/${repo}/git/commits/${sha}`)?.tree?.sha;
  const headTree = api(`repos/${repo}/git/commits/${head}`)?.tree?.sha;
  if (!isSHA(mergedTree) || mergedTree !== headTree) return null;
  const runsPath = `repos/${repo}/actions/runs?head_sha=${head}&event=pull_request&per_page=100`;
  const newest = newestRun(api(runsPath), head);
  if (!newest) return null;
  const jobs = completePage(api(
    `repos/${repo}/actions/runs/${newest.id}/attempts/${newest.run_attempt}/jobs?per_page=100`), 'jobs');
  const gates = jobs?.filter(job => job.name === 'gate');
  if (gates?.length !== 1 || gates[0].conclusion !== 'success' || gates[0].status !== 'completed'
      || gates[0].run_id !== newest.id || gates[0].run_attempt !== newest.run_attempt || gates[0].head_sha !== head) return null;
  // A new run or rerun while reading jobs invalidates the earlier proof.
  const final = newestRun(api(runsPath), head);
  if (!final || final.id !== newest.id || final.run_attempt !== newest.run_attempt
      || final.html_url !== newest.html_url) return null;
  return newest.html_url;
}

export function main(api, repo, sha, output = console) {
  try {
    const url = proof(api, repo, sha);
    if (url === null) {
      output.log('No merged pull request proved this tree, running every job.');
      return 1;
    }
    output.log(`This tree passed gate in ${url}`);
    return 0;
  } catch {
    output.error('Could not prove reuse, running every job.');
    return 1;
  }
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); }
  catch { return false; }
}

if (isMain()) {
  process.exitCode = process.argv.length === 4 ? main(ghApi, process.argv[2], process.argv[3]) : 1;
}
