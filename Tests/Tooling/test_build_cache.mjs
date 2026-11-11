import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const workflows = new URL('../../.github/workflows/', import.meta.url);
const workflow = name => readFileSync(new URL(name, workflows), 'utf8');
const job = (source, name) => {
  const lines = source.split('\n');
  const start = lines.indexOf(`  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const end = lines.findIndex((line, i) => i > start && /^  \S/.test(line));
  return lines.slice(start, end < 0 ? undefined : end).join('\n');
};
const unit = job(workflow('ci.yml'), 'unit');
const cache = job(workflow('build-cache.yml'), 'swift-build');

function validate(unitJob, cacheJob) {
  const prefix = source => {
    const image = /runs-on: (\S+)/.exec(source)?.[1];
    const xcode = /Xcode_([\d.]+)\.app/.exec(source)?.[1];
    assert.ok(image && xcode, 'Both jobs must declare their toolchain');
    return `swiftpm-build-${image}-xcode-${xcode}-`;
  };
  const key = prefix(unitJob);
  assert.equal(prefix(cacheJob), key);
  assert.ok(unitJob.includes(`key: ${key}\${{ hashFiles('Package.swift') }}-\${{ hashFiles('Package.resolved') }}-\n`));
  assert.ok(unitJob.includes(`restore-keys: ${key}\${{ hashFiles('Package.swift') }}-\n`));
  assert.ok(cacheJob.includes(`graph=${key}$MANIFEST-"`));
  assert.ok(cacheJob.includes(`prefix=${key}$MANIFEST-$RESOLVED-"`));
  assert.ok(cacheJob.includes('restore-keys: ${{ steps.key.outputs.graph }}\n'));
  assert.ok(cacheJob.includes('key: ${{ steps.key.outputs.prefix }}${{ github.run_id }}'));
  assert.ok(!unitJob.includes('actions/cache/save@'), 'PRs must not evict the main cache');
  const commands = source => [...source.matchAll(/^\s*(?:- run: )?swift (.+)$/gm)].map(match => match[1]);
  assert.deepEqual(commands(unitJob), [
    'build -Xswiftc -warnings-as-errors',
    'test --parallel -Xswiftc -warnings-as-errors',
  ]);
  assert.deepEqual(commands(cacheJob), ['build --build-tests -Xswiftc -warnings-as-errors']);
}

test('cache keys, toolchains and compiler flags agree with unit, including all test bundles', () => {
  validate(unit, cache);
});

for (const [name, changeUnit, changeCache] of [
  ['different runner', value => value, value => value.replace(/runs-on: \S+/, 'runs-on: incompatible-runner')],
  ['different Xcode', value => value, value => value.replace(/Xcode_[\d.]+\.app/, 'Xcode_0.0.app')],
  ['missing test products', value => value, value => value.replace(' --build-tests', '')],
  ['weakened compiler diagnostics', value => value, value => value.replace(' -warnings-as-errors', '')],
  ['a cache saved by a PR', value => value + '\n      - uses: actions/cache/save@abc', value => value],
  ['a changed manifest restoring old products', value => value.replace(
    /restore-keys: [^\n]+/, 'restore-keys: swiftpm-build-'), value => value],
  ['a cache key shared by different runs', value => value, value => value.replace('${{ github.run_id }}', 'shared')],
  ['redundant default-product build', value => value, value => value + '\n      - run: swift build -Xswiftc -warnings-as-errors'],
  ['a build hidden in a script block', value => value, value => value + '\n      - run: |\n          swift build -Xswiftc -warnings-as-errors'],
]) {
  test(`rejects ${name}`, () => {
    assert.throws(() => validate(changeUnit(unit), changeCache(cache)), assert.AssertionError);
  });
}
