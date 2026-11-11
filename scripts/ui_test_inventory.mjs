import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, realpathSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { testInventory, shards, shardArguments } from './ui_test_shards.mjs';

const read = path => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(readFileSync(path));

export function inventory(plan, shard, selection, found, smoke) {
  let expectedSelection, expectedTests;
  if (plan === 'smoke') {
    assert.equal(shard, '', 'Smoke cannot be sharded');
    const entries = smoke.split('\n').filter(Boolean);
    assert.ok(entries.length > 0 && entries.length <= 10, 'Smoke must select one to ten tests');
    expectedSelection = entries.map(entry => `-only-testing:${entry}`);
    expectedTests = entries.map(entry => {
      const parts = entry.split('/');
      assert.equal(parts.length, 3, `Smoke must name an individual test: ${entry}`);
      const [target, name, method] = parts;
      assert.equal(target, 'SecreteoUITests', `Unknown UI test target: ${entry}`);
      assert.ok(found.get(name)?.includes(method), `Unknown smoke test: ${entry}`);
      return `${name}/${method}()`;
    });
  } else {
    assert.equal(plan, 'full', 'Unknown UI plan');
    let names = [...found.keys()];
    expectedSelection = [];
    if (shard) {
      const args = shard.split('/');
      assert.equal(args.length, 2, 'Invalid shard');
      const [index, count] = shardArguments(args);
      names = shards(new Map([...found].map(([name, tests]) => [name, tests.length])), count)[index - 1];
      expectedSelection = names.map(name => `-only-testing:SecreteoUITests/${name}`);
    }
    expectedTests = names.flatMap(name => found.get(name).map(method => `${name}/${method}()`));
  }
  assert.deepEqual(selection, expectedSelection, 'Selection differs from the plan');
  assert.ok(expectedTests.length > 0, 'UI inventory is empty');
  assert.equal(new Set(expectedTests).size, expectedTests.length, 'Duplicate expected tests');
  return { schemaVersion: 1, plan, shard: shard || null, selection, expectedTests };
}

export function qualify(document, expected) {
  const issues = [], cases = [];
  const check = (condition, message) => { if (!condition) issues.push(message); };
  try {
    const inventoryIssue = 'Invalid UI inventory', captureIssue = 'Incomplete UI capture';
    const planIssue = 'Receipt plan differs from the inventory';
    assert.equal(expected.schemaVersion, 1, inventoryIssue);
    assert.ok(['smoke', 'full'].includes(expected.plan), inventoryIssue);
    assert.ok(Array.isArray(expected.selection) && expected.selection.every(value => typeof value === 'string'), inventoryIssue);
    assert.ok(Array.isArray(expected.expectedTests) && expected.expectedTests.length > 0, inventoryIssue);
    assert.ok(expected.expectedTests.every(value => typeof value === 'string' && value.length > 0), inventoryIssue);
    assert.equal(new Set(expected.expectedTests).size, expected.expectedTests.length, inventoryIssue);
    assert.equal(document.schemaVersion, 1, captureIssue);
    assert.equal(document.xcresultSchemaVersion, '0.1.0', captureIssue);
    assert.equal(document.captureComplete, true, captureIssue);
    assert.deepEqual(document.errors, [], captureIssue);
    assert.equal(document.plan, expected.plan, planIssue);
    assert.equal(document.shard, expected.shard, planIssue);
    assert.deepEqual(document.selection, expected.selection, planIssue);
    check(document.testExitCode === 0, 'UI process did not succeed');
    function walk(nodes) {
      assert.ok(Array.isArray(nodes), 'Malformed UI test tree');
      for (const node of nodes) {
        assert.ok(node && typeof node === 'object' && !Array.isArray(node), 'Malformed UI test tree');
        if (node.nodeType === 'Test Case') {
          assert.equal(typeof node.nodeIdentifier, 'string', 'Malformed UI test tree');
          cases.push({ identifier: node.nodeIdentifier, result: node.result });
        }
        if (node.children !== undefined) walk(node.children);
      }
    }
    walk(document.reports.tests.testNodes);
    const actual = cases.map(row => row.identifier);
    check(new Set(actual).size === actual.length, 'Duplicate executed tests');
    check(actual.length === expected.expectedTests.length
      && expected.expectedTests.every(id => actual.includes(id)), 'Executed tests differ from the inventory');
    check(cases.every(row => row.result === 'Passed'), 'Selected tests did not all pass');
    const summary = document.reports.summary;
    check(summary.result === 'Passed' && summary.totalTestCount === expected.expectedTests.length
      && summary.passedTests === expected.expectedTests.length && summary.failedTests === 0
      && summary.skippedTests === 0 && summary.expectedFailures === 0
      && Array.isArray(summary.testFailures) && summary.testFailures.length === 0, 'Summary does not prove every selected test passed');
  } catch (error) {
    issues.push(error instanceof assert.AssertionError && !error.generatedMessage
      ? error.message.split('\n')[0] : 'Invalid or mismatched UI evidence');
  }
  return { schemaVersion: 1, qualified: issues.length === 0, issues, cases };
}

function isMain() {
  try { return process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url); }
  catch { return false; }
}
if (isMain()) {
  try {
    const [command, target, plan, shard, ...selection] = process.argv.slice(2);
    if (command === 'plan' && target !== undefined && plan !== undefined && shard !== undefined) {
      const smoke = plan === 'smoke' ? read(new URL('../Tests/Plans/Smoke.txt', import.meta.url)) : '';
      const expected = inventory(plan, shard, selection, testInventory(), smoke);
      writeFileSync(join(target, 'test-inventory.json'), `${JSON.stringify(expected, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
    } else if (command === 'qualify' && target !== undefined && plan === undefined) {
      const result = qualify(JSON.parse(read(join(target, 'test-results.json'))), JSON.parse(read(join(target, 'test-inventory.json'))));
      writeFileSync(join(target, 'test-validation.json'), `${JSON.stringify(result, null, 2)}\n`, { flag: 'wx', mode: 0o600 });
      if (!result.qualified) { console.error(result.issues.join('\n')); process.exitCode = 1; }
    } else throw new Error('Usage: ui_test_inventory.mjs plan TARGET PLAN SHARD [SELECTION...] | qualify TARGET');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
