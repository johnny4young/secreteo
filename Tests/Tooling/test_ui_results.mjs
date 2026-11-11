import test, { after } from 'node:test';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, statSync, linkSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
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
for (const args of [[], ['unknown'], ['summary', 'extra'], ['attachments'], ['attachments', 'a']]) test(`invalid CLI ${JSON.stringify(args)} fails`, () => assert.equal(invoke(args).status, 1));
const consumer = readFileSync(new URL('../../scripts/run-ui-tests.sh', import.meta.url), 'utf8');
const summaryBlock = consumer.slice(consumer.indexOf('if [[ "$status" -ne 0 ]]'), consumer.indexOf('\nscratch='));
const exportBlock = consumer.slice(consumer.indexOf('if xcrun xcresulttool export'), consumer.indexOf('\nexit "$status"'));
function bashBlock(block, f, status) {
  return spawnSync('/bin/bash', ['-c', `set -euo pipefail\nstatus="$1"; results=unused; scratch="$2"; screenshots="$3"\nxcrun() { printf '{'; }\n${block}\nexit "$status"`, 'fixture', String(status), f.source, f.target], { cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8' });
}
test('isolated summary error preserves test exit 65', () => { const r = bashBlock(summaryBlock, fixture([]), 65); assert.equal(r.status, 65); assert.notEqual(r.stderr, ''); });
test('isolated export error is fatal even after successful tests', () => { const r = bashBlock(exportBlock, fixture('{'), 0); assert.equal(r.status, 1); assert.notEqual(r.stderr, ''); });
test('isolated successful export preserves test failure 65', () => { assert.equal(bashBlock(exportBlock, fixture([]), 65).status, 65); });

test('strict JSON rejects nonstandard NaN rather than accepting Python extension', () => { assert.equal(summarize('{"unused":NaN}').status, 1); });
test('export rejects malformed UTF-8 manifest', () => { const f = fixture([]); writeFileSync(join(f.source, 'manifest.json'), Buffer.from([0xff])); assert.equal(exportFiles(f).status, 1); assert.deepEqual(readdirSync(f.target), []); });
test('import does not run the CLI', () => { const r = spawnSync(process.execPath, ['--input-type=module', '-'], { input: 'await import(' + JSON.stringify(new URL('../../scripts/ui_test_results.mjs', import.meta.url).href) + ');', encoding: 'utf8' }); assert.equal(r.status, 0); assert.equal(r.stdout, ''); assert.equal(r.stderr, ''); });
