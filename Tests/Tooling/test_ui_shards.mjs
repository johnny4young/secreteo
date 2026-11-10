import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { testClasses, shards } from '../../scripts/ui_test_shards.mjs';

function fixture(t, files = {}) {
  const root = mkdtempSync(join(tmpdir(), 'secreteo-shards-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(join(root, 'scripts'));
  mkdirSync(join(root, 'Tests/SecreteoUITests'), { recursive: true });
  copyFileSync(new URL('../../scripts/ui_test_shards.mjs', import.meta.url), join(root, 'scripts/ui_test_shards.mjs'));
  for (const [name, contents] of Object.entries(files)) writeFileSync(join(root, 'Tests/SecreteoUITests', name), contents);
  return root;
}
const source = (name, methods = '    func testOne() {}\n') => `final class ${name}: XCTestCase {\n${methods}}\n`;
const invoke = (root, args) => spawnSync(process.execPath, [join(root, 'scripts/ui_test_shards.mjs'), ...args], { encoding: 'utf8' });

test('balances descending weights, alphabetic ties, and earliest-bin ties', () => {
  assert.deepEqual(shards(new Map([['D', 1], ['B', 3], ['A', 3], ['C', 2]]), 2), [['A', 'C'], ['B', 'D']]);
});
test('each class appears once and imbalance stays within the largest class', () => {
  const found = new Map([['A', 9], ['B', 7], ['C', 5], ['D', 3], ['E', 1]]);
  const result = shards(found, 2);
  assert.deepEqual(result.flat().sort(), ['A', 'B', 'C', 'D', 'E']);
  const sizes = result.map(bin => bin.reduce((sum, name) => sum + found.get(name), 0));
  assert.ok(Math.max(...sizes) - Math.min(...sizes) <= 9);
});
test('more shards than classes preserves empty bins', () => {
  assert.deepEqual(shards(new Map([['A', 1]]), 3), [['A'], [], []]);
});
test('uses Unicode code point order, not locale or UTF-16 order', () => {
  assert.deepEqual(shards(new Map([['𐐀', 1], ['Ｚ', 1], ['Á', 1], ['Z', 1]]), 1), [['Z', 'Á', 'Ｚ', '𐐀']]);
});
test('discovers direct Swift files and ignores a base without tests', t => {
  const root = fixture(t, { 'Base.swift': 'class Base: XCTestCase {}\n', 'Menu.swift': source('Menu', '    func testOpens() {}\n    func testCloses() {}\n'), 'Ignored.txt': source('Ignored') });
  assert.deepEqual([...testClasses(join(root, 'Tests/SecreteoUITests'))], [['Menu', 2]]);
});
test('duplicate class names keep the last sorted file count like the original', t => {
  const root = fixture(t, { 'Z.swift': source('Same'), 'A.swift': source('Same', ' func testOne() {}\n func testTwo() {}\n') });
  assert.deepEqual([...testClasses(join(root, 'Tests/SecreteoUITests'))], [['Same', 1]]);
});
test('Unicode names, CR line endings and Python whitespace are recognized', t => {
  const root = fixture(t, { 'Unicode.swift': 'class Á²: XCTestCase {\r\u0085func testÑ() {}\r}\r' });
  assert.deepEqual([...testClasses(join(root, 'Tests/SecreteoUITests'))], [['Á²', 1]]);
});
test('multiple classes fail without partial stdout', t => {
  const result = invoke(fixture(t, { 'Both.swift': source('A') + source('B') }), ['1', '2']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, 'Both.swift: keep one test class per file to shard it\n');
});
test('test methods with no recognized class fail', t => {
  const result = invoke(fixture(t, { 'NoClass.swift': '    func testA() {}\n' }), ['1', '1']);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /keep one test class per file/);
});
test('invalid UTF-8 fails rather than silently selecting nothing', t => {
  const result = invoke(fixture(t, { 'Bad.swift': Buffer.from([0xff]) }), ['1', '1']);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
});
test('CLI prints exact sorted lines and final newline', t => {
  const result = invoke(fixture(t, { 'Z.swift': source('Z'), 'A.swift': source('A') }), ['1', '1']);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'A\nZ\n');
  assert.equal(result.stderr, '');
});
test('empty shard prints one newline, preserving consumer empty-selection guard', t => {
  const result = invoke(fixture(t, { 'A.swift': source('A') }), ['2', '2']);
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '\n');
});
for (const args of [[], ['1'], ['0', '2'], ['3', '2'], ['1', '0'], ['-1', '2'], ['1.5', '2'], ['NaN', '2'], ['1', '2junk']]) {
  test(`invalid arguments ${JSON.stringify(args)} fail closed`, t => {
    const result = invoke(fixture(t), args);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '');
    assert.notEqual(result.stderr, '');
  });
}

// Only extract the selection block; never execute the build/download/export harness.
import { readFileSync } from 'node:fs';
const originalConsumer = readFileSync(new URL('../../scripts/run-ui-tests.sh', import.meta.url), 'utf8');
const start = originalConsumer.indexOf('selection=()\n');
const end = originalConsumer.indexOf('\ncommon=(');
assert.ok(start >= 0 && end > start);
const selectionBlock = originalConsumer.slice(start, end);
function consume(root, shard) {
  return spawnSync('/bin/bash', ['-c', `set -euo pipefail\nplan=full\nshard="$1"\n${selectionBlock}\nprintf '%s\\n' "\${selection[@]}"`, 'harness', shard], { cwd: root, encoding: 'utf8' });
}
test('isolated Bash consumer produces only-testing arguments from the Node selector', t => {
  const result = consume(fixture(t, { 'A.swift': source('A'), 'B.swift': source('B') }), '1/1');
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '-only-testing:SecreteoUITests/A\n-only-testing:SecreteoUITests/B\n');
});
test('isolated Bash consumer rejects empty selection with existing exit 64', t => {
  const result = consume(fixture(t, { 'A.swift': source('A') }), '2/2');
  assert.equal(result.status, 64);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, 'Shard 2/2 has no test classes.\n');
});
test('isolated Bash consumer propagates selector failure before selection', t => {
  const result = consume(fixture(t, { 'Both.swift': source('A') + source('B') }), '1/2');
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /keep one test class per file/);
});

function consumeSmoke(root, plan) {
  mkdirSync(join(root, 'Tests/Plans'), { recursive: true });
  writeFileSync(join(root, 'Tests/Plans/Smoke.txt'), plan);
  return spawnSync('/bin/bash', ['-c', `set -euo pipefail\nplan=smoke\nshard=''\n${selectionBlock}\nprintf '%s\\n' "\${selection[@]}"`], {
    cwd: root, encoding: 'utf8',
  });
}
for (const ending of ['\n', '']) {
  test(`smoke keeps the last selector with ${ending ? 'a' : 'no'} final newline`, t => {
    const selectors = ['SecreteoUITests/Menu/testOne', 'SecreteoUITests/Menu/testTwo'];
    const result = consumeSmoke(fixture(t), `${selectors[0]}\n\n${selectors[1]}${ending}`);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, selectors.map(value => `-only-testing:${value}\n`).join(''));
  });
}
for (const contents of ['', '\n\n']) {
  test(`an ${contents ? 'all-blank' : 'empty'} smoke plan cannot select the full suite`, t => {
    const result = consumeSmoke(fixture(t), contents);
    assert.equal(result.status, 64);
    assert.equal(result.stdout, '');
    assert.equal(result.stderr, 'Smoke plan has no tests.\n');
  });
}
test('Unicode line separators do not become Python multiline class anchors', t => {
  const root = fixture(t, { 'Separator.swift': 'ignored\u2028class A: XCTestCase {\nfunc testA() {}\n}\n' });
  assert.throws(() => testClasses(join(root, 'Tests/SecreteoUITests')), /keep one test class per file/);
});
test('Unicode line separators do not become Python multiline test anchors', t => {
  const root = fixture(t, { 'Separator.swift': 'class A: XCTestCase {\nignored\u2029func testA() {}\n}\n' });
  assert.deepEqual([...testClasses(join(root, 'Tests/SecreteoUITests'))], []);
});
test('UTF-8 BOM is retained rather than silently recognizing a new class', t => {
  const root = fixture(t, { 'BOM.swift': '\ufeff' + source('A') });
  assert.throws(() => testClasses(join(root, 'Tests/SecreteoUITests')), /keep one test class per file/);
});

import { symlinkSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
test('import from stdin has no CLI side effects or filesystem errors', t => {
  const root = fixture(t);
  const moduleURL = pathToFileURL(join(root, 'scripts/ui_test_shards.mjs')).href;
  const result = spawnSync(process.execPath, ['--input-type=module', '-'], {
    input: `await import(${JSON.stringify(moduleURL)});`, encoding: 'utf8', cwd: root,
  });
  assert.equal(result.status, 0);
  assert.equal(result.stdout, '');
  assert.equal(result.stderr, '');
});
test('symlink invocation still executes the CLI with the module-relative catalog', t => {
  const root = fixture(t, { 'A.swift': source('A') });
  const alias = join(root, 'alias.mjs');
  symlinkSync(join(root, 'scripts/ui_test_shards.mjs'), alias);
  const result = spawnSync(process.execPath, [alias, '1', '1'], { encoding: 'utf8' });
  assert.equal(result.status, 0);
  assert.equal(result.stdout, 'A\n');
  assert.equal(result.stderr, '');
});

// Retain the original acceptance checks against the actual repository catalog.
test('the current UI catalog is exhaustive, disjoint and balanced', () => {
  const found = testClasses();
  assert.ok(found.size > 0);
  const halves = shards(found, 2);
  assert.deepEqual(halves.flat().sort(), [...found.keys()].sort());
  assert.equal(new Set(halves.flat()).size, found.size);
  const sizes = halves.map(half => half.reduce((sum, name) => sum + found.get(name), 0));
  assert.ok(Math.max(...sizes) - Math.min(...sizes) <= Math.max(...found.values()));
});
