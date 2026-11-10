import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { inventory, qualify } from '../../scripts/ui_test_inventory.mjs';
import { testInventory, testClasses } from '../../scripts/ui_test_shards.mjs';

const found = () => new Map([['A', ['testOne', 'testTwo']], ['B', ['testThree']]]);
const selector = '-only-testing:SecreteoUITests/A/testOne';
const expected = () => ({ schemaVersion: 1, plan: 'smoke', shard: null,
  selection: [selector], expectedTests: ['A/testOne()'] });
const receipt = () => ({ schemaVersion: 1, xcresultSchemaVersion: '0.1.0', captureComplete: true, errors: [],
  plan: 'smoke', shard: null, selection: [selector], testExitCode: 0, reports: {
    summary: { result: 'Passed', totalTestCount: 1, passedTests: 1, failedTests: 0, skippedTests: 0,
      expectedFailures: 0, testFailures: [] },
    tests: { testNodes: [{ nodeType: 'Test Case', name: 'testOne()', nodeIdentifier: 'A/testOne()', result: 'Passed' }] },
  } });

test('smoke inventory preserves its exact selectors with or without final newline', () => {
  assert.deepEqual(inventory('smoke', '', [selector], found(), 'SecreteoUITests/A/testOne\n'), expected());
  assert.deepEqual(inventory('smoke', '', [selector], found(), 'SecreteoUITests/A/testOne'), expected());
});
test('full inventory matches the existing shard assignment and unsharded catalog', () => {
  assert.deepEqual(inventory('full', '1/2', ['-only-testing:SecreteoUITests/A'], found(), '').expectedTests,
    ['A/testOne()', 'A/testTwo()']);
  assert.deepEqual(inventory('full', '2/2', ['-only-testing:SecreteoUITests/B'], found(), '').expectedTests,
    ['B/testThree()']);
  assert.deepEqual(inventory('full', '', [], found(), '').expectedTests,
    ['A/testOne()', 'A/testTwo()', 'B/testThree()']);
});
for (const [name, plan, shard, selection, smoke] of [
  ['empty plan', 'smoke', '', [], ''],
  ['duplicate selectors', 'smoke', '', [selector, selector], 'SecreteoUITests/A/testOne\nSecreteoUITests/A/testOne'],
  ['wrong class for an existing method', 'smoke', '', ['-only-testing:SecreteoUITests/B/testOne'], 'SecreteoUITests/B/testOne'],
  ['wrong target', 'smoke', '', ['-only-testing:Other/A/testOne'], 'Other/A/testOne'],
  ['class-only smoke selector', 'smoke', '', ['-only-testing:SecreteoUITests/A'], 'SecreteoUITests/A'],
  ['partial smoke selection', 'smoke', '', [], 'SecreteoUITests/A/testOne'],
  ['sharded smoke', 'smoke', '1/2', [selector], 'SecreteoUITests/A/testOne'],
  ['unknown plan', 'other', '', [], ''],
  ['wrong shard classes', 'full', '1/2', ['-only-testing:SecreteoUITests/B'], ''],
  ['empty shard', 'full', '3/3', [], ''],
  ['malformed shard', 'full', '1/2/3', [], ''],
  ['invalid shard index', 'full', '0/2', [], ''],
  ['unsharded filter', 'full', '', ['-only-testing:SecreteoUITests/A'], ''],
]) {
  test(`inventory rejects ${name}`, () => assert.throws(() => inventory(plan, shard, selection, found(), smoke)));
}
test('smoke cannot grow past its existing ten-case budget', () => {
  const methods = Array.from({ length: 11 }, (_, i) => `test${i}`);
  const entries = methods.map(method => `SecreteoUITests/A/${method}`);
  assert.throws(() => inventory('smoke', '', entries.map(e => `-only-testing:${e}`),
    new Map([['A', methods]]), entries.join('\n')));
});
test('a complete matching receipt qualifies without mutation', () => {
  const document = receipt(), before = structuredClone(document);
  assert.deepEqual(qualify(document, expected()), { schemaVersion: 1, qualified: true, issues: [],
    cases: [{ identifier: 'A/testOne()', result: 'Passed' }] });
  assert.deepEqual(document, before);
});
test('nested Test Case Run records do not count as additional tests', () => {
  const document = receipt();
  document.reports.tests.testNodes[0].children = [
    { nodeType: 'Test Case Run', name: 'Run 1', nodeIdentifier: 'A/testOne()', result: 'Passed' },
  ];
  assert.equal(qualify(document, expected()).qualified, true);
});
for (const [name, mutate] of [
  ['partial capture', r => { r.captureComplete = false; }],
  ['capture errors', r => { r.errors = ['tests']; }],
  ['wrong plan', r => { r.plan = 'full'; }],
  ['wrong shard', r => { r.shard = '1/2'; }],
  ['wrong selection', r => { r.selection = []; }],
  ['wrong schema', r => { r.xcresultSchemaVersion = '0.5.0'; }],
  ['failed process', r => { r.testExitCode = 65; }],
  ['empty tree', r => { r.reports.tests.testNodes = []; }],
  ['missing identifier', r => { delete r.reports.tests.testNodes[0].nodeIdentifier; }],
  ['duplicate case', r => { r.reports.tests.testNodes.push(r.reports.tests.testNodes[0]); }],
  ['extra case', r => { r.reports.tests.testNodes.push({ ...r.reports.tests.testNodes[0], nodeIdentifier: 'B/testThree()' }); }],
  ['wrong case', r => { r.reports.tests.testNodes[0].nodeIdentifier = 'A/testTwo()'; }],
  ['skipped case', r => { r.reports.tests.testNodes[0].result = 'Skipped'; }],
  ['expected failure', r => { r.reports.tests.testNodes[0].result = 'Expected Failure'; }],
  ['unknown outcome', r => { r.reports.tests.testNodes[0].result = 'unknown'; }],
  ['inconsistent count', r => { r.reports.summary.totalTestCount = 2; }],
  ['inconsistent passed count', r => { r.reports.summary.passedTests = 0; }],
  ['skipped summary', r => { r.reports.summary.skippedTests = 1; }],
  ['failed summary', r => { r.reports.summary.failedTests = 1; }],
  ['expected-failure summary', r => { r.reports.summary.expectedFailures = 1; }],
  ['unknown summary', r => { r.reports.summary.result = 'unknown'; }],
  ['failure details', r => { r.reports.summary.testFailures = [{}]; }],
  ['invalid children', r => { r.reports.tests.testNodes[0].children = null; }],
]) {
  test(`qualification rejects ${name}`, () => {
    const document = receipt(); mutate(document);
    assert.equal(qualify(document, expected()).qualified, false);
  });
}
test('invalid and duplicated expected inventories cannot qualify', () => {
  assert.equal(qualify(receipt(), null).qualified, false);
  assert.equal(qualify(receipt(), { ...expected(), expectedTests: [] }).qualified, false);
  assert.equal(qualify(receipt(), { ...expected(), expectedTests: ['A/testOne()', 'A/testOne()'] }).qualified, false);
});

function fixture(t, files = { 'A.swift': 'final class A: XCTestCase {\n func testOne() {}\n}\n' }) {
  const root = mkdtempSync(join(tmpdir(), 'secreteo-ui-inventory-')); t.after(() => rmSync(root, { recursive: true, force: true }));
  for (const path of ['scripts', 'Tests/SecreteoUITests', 'Tests/Plans', 'output']) mkdirSync(join(root, path), { recursive: true });
  for (const name of ['ui_test_inventory.mjs', 'ui_test_shards.mjs']) copyFileSync(new URL(`../../scripts/${name}`, import.meta.url), join(root, 'scripts', name));
  for (const [name, contents] of Object.entries(files)) writeFileSync(join(root, 'Tests/SecreteoUITests', name), contents);
  writeFileSync(join(root, 'Tests/Plans/Smoke.txt'), 'SecreteoUITests/A/testOne\n');
  return root;
}
const invoke = (root, args) => spawnSync(process.execPath, [join(root, 'scripts/ui_test_inventory.mjs'), ...args], { encoding: 'utf8' });
test('CLI retains inventory and qualification alongside the unchanged receipt', t => {
  const root = fixture(t), target = join(root, 'output');
  assert.equal(invoke(root, ['plan', target, 'smoke', '', selector]).status, 0);
  assert.deepEqual(JSON.parse(readFileSync(join(target, 'test-inventory.json'))), expected());
  assert.equal(statSync(join(target, 'test-inventory.json')).mode & 0o777, 0o600);
  const bytes = JSON.stringify(receipt()); writeFileSync(join(target, 'test-results.json'), bytes);
  assert.equal(invoke(root, ['qualify', target]).status, 0);
  assert.equal(JSON.parse(readFileSync(join(target, 'test-validation.json'))).qualified, true);
  assert.equal(readFileSync(join(target, 'test-results.json'), 'utf8'), bytes);
  assert.equal(invoke(root, ['plan', target, 'smoke', '', selector]).status, 1);
  assert.equal(invoke(root, ['qualify', target]).status, 1);
});
test('CLI fails malformed JSON without changing the receipt', t => {
  const root = fixture(t), target = join(root, 'output');
  writeFileSync(join(target, 'test-results.json'), '{'); writeFileSync(join(target, 'test-inventory.json'), JSON.stringify(expected()));
  assert.equal(invoke(root, ['qualify', target]).status, 1);
  assert.equal(readFileSync(join(target, 'test-results.json'), 'utf8'), '{');
});
test('ambiguous declarations fail inventory discovery while legacy shard counts retain their behavior', t => {
  const root = fixture(t, { 'A.swift': 'class Same: XCTestCase {\n func testOne() {}\n}\n',
    'B.swift': 'class Same: XCTestCase {\n func testTwo() {}\n}\n' });
  assert.throws(() => testInventory(join(root, 'Tests/SecreteoUITests')), /Duplicate/);
  assert.deepEqual([...testClasses(join(root, 'Tests/SecreteoUITests'))], [['Same', 1]]);
});
test('duplicate method declarations fail inventory discovery', t => {
  const root = fixture(t, { 'A.swift': 'class A: XCTestCase {\n func testOne() {}\n func testOne() {}\n}\n' });
  assert.throws(() => testInventory(join(root, 'Tests/SecreteoUITests')), /Duplicate/);
});
test('the repository smoke inventory resolves to ten distinct methods', () => {
  const smoke = readFileSync(new URL('../Plans/Smoke.txt', import.meta.url), 'utf8');
  const selection = smoke.split('\n').filter(Boolean).map(line => `-only-testing:${line}`);
  assert.equal(inventory('smoke', '', selection, testInventory(), smoke).expectedTests.length, 10);
});
