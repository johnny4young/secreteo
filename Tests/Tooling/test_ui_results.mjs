import test, { after } from 'node:test';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, linkSync, symlinkSync, copyFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { receipt } from '../../scripts/ui_test_results.mjs';
const roots = [];
after(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }); });
const helper = fileURLToPath(new URL('../../scripts/ui_test_results.mjs', import.meta.url));
const invoke = (args, input = '') => spawnSync(process.execPath, [helper, ...args], { input, encoding: 'utf8' });
const summarize = input => invoke(['summary'], typeof input === 'string' || Buffer.isBuffer(input) ? input : JSON.stringify(input));
function fixture(manifest) {
  const root = mkdtempSync(join(tmpdir(), 'secreteo-ui-results-'));
  roots.push(root);
  const source = join(root, 'source'); const target = join(root, 'target');
  mkdirSync(source); mkdirSync(target);
  writeFileSync(join(source, 'manifest.json'), typeof manifest === 'string' ? manifest : JSON.stringify(manifest));
  writeFileSync(join(source, 'one.png'), 'synthetic-one', { mode: 0o640 });
  writeFileSync(join(source, 'two.png'), 'synthetic-two');
  return { root, source, target };
}
const item = (name = 'pr-á😀_suffix', file = 'one.png') => ({ suggestedHumanReadableName: name, exportedFileName: file });
const exportFiles = f => invoke(['attachments', f.source, f.target]);
test('summary preserves Unicode, colon, order and embedded newline', () => {
  const result = summarize({ testFailures: [{ testName: 'Á😀', failureText: 'first\nsecond' }, { testName: 'B', failureText: '' }] });
  assert.equal(result.status, 0); assert.equal(result.stdout, 'Á😀: first\nsecond\nB: \n'); assert.equal(result.stderr, '');
});
test('missing failures produces no output', () => { assert.equal(summarize({}).stdout, ''); assert.equal(summarize({}).status, 0); });
for (const input of ['{', 'null', '[]', '{"testFailures":null}', '{"testFailures":[{}]}', '{"testFailures":[{"testName":1,"failureText":"a"}]}', '\ufeff{}', Buffer.from([0xff]), '{"testFailures":[{"testName":"\\ud800","failureText":"a"}]}']) {
  test(`summary rejects malformed input ${JSON.stringify(input)}`, () => { const r = summarize(input); assert.equal(r.status, 1); assert.equal(r.stdout, ''); assert.notEqual(r.stderr, ''); });
}
test('summary retains earlier output when a later failure is malformed', () => {
  const r = summarize({ testFailures: [{ testName: 'A', failureText: 'failed' }, {}] });
  assert.equal(r.status, 1); assert.equal(r.stdout, 'A: failed\n');
});
test('exports pr names, first underscore, source mode and skips other attachments', () => {
  const f = fixture([{ attachments: [item(), item('not-pr', 'missing'), {}] }, {}]);
  assert.equal(exportFiles(f).status, 0); assert.deepEqual(readdirSync(f.target), ['pr-á😀.png']);
  assert.equal(readFileSync(join(f.target, 'pr-á😀.png'), 'utf8'), 'synthetic-one');
  assert.equal(statSync(join(f.target, 'pr-á😀.png')).mode & 0o777, 0o640);
});
test('later attachment with the same prefix overwrites earlier bytes', () => {
  const f = fixture([{ attachments: [item('pr-view_a'), item('pr-view_b', 'two.png')] }]);
  assert.equal(exportFiles(f).status, 0); assert.equal(readFileSync(join(f.target, 'pr-view.png'), 'utf8'), 'synthetic-two');
});
for (const manifest of ['{', 'null', '{}', '[null]', '[{"attachments":null}]', '[{"attachments":[{"suggestedHumanReadableName":null}]}]', '[{"attachments":[{"suggestedHumanReadableName":"pr-a"}]}]', '\ufeff[]']) {
  test(`export rejects malformed manifest ${manifest}`, () => { const f = fixture(manifest); const r = exportFiles(f); assert.equal(r.status, 1); assert.equal(r.stdout, ''); assert.notEqual(r.stderr, ''); assert.deepEqual(readdirSync(f.target), []); });
}
test('missing manifest fails', () => { const f = fixture([]); const r = invoke(['attachments', join(f.source, 'absent'), f.target]); assert.equal(r.status, 1); });
test('missing source fails after keeping prior exports', () => { const f = fixture([{ attachments: [item('pr-ok'), item('pr-bad', 'missing')] }]); assert.equal(exportFiles(f).status, 1); assert.deepEqual(readdirSync(f.target), ['pr-ok.png']); });
test('missing destination directory fails without creating it', () => { const f = fixture([{ attachments: [item()] }]); assert.equal(invoke(['attachments', f.source, join(f.target, 'absent')]).status, 1); assert.deepEqual(readdirSync(f.target), []); });
test('attachment name cannot leave the target folder', () => { const f = fixture([{ attachments: [item('pr-/../../escaped_x')] }]); const shots = join(f.target, 'shots'); mkdirSync(shots); assert.equal(invoke(['attachments', f.source, shots]).status, 1); assert.deepEqual(readdirSync(f.target), ['shots']); });
test('same-file hard link fails without truncation', () => { const f = fixture([{ attachments: [item('pr-same')] }]); linkSync(join(f.source, 'one.png'), join(f.target, 'pr-same.png')); assert.equal(exportFiles(f).status, 1); assert.equal(readFileSync(join(f.source, 'one.png'), 'utf8'), 'synthetic-one'); });
test('existing destination directory receives source basename like shutil.copy', () => { const f = fixture([{ attachments: [item('pr-dir')] }]); mkdirSync(join(f.target, 'pr-dir.png')); assert.equal(exportFiles(f).status, 0); assert.equal(readFileSync(join(f.target, 'pr-dir.png/one.png'), 'utf8'), 'synthetic-one'); });
for (const args of [[], ['unknown'], ['summary', 'extra'], ['attachments'], ['attachments', 'a'], ['receipt', 'a', 'b'], ['receipt', 'a', 'b', '0', 'smoke']]) test(`invalid CLI ${JSON.stringify(args)} fails`, () => assert.equal(invoke(args).status, 1));
const consumer = readFileSync(new URL('../../scripts/run-ui-tests.sh', import.meta.url), 'utf8');
const summaryBlock = consumer.slice(consumer.indexOf('if [[ "$status" -ne 0 ]]'), consumer.indexOf('\nreceipt_status='));
const exportBlock = consumer.slice(consumer.indexOf('if xcrun xcresulttool export'), consumer.indexOf('\nexit "$status"'));
function bashBlock(block, f, status) {
  return spawnSync('/bin/bash', ['-c', `set -euo pipefail\nstatus="$1"; receipt_status=0; results=unused; scratch="$2"; screenshots="$3"\nxcrun() { printf '{'; }\n${block}\nexit "$status"`, 'fixture', String(status), f.source, f.target], { cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8' });
}
test('isolated summary error preserves test exit 65', () => { const r = bashBlock(summaryBlock, fixture([]), 65); assert.equal(r.status, 65); assert.notEqual(r.stderr, ''); });
test('isolated export error is fatal even after successful tests', () => { const r = bashBlock(exportBlock, fixture('{'), 0); assert.equal(r.status, 1); assert.notEqual(r.stderr, ''); });
test('isolated successful export preserves test failure 65', () => { assert.equal(bashBlock(exportBlock, fixture([]), 65).status, 65); });

test('strict JSON rejects nonstandard NaN rather than accepting Python extension', () => { assert.equal(summarize('{"unused":NaN}').status, 1); });
test('export rejects malformed UTF-8 manifest', () => { const f = fixture([]); writeFileSync(join(f.source, 'manifest.json'), Buffer.from([0xff])); assert.equal(exportFiles(f).status, 1); assert.deepEqual(readdirSync(f.target), []); });
test('import does not run the CLI', () => { const r = spawnSync(process.execPath, ['--input-type=module', '-'], { input: 'await import(' + JSON.stringify(new URL('../../scripts/ui_test_results.mjs', import.meta.url).href) + ');', encoding: 'utf8' }); assert.equal(r.status, 0); assert.equal(r.stdout, ''); assert.equal(r.stderr, ''); });

const successfulSummary = () => ({ result: 'Passed', totalTestCount: 1, passedTests: 1,
  failedTests: 0, skippedTests: 0, expectedFailures: 0, testFailures: [] });
const successfulTests = () => ({ testPlanConfigurations: [], devices: [], testNodes: [
  { nodeType: 'Test Case', name: 'testOne()', nodeIdentifier: 'Menu/testOne()', result: 'Passed', durationInSeconds: 2.5 },
] });
function captured(overrides = {}) {
  const calls = [];
  const run = (command, args, options) => {
    calls.push({ command, args, options });
    if (command === 'git') return Buffer.from('a'.repeat(40) + '\n');
    assert.equal(command, 'xcrun');
    const kind = args[3];
    assert.deepEqual(args.slice(0, 4), ['xcresulttool', 'get', 'test-results', kind]);
    assert.deepEqual(args.slice(4), ['--schema-version', '0.1.0', '--path', 'results with spaces', '--compact']);
    assert.ok(options.timeout > 0 && options.maxBuffer > 0);
    if (Object.hasOwn(overrides, kind)) {
      if (overrides[kind] instanceof Error) throw overrides[kind];
      return overrides[kind];
    }
    return Buffer.from(JSON.stringify(kind === 'summary' ? successfulSummary() : successfulTests()));
  };
  return { calls, run };
}
test('receipt retains raw counts, test tree, selection and explicit source identity', () => {
  const f = fixture([]), runner = captured();
  const env = { GITHUB_RUN_ID: '7', GITHUB_RUN_ATTEMPT: '2', GITHUB_EVENT_NAME: 'pull_request',
    GITHUB_SHA: 'b'.repeat(40), GIT_DIR: '/unowned', SECRET_SENTINEL: 'not-for-the-receipt' };
  const selection = ['-only-testing:SecreteoUITests/Menu/testOne'];
  assert.equal(receipt('results with spaces', f.target, '0', 'smoke', '', selection, runner.run, env), 0);
  const raw = readFileSync(join(f.target, 'test-results.json'), 'utf8'), document = JSON.parse(raw);
  assert.equal(document.captureComplete, true);
  assert.equal(document.checkoutSHA, 'a'.repeat(40));
  assert.deepEqual(document.ci, { runID: '7', attempt: '2', event: 'pull_request', githubSHA: 'b'.repeat(40) });
  assert.deepEqual(document.selection, selection);
  assert.deepEqual(document.reports, { summary: successfulSummary(), tests: successfulTests() });
  assert.doesNotMatch(raw, /not-for-the-receipt|unowned/);
  assert.equal(runner.calls[0].options.env.GIT_DIR, undefined);
  assert.equal(statSync(join(f.target, 'test-results.json')).mode & 0o777, 0o600);
});
test('receipt uses the schema available in the pinned CI Xcode', () => {
  const f = fixture([]);
  const run = (command, args) => {
    if (command === 'git') return Buffer.from('a'.repeat(40));
    if (args[args.indexOf('--schema-version') + 1] !== '0.1.0') throw new Error('Unsupported schema version');
    return Buffer.from(JSON.stringify(args[3] === 'summary' ? successfulSummary() : successfulTests()));
  };
  assert.equal(receipt('unused', f.target, '0', 'smoke', '', [], run, {}), 0);
  assert.equal(JSON.parse(readFileSync(join(f.target, 'test-results.json'))).xcresultSchemaVersion, '0.1.0');
});
test('a complete capture retains failed, skipped and expected-failure outcomes without declaring tests passed', () => {
  const summary = { ...successfulSummary(), result: 'Failed', totalTestCount: 4,
    failedTests: 1, skippedTests: 1, expectedFailures: 1, testFailures: [{ testName: 'testBad', failureText: 'synthetic failure' }] };
  const f = fixture([]), runner = captured({ summary: Buffer.from(JSON.stringify(summary)) });
  assert.equal(receipt('results with spaces', f.target, '65', 'full', '1/2', [], runner.run, {}), 0);
  const saved = JSON.parse(readFileSync(join(f.target, 'test-results.json')));
  assert.equal(saved.testExitCode, 65);
  assert.equal(saved.shard, '1/2');
  assert.deepEqual(saved.reports.summary, summary);
});
for (const [name, value] of [
  ['command failure', new Error('PRIVATE-SENTINEL')], ['invalid JSON', Buffer.from('{')],
  ['invalid UTF-8', Buffer.from([255])], ['empty object', Buffer.from('{}')],
  ['negative count', Buffer.from(JSON.stringify({ ...successfulSummary(), passedTests: -1 }))],
  ['malformed failure', Buffer.from(JSON.stringify({ ...successfulSummary(), testFailures: [{ testName: 'testBad' }] }))],
]) {
  test(`receipt preserves partial evidence and fails for ${name}`, () => {
    const f = fixture([]), runner = captured({ summary: value });
    assert.equal(receipt('results with spaces', f.target, '0', 'smoke', '', [], runner.run, {}), 1);
    const raw = readFileSync(join(f.target, 'test-results.json'), 'utf8'), saved = JSON.parse(raw);
    assert.equal(saved.captureComplete, false);
    assert.deepEqual(saved.errors, ['summary']);
    assert.deepEqual(saved.reports.tests, successfulTests());
    assert.doesNotMatch(raw, /PRIVATE-SENTINEL/);
  });
}
test('invalid checkout identity cannot produce a complete receipt', () => {
  const f = fixture([]), runner = captured();
  const run = (command, ...args) => command === 'git' ? Buffer.from('invalid\n') : runner.run(command, ...args);
  assert.equal(receipt('results with spaces', f.target, '0', 'full', '', [], run, {}), 1);
  assert.deepEqual(JSON.parse(readFileSync(join(f.target, 'test-results.json'))).errors, ['checkout']);
});
test('malformed test tree cannot masquerade as complete results', () => {
  const f = fixture([]), runner = captured({ tests: Buffer.from('{"testNodes":null,"devices":[],"testPlanConfigurations":[]}') });
  assert.equal(receipt('results with spaces', f.target, '0', 'full', '', [], runner.run, {}), 1);
  const saved = JSON.parse(readFileSync(join(f.target, 'test-results.json')));
  assert.deepEqual(saved.errors, ['tests']);
  assert.deepEqual(saved.reports.summary, successfulSummary());
});
for (const [name, nodes] of [
  ['null node', [null]], ['missing name', [{ nodeType: 'Test Case' }]],
  ['unknown node type', [{ nodeType: 'invented', name: 'test' }]],
  ['invalid children', [{ nodeType: 'Test Suite', name: 'Suite', children: {} }]],
  ['nested null node', [{ nodeType: 'Test Suite', name: 'Suite', children: [null] }]],
  ['invalid outcome', [{ nodeType: 'Test Case', name: 'test', result: 'invented' }]],
  ['invalid identifier', [{ nodeType: 'Test Case', name: 'test', nodeIdentifier: 42 }]],
]) {
  test(`malformed tree with ${name} stays partial`, () => {
    const f = fixture([]), runner = captured({ tests: Buffer.from(JSON.stringify({ ...successfulTests(), testNodes: nodes })) });
    assert.equal(receipt('results with spaces', f.target, '0', 'full', '', [], runner.run, {}), 1);
    const saved = JSON.parse(readFileSync(join(f.target, 'test-results.json')));
    assert.equal(saved.captureComplete, false);
    assert.deepEqual(saved.errors, ['tests']);
    assert.deepEqual(saved.reports.summary, successfulSummary());
  });
}
test('valid nested trees and empty exports retain their original structure', () => {
  for (const testNodes of [[], [{ nodeType: 'Test Suite', name: 'Suite', children: successfulTests().testNodes }]]) {
    const f = fixture([]), expected = { ...successfulTests(), testNodes };
    const runner = captured({ tests: Buffer.from(JSON.stringify(expected)) });
    assert.equal(receipt('results with spaces', f.target, '0', 'full', '', [], runner.run, {}), 0);
    assert.deepEqual(JSON.parse(readFileSync(join(f.target, 'test-results.json'))).reports.tests, expected);
  }
});
test('receipt never overwrites an earlier result', () => {
  const f = fixture([]), runner = captured(), path = join(f.target, 'test-results.json');
  writeFileSync(path, 'keep');
  assert.throws(() => receipt('results with spaces', f.target, '0', 'smoke', '', [], runner.run, {}), /EEXIST/);
  assert.equal(readFileSync(path, 'utf8'), 'keep');
});
test('invalid receipt arguments never invoke tools or write files', () => {
  const f = fixture([]), runner = captured();
  for (const status of ['-1', '256', '1x', '00', '']) {
    assert.throws(() => receipt('unused', f.target, status, 'smoke', '', [], runner.run, {}));
  }
  assert.throws(() => receipt('unused', f.target, '0', 'unknown', '', [], runner.run, {}));
  assert.equal(runner.calls.length, 0);
  assert.deepEqual(readdirSync(f.target), []);
});

function launchDouble(status, badReport = false) {
  const f = fixture([]), bin = join(f.root, 'bin'), scripts = join(f.root, 'scripts');
  mkdirSync(bin); mkdirSync(scripts); mkdirSync(join(f.root, 'Tests/Plans'), { recursive: true });
  writeFileSync(join(scripts, 'run-ui-tests.sh'), consumer);
  copyFileSync(helper, join(scripts, 'ui_test_results.mjs'));
  writeFileSync(join(scripts, 'fetch-sparkle.sh'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  writeFileSync(join(f.root, 'Tests/Plans/Smoke.txt'), 'SecreteoUITests/Menu/testOne\n');
  symlinkSync(process.execPath, join(bin, 'node'));
  writeFileSync(join(bin, 'xcodegen'), '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  writeFileSync(join(bin, 'git'), `#!/bin/sh\nprintf '%s\\n' '${'a'.repeat(40)}'\n`, { mode: 0o755 });
  writeFileSync(join(bin, 'xcodebuild'), '#!/bin/sh\ncase " $* " in *" test-without-building "*) exit "$UI_TEST_EXIT";; esac\nexit 0\n', { mode: 0o755 });
  const summaryJSON = badReport ? '{' : JSON.stringify(successfulSummary());
  writeFileSync(join(bin, 'xcrun'), `#!/bin/sh\ncase "$4" in\nsummary) printf '%s' '${summaryJSON}';;\ntests) printf '%s' '${JSON.stringify(successfulTests())}';;\n*) exit 1;;\nesac\n`, { mode: 0o755 });
  const result = spawnSync('/bin/bash', [join(scripts, 'run-ui-tests.sh'), 'smoke', f.target], {
    cwd: f.root, env: { PATH: `${bin}:/usr/bin:/bin`, TMPDIR: f.root, UI_TEST_EXIT: String(status),
      GITHUB_RUN_ID: '7', GITHUB_RUN_ATTEMPT: '2' }, encoding: 'utf8',
  });
  return { result, path: join(f.target, 'test-results.json') };
}
for (const status of [0, 65]) {
  test(`launcher retains a receipt after ${status === 0 ? 'a successful' : 'a failed'} run`, () => {
    const { result, path } = launchDouble(status);
    assert.equal(result.status, status, result.stderr);
    const saved = JSON.parse(readFileSync(path));
    assert.equal(saved.captureComplete, true);
    assert.equal(saved.testExitCode, status);
    assert.deepEqual(saved.selection, ['-only-testing:SecreteoUITests/Menu/testOne']);
  });
  test(`launcher export failure preserves the test outcome ${status}`, () => {
    const { result, path } = launchDouble(status, true);
    assert.equal(result.status, status || 1, result.stderr);
    assert.equal(JSON.parse(readFileSync(path)).captureComplete, false);
  });
}
