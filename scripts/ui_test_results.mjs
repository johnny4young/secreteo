import { readFileSync, writeFileSync, copyFileSync, chmodSync, statSync, realpathSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { resolve, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

function json(input) {
  return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(input));
}
function object(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Expected a JSON object');
  return value;
}
function list(value) {
  if (!Array.isArray(value)) throw new Error('Expected a JSON array');
  return value;
}
function string(value) {
  if (typeof value !== 'string') throw new Error('Expected a JSON string');
  // Python UTF-8 output and filesystem paths reject unpaired surrogates.
  if (!value.isWellFormed()) throw new Error('Invalid Unicode surrogate');
  return value;
}
export function summary(input, write) {
  const document = object(json(input));
  for (const failure of list(document.testFailures === undefined ? [] : document.testFailures)) {
    object(failure);
    write(`${string(failure.testName)}: ${string(failure.failureText)}\n`);
  }
}
export function attachments(source, target) {
  const manifest = list(json(readFileSync(resolve(source, 'manifest.json'))));
  for (const test of manifest) {
    object(test);
    for (const attachment of list(test.attachments === undefined ? [] : test.attachments)) {
      object(attachment);
      const name = string(attachment.suggestedHumanReadableName === undefined ? '' : attachment.suggestedHumanReadableName);
      if (!name.startsWith('pr-')) continue;
      const from = resolve(source, string(attachment.exportedFileName));
      let to = resolve(target, `${name.split('_')[0]}.png`);
      let destination;
      try { destination = statSync(to); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (destination?.isDirectory()) {
        to = join(to, basename(from));
        try { destination = statSync(to); } catch (error) { if (error.code !== 'ENOENT') throw error; destination = undefined; }
      }
      const original = statSync(from);
      if (!original.isFile()) throw new Error('Attachment must be a regular file');
      if (destination && original.dev === destination.dev && original.ino === destination.ino) throw new Error('Source and destination are the same file');
      copyFileSync(from, to);
      chmodSync(to, original.mode & 0o7777);
    }
  }
}

const testResults = new Set(['Passed', 'Failed', 'Skipped', 'Expected Failure', 'unknown']);
const nodeTypes = new Set(['Test Plan', 'Unit test bundle', 'UI test bundle', 'Test Suite', 'Test Case',
  'Device', 'Test Plan Configuration', 'Arguments', 'Repetition', 'Test Case Run', 'Failure Message',
  'Source Code Reference', 'Attachment', 'Expression', 'Test Value', 'Runtime Warning']);
function testTree(nodes) {
  for (const node of list(nodes)) {
    object(node);
    string(node.name);
    if (!nodeTypes.has(node.nodeType)) throw new Error('Invalid test node type');
    if (node.result !== undefined && !testResults.has(node.result)) throw new Error('Invalid test result');
    if (node.nodeIdentifier !== undefined) string(node.nodeIdentifier);
    if (node.children !== undefined) testTree(node.children);
  }
}
export function receipt(results, target, status, plan, shard, selection, run = execFileSync, env = process.env) {
  if (!/^(?:0|[1-9][0-9]{0,2})$/.test(status) || Number(status) > 255
      || !['smoke', 'full'].includes(plan) || typeof shard !== 'string'
      || !Array.isArray(selection) || selection.some(value => typeof value !== 'string')) {
    throw new Error('Invalid UI receipt arguments');
  }
  const document = { schemaVersion: 1, xcresultSchemaVersion: '0.1.0', plan, shard: shard || null, selection,
    testExitCode: Number(status), checkoutSHA: null,
    ci: { runID: env.GITHUB_RUN_ID ?? null, attempt: env.GITHUB_RUN_ATTEMPT ?? null,
      event: env.GITHUB_EVENT_NAME ?? null, githubSHA: env.GITHUB_SHA ?? null },
    reports: {}, errors: [] };
  try {
    const bytes = run('git', ['rev-parse', 'HEAD'], {
      cwd: fileURLToPath(new URL('../', import.meta.url)),
      env: Object.fromEntries(Object.entries(env).filter(([name]) => !name.startsWith('GIT_'))),
      stdio: ['ignore', 'pipe', 'pipe'], timeout: 10_000, maxBuffer: 4096,
    });
    const sha = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes).trim();
    if (!/^[0-9a-f]{40}$/.test(sha)) throw new Error('Invalid checkout SHA');
    document.checkoutSHA = sha;
  } catch { document.errors.push('checkout'); }
  for (const kind of ['summary', 'tests']) {
    try {
      const report = object(json(run('xcrun', [
        'xcresulttool', 'get', 'test-results', kind, '--schema-version', '0.1.0', '--path', results, '--compact',
      ], { stdio: ['ignore', 'pipe', 'pipe'], timeout: 30_000, maxBuffer: 4 * 1024 * 1024 })));
      if (kind === 'summary') {
        for (const key of ['totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures']) {
          if (!Number.isSafeInteger(report[key]) || report[key] < 0) throw new Error('Invalid result count');
        }
        if (!testResults.has(report.result)) throw new Error('Invalid test result');
        list(report.testFailures);
      } else {
        for (const key of ['testNodes', 'devices', 'testPlanConfigurations']) list(report[key]);
        testTree(report.testNodes);
      }
      document.reports[kind] = report;
    } catch { document.errors.push(kind); }
  }
  document.captureComplete = document.errors.length === 0;
  writeFileSync(join(target, 'test-results.json'), `${JSON.stringify(document, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
  return document.captureComplete ? 0 : 1;
}
function isMain() {
  try { return process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url); }
  catch { return false; }
}
if (isMain()) {
  try {
    const [command, source, target, ...extra] = process.argv.slice(2);
    if (command === 'summary' && source === undefined) summary(readFileSync(0), line => process.stdout.write(line));
    else if (command === 'attachments' && source !== undefined && target !== undefined && !extra.length) attachments(source, target);
    else if (command === 'receipt' && source !== undefined && target !== undefined && extra.length >= 3) {
      process.exitCode = receipt(source, target, extra[0], extra[1], extra[2], extra.slice(3));
      if (process.exitCode) console.error('Could not capture complete UI test results.');
    } else throw new Error('Usage: node scripts/ui_test_results.mjs summary | attachments SOURCE TARGET | receipt RESULTS TARGET STATUS PLAN SHARD [SELECTION...]');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
