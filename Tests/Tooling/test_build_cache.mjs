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

const dryrun = job(workflow('ci.yml'), 'release-dryrun');
const releaseCache = job(workflow('build-cache.yml'), 'release-build');

function validateRelease(dryrunJob, cacheJob) {
  const prefix = source => {
    const image = /runs-on: (\S+)/.exec(source)?.[1];
    const xcode = /Xcode_([\d.]+)\.app/.exec(source)?.[1];
    assert.ok(image && xcode, 'Both jobs must declare their toolchain');
    return `release-derived-${image}-xcode-${xcode}-`;
  };
  const key = prefix(dryrunJob);
  assert.equal(prefix(cacheJob), key);
  const graph = "${{ hashFiles('Package.swift', 'project.yml') }}";
  assert.ok(dryrunJob.includes(`key: ${key}${graph}-\${{ hashFiles('Package.resolved') }}-\n`));
  assert.ok(dryrunJob.includes(`restore-keys: ${key}${graph}-\n`));
  assert.ok(cacheJob.includes(`GRAPH: ${graph}\n`));
  assert.ok(cacheJob.includes(`graph=${key}$GRAPH-"`));
  assert.ok(cacheJob.includes(`prefix=${key}$GRAPH-$RESOLVED-"`));
  assert.ok(cacheJob.includes('key: ${{ steps.key.outputs.prefix }}${{ github.run_id }}'));
  assert.ok(cacheJob.includes('restore-keys: ${{ steps.key.outputs.graph }}\n'), 'main never crosses a graph change');
  const actions = source => [...source.matchAll(/uses: (actions\/cache[^@]*)@/g)].map(match => match[1]);
  assert.deepEqual(actions(dryrunJob), ['actions/cache/restore'], 'PRs only restore, never the saving action');
  assert.deepEqual(actions(cacheJob), ['actions/cache/restore', 'actions/cache/save']);
  const save = cacheJob.slice(cacheJob.indexOf('actions/cache/save@'));
  assert.doesNotMatch(save, /^\s+if:/m, 'only a successful build is saved');
  for (const source of [dryrunJob, cacheJob]) assert.match(source, /path: build\/release\n/);
  assert.match(cacheJob, /- run: scripts\/release-dryrun\.sh package\n/);
  assert.match(cacheJob, /^    if: github\.ref == 'refs\/heads\/main'$/m);
  // The cache must restore before the build that uses it.
  const restore = dryrunJob.indexOf('actions/cache/restore@');
  assert.ok(restore >= 0 && restore < dryrunJob.indexOf('scripts/release-dryrun.sh'));
}

test('the dry run restores the derived data main saves, under the same key', () => {
  validateRelease(dryrun, releaseCache);
});

test('real releases never restore a cache', () => {
  assert.doesNotMatch(workflow('release.yml'), /actions\/cache/);
});

for (const [name, changeDryrun, changeCache] of [
  ['different Xcode', value => value, value => value.replace(/Xcode_[\d.]+\.app/, 'Xcode_0.0.app')],
  ['a cache saved by a PR', value => value + '\n      - uses: actions/cache/save@abc', value => value],
  ['a changed project restoring old products', value => value.replace(/restore-keys: [^\n]+/, 'restore-keys: release-derived-'),
    value => value],
  ['a graph without project.yml', value => value.replaceAll(", 'project.yml'", ''), value => value],
  ['a cache key shared by different runs', value => value, value => value.replace('${{ github.run_id }}', 'shared')],
  ['a cache saved off main', value => value, value => value.replace("if: github.ref == 'refs/heads/main'", 'if: always()')],
  ['a different derived data path', value => value, value => value.replaceAll('path: build/release', 'path: build/other')],
  ['a PR using the saving cache action', value => value.replace('actions/cache/restore@', 'actions/cache@'), value => value],
  ['a dry run without a restore', value => value.replace(/      - uses: actions\/cache\/restore@[\s\S]*?(?=      - run: scripts\/release-dryrun)/, ''),
    value => value],
  ['main crossing a graph change', value => value, value => value.replace(
    'restore-keys: ${{ steps.key.outputs.graph }}', 'restore-keys: release-derived-')],
  ['saving a failed build', value => value, value => value.replace(
    /(      - uses: actions\/cache\/save@[^\n]*\n)/, '$1        if: always()\n')],
]) {
  test(`release cache rejects ${name}`, () => {
    assert.throws(() => validateRelease(changeDryrun(dryrun), changeCache(releaseCache)), assert.AssertionError);
  });
}
