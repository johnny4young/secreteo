import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { classify, glob, main as classifyInput } from '../../scripts/ci_changes.mjs';
import { failures } from '../../scripts/ci_gate.mjs';

const root = fileURLToPath(new URL('../..', import.meta.url));
const all = { code: true, delivery: true, release: true };
const always = ['hygiene', 'legacy-tooling', 'lint', 'changes'];
const scoped = { unit: 'code', 'ui-smoke': 'code', 'signed-handoff': 'delivery', 'release-dryrun': 'release' };
function needs(scope = {}, results = {}) {
  const payload = Object.fromEntries([...always, ...Object.keys(scoped)].map(name => [name, {
    result: Object.hasOwn(results, name) ? results[name] : 'success',
  }]));
  payload.changes.outputs = { code: 'true', delivery: 'true', release: 'true', ...scope };
  return payload;
}
const run = (script, args = [], input = '') => spawnSync(process.execPath, [`scripts/${script}.mjs`, ...args], {
  cwd: root, input, encoding: 'utf8',
});

test('docs only is not code', () => {
  assert.equal(classify(['docs/A.md', 'README.md', 'site/index.html']).code, false);
});
test('any source file is code', () => {
  assert.equal(classify(['docs/A.md', 'Sources/AppUI/A.swift']).code, true);
});
test('workflow change is code', () => {
  assert.equal(classify(['.github/workflows/ci.yml']).code, true);
});
test('an empty diff never skips', () => {
  assert.deepEqual(classify([]), all);
});
test('delivery and triggers select the signed lane', () => {
  for (const path of ['Sources/DictationSession/Delivery/TextInserter.swift',
    'Tests/DictationSessionTests/Delivery/TextInsertionTargetTests.swift',
    'Sources/DictationSession/Triggers/GlobalHotkey.swift', 'Tests/DictationSessionTests/Triggers/HotkeySettingTests.swift']) {
    assert.equal(classify([path]).delivery, true, path);
  }
  for (const path of ['Sources/DictationSession/DictationController.swift', 'Sources/AppUI/A.swift']) {
    assert.equal(classify([path]).delivery, false, path);
  }
});
test('ci machinery runs every lane', () => {
  for (const path of ['.github/workflows/ci.yml', 'scripts/ci_changes.mjs', 'scripts/ci_gate.mjs',
    'scripts/ci_changes.py', 'scripts/ci_gate.py', 'scripts/ci_reuse_gate.py', 'scripts/ci_reuse_gate.mjs']) assert.deepEqual(classify([path]), all, path);
});
test('packaging selects the release dry run', () => {
  for (const path of ['scripts/package-release.sh', 'project.yml', 'Apps/Secreteo/SparkleUpdater.swift']) {
    assert.equal(classify([path]).release, true, path);
  }
  for (const path of ['Sources/AppUI/A.swift', 'Apps/Secreteo/Localizable.xcstrings']) {
    assert.equal(classify([path]).release, false, path);
  }
});
test('all green passes', () => { assert.deepEqual(failures(needs()), []); });
test('a failure fails', () => { assert.notDeepEqual(failures(needs({}, { unit: 'failure' })), []); });
test('a cancelled job fails', () => { assert.notDeepEqual(failures(needs({}, { unit: 'cancelled' })), []); });
test('skipping unit on a code change fails', () => {
  assert.notDeepEqual(failures(needs({ code: 'true' }, { unit: 'skipped' })), []);
});
test('skipping unit on docs passes', () => {
  assert.deepEqual(failures(needs({ code: 'false' }, { unit: 'skipped' })), []);
});
test('a failure on docs still fails', () => {
  assert.notDeepEqual(failures(needs({ code: 'false' }, { unit: 'failure' })), []);
});
test('a missing scope cannot skip', () => {
  const payload = needs({}, { unit: 'skipped' });
  payload.changes.outputs = {};
  assert.notDeepEqual(failures(payload), []);
});
test('hygiene can never be skipped', () => {
  assert.notDeepEqual(failures(needs({ code: 'false' }, { hygiene: 'skipped' })), []);
});
test('a failed scope job fails', () => {
  assert.notDeepEqual(failures(needs({}, { changes: 'failure' })), []);
});
test('the signed lane follows its own scope', () => {
  assert.deepEqual(failures(needs({ delivery: 'false' }, { 'signed-handoff': 'skipped' })), []);
  assert.notDeepEqual(failures(needs({ delivery: 'true' }, { 'signed-handoff': 'skipped' })), []);
});
test('release dry run may skip only when scoped out', () => {
  assert.deepEqual(failures(needs({ release: 'false' }, { 'release-dryrun': 'skipped' })), []);
  assert.notDeepEqual(failures(needs({ release: 'true' }, { 'release-dryrun': 'skipped' })), []);
  assert.notDeepEqual(failures(needs({ release: 'false' }, { 'release-dryrun': 'failure' })), []);
});
test('a job missing from needs fails in every scope', () => {
  for (const job of Object.keys(scoped)) for (const flag of ['true', 'false']) {
    const payload = needs({ code: flag, delivery: flag, release: flag });
    delete payload[job];
    assert.notDeepEqual(failures(payload), [], `${job} ${flag}`);
  }
});
test('the author is not an input', () => {
  const payload = needs({}, { unit: 'skipped' });
  payload.actor = { result: 'dependabot[bot]' };
  assert.notDeepEqual(failures(payload), []);
});

test('all 2048 combinations of scoped success, skip, failure and cancellation follow their own flags', () => {
  const jobs = Object.keys(scoped);
  const states = ['success', 'skipped', 'failure', 'cancelled'];
  for (let scope = 0; scope < 8; scope++) for (let statuses = 0; statuses < 256; statuses++) {
    const flags = Object.fromEntries(['code', 'delivery', 'release'].map((flag, index) =>
      [flag, scope & (1 << index) ? 'true' : 'false']));
    const results = Object.fromEntries(jobs.map((job, index) => [job, states[(statuses >> (index * 2)) & 3]]));
    const expected = jobs.filter(job => results[job] !== 'success'
      && !(results[job] === 'skipped' && flags[scoped[job]] === 'false'));
    assert.deepEqual(failures(needs(flags, results)).map(value => value.split(':')[0]), expected,
      `scope=${scope} statuses=${statuses}`);
  }
});

test('all 256 combinations keep unconditional jobs mandatory', () => {
  for (let mask = 0; mask < 8; mask++) for (const job of always) {
    for (const status of ['success', 'skipped', 'failure', 'cancelled', 'neutral', 'timed_out', null, undefined]) {
      const scope = Object.fromEntries(['code', 'delivery', 'release'].map((flag, index) =>
        [flag, mask & (1 << index) ? 'true' : 'false']));
      assert.equal(failures(needs(scope, { [job]: status })).length === 0, status === 'success');
    }
  }
});

test('missing legacy tooling cannot pass the gate, including docs-only changes', () => {
  for (const flag of ['true', 'false']) {
    const payload = needs({ code: flag, delivery: flag, release: flag });
    delete payload['legacy-tooling'];
    assert.deepEqual(failures(payload), ['legacy-tooling: None']);
    const result = run('ci_gate', [JSON.stringify(payload)]);
    assert.equal(result.status, 1);
    assert.equal(result.stdout, '::error::legacy-tooling: None\n');
  }
});

test('only the exact false string authorizes a skip', () => {
  for (const value of [false, true, 0, null, undefined, '', 'FALSE', '0', [], {}]) {
    for (const [job, flag] of Object.entries(scoped)) {
      assert.notDeepEqual(failures(needs({ [flag]: value }, { [job]: 'skipped' })), []);
    }
  }
});

test('malformed needs shapes never pass', () => {
  for (const payload of [undefined, null, false, 1, 'success', [], {}]) assert.notDeepEqual(failures(payload), []);
  for (const job of [...always, ...Object.keys(scoped)]) for (const value of [null, false, 1, 'success', []]) {
    const payload = needs();
    payload[job] = value;
    assert.notDeepEqual(failures(payload), []);
  }
});

test('malformed outputs cannot pass even when all jobs report success', () => {
  for (const outputs of [null, false, 0, 'false', []]) {
    const payload = needs();
    payload.changes.outputs = outputs;
    assert.notDeepEqual(failures(payload), [], JSON.stringify(outputs));
    assert.equal(run('ci_gate', [JSON.stringify(payload)]).status, 1);
  }
  const missing = needs();
  delete missing.changes.outputs;
  assert.deepEqual(failures(missing), [], 'Missing scope is valid when every job succeeded');
});

test('malformed outputs still report every failed lane', () => {
  const payload = needs({}, { unit: 'failure' });
  payload.changes.outputs = [];
  assert.deepEqual(failures(payload).filter(line => line.startsWith('unit:')), ['unit: failure']);
});
test('patterns keep fnmatch semantics for several wildcards and literal regex characters', () => {
  assert.ok(glob('Sources/*/Delivery/*').test('Sources/X/Delivery/a.swift'));
  assert.ok(glob('docs/?.md').test('docs/a.md'));
  assert.ok(!glob('a.b').test('axb'));
});

test('the fixed glob policy includes nested files and exact literal paths', () => {
  for (const path of ['nested/deep/README.md', 'docs/deep/a.txt', 'site/deep/a.html', '.github/ISSUE_TEMPLATE/new.yml']) {
    assert.equal(classify([path]).code, false, path);
  }
  for (const path of ['LICENSE.backup', 'README.MD', 'site-copy/a.html', 'prefix/docs/a.txt']) {
    assert.equal(classify([path]).code, true, path);
  }
  assert.equal(classify(['Sources/DictationSession/Delivery/deep/file.swift']).delivery, true);
  assert.equal(classify(['Sources/DictationSession/DeliveryCopy/file.swift']).delivery, false);
  assert.equal(classify(['line\nname.md']).code, false);
});

test('a literal trailing newline does not turn an argv path into documentation', () => {
  assert.equal(classify(['LICENSE\n']).code, true);
  assert.equal(classify(['README.md\n']).code, true);
});

test('stdin supports CR-only lines without hiding a source path behind a markdown path', () => {
  assert.equal(classifyInput([], 'Sources/AppUI/A.swift\rdocs/A.md\r'),
    'code=true\ndelivery=false\nrelease=false\n');
});

test('stdin preserves a BOM rather than silently recognizing LICENSE', () => {
  assert.equal(classifyInput([], '\ufeffLICENSE\n'), 'code=true\ndelivery=false\nrelease=false\n');
});

test('stdin preserves the original whitespace set and argv remains literal', () => {
  for (const space of ['\t', '\v', '\f', '\u001c', '\u0085', '\u00a0', '\u1680', '\u2028', '\u202f', '\u3000']) {
    assert.equal(classifyInput([], `${space}LICENSE${space}\n`), 'code=false\ndelivery=false\nrelease=false\n');
  }
  assert.equal(classifyInput([' LICENSE '], 'docs/A.md'), 'code=true\ndelivery=false\nrelease=false\n');
  assert.equal(classifyInput([], 'LICENSE\u2028Sources/A.swift\n'), 'code=true\ndelivery=false\nrelease=false\n');
});

test('classifier CLI emits exact outputs for empty, argument and stdin paths', () => {
  for (const input of ['', '\n \t\r\n', ' \u001c\n']) {
    const result = run('ci_changes', [], input);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'code=true\ndelivery=true\nrelease=true\n');
  }
  for (const input of ['docs/A.md\nLICENSE\n', 'docs/A.md\r\nLICENSE\r\n', 'docs/A.md\rLICENSE\r']) {
    const result = run('ci_changes', [], input);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, 'code=false\ndelivery=false\nrelease=false\n');
  }
  const argument = run('ci_changes', ['Sources/AppUI/A.swift'], 'docs/A.md');
  assert.equal(argument.status, 0, argument.stderr);
  assert.equal(argument.stdout, 'code=true\ndelivery=false\nrelease=false\n');
});

test('classifier CLI rejects malformed UTF-8 without publishing partial scope', () => {
  const result = run('ci_changes', [], Buffer.from([0xff, 0x0a]));
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '');
  assert.match(result.stderr, /Could not classify/);
});

test('gate CLI fails closed on missing or malformed JSON and emits failure annotations', () => {
  for (const args of [[], ['{'], ['null'], ['[]'], ['"success"']]) assert.equal(run('ci_gate', args).status, 1);
  const success = run('ci_gate', [JSON.stringify(needs())]);
  assert.equal(success.status, 0, success.stderr);
  assert.equal(success.stdout, '');
  const result = run('ci_gate', [JSON.stringify(needs({}, { unit: 'failure' }))]);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '::error::unit: failure\n');
});

test('gate error values cannot introduce another workflow command', () => {
  const result = run('ci_gate', [JSON.stringify(needs({}, { unit: 'failure%\r\n::notice::other' }))]);
  assert.equal(result.status, 1);
  assert.equal(result.stdout, '::error::unit: failure%25%0D%0A::notice::other\n');
});

test('stdin imports have no CLI side effects and symlinks still invoke both CLIs', () => {
  const imported = spawnSync(process.execPath, ['--input-type=module'], {
    cwd: root, input: "await import('./scripts/ci_changes.mjs'); await import('./scripts/ci_gate.mjs'); console.log('imported');",
    encoding: 'utf8',
  });
  assert.equal(imported.status, 0, imported.stderr);
  assert.equal(imported.stdout, 'imported\n');
  const dir = mkdtempSync(join(tmpdir(), 'secreteo-ci-links-'));
  try {
    for (const script of ['ci_changes', 'ci_gate']) {
      const link = join(dir, `${script} link ü.mjs`);
      symlinkSync(join(root, 'scripts', `${script}.mjs`), link);
      const args = script === 'ci_changes' ? ['LICENSE'] : [JSON.stringify(needs())];
      const result = spawnSync(process.execPath, [link, ...args], { cwd: dir, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout, script === 'ci_changes' ? 'code=false\ndelivery=false\nrelease=false\n' : '');
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

const workflow = readFileSync(new URL('../../.github/workflows/ci.yml', import.meta.url), 'utf8');
const hygiene = readFileSync(new URL('../../scripts/check-repository-hygiene.sh', import.meta.url), 'utf8');
function job(source, name) {
  const lines = source.split('\n');
  const start = lines.indexOf(`  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const end = lines.findIndex((line, index) => index > start && /^  \S/.test(line));
  return lines.slice(start, end < 0 ? undefined : end).join('\n');
}

function validateWiring(source, repositoryGate) {
  for (const [name, script] of [['changes', 'ci_changes'], ['gate', 'ci_gate']]) {
    const block = job(source, name);
    const setup = block.indexOf('uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1');
    const command = block.indexOf(`node scripts/${script}.mjs`);
    assert.ok(setup >= 0 && command > setup, `${name}: runtime before command`);
    assert.match(block, /node-version-file: \.nvmrc/);
    assert.match(block, /check-latest: true/);
    assert.match(block, /package-manager-cache: false/);
  }
  assert.match(job(source, 'gate'), /NEEDS: \$\{\{ toJSON\(needs\) \}\}/);
  assert.match(job(source, 'gate'), /run: node scripts\/ci_gate\.mjs "\$NEEDS"/);
  assert.match(job(source, 'gate'), /if: always\(\)/);
  assert.match(job(source, 'changes'), /set -euo pipefail/);
  assert.match(job(source, 'changes'), /node scripts\/ci_reuse_gate\.mjs "\$GITHUB_REPOSITORY" "\$HEAD_SHA"/);
  assert.ok(repositoryGate.includes('Tests/Tooling/test_ci_decisions.mjs'));
  assert.doesNotMatch(source, /python3 scripts\/ci_(?:changes|gate|reuse_gate)\.py/);
}

test('workflow provisions the pinned Node runtime and keeps hosted reuse proof explicit', () => {
  validateWiring(workflow, hygiene);
});

for (const [name, mutate] of [
  ['missing runtime setup', value => value.replaceAll('actions/setup-node@', 'actions/unavailable@')],
  ['different Node version source', value => value.replaceAll('node-version-file: .nvmrc', 'node-version: 1')],
  ['changed scope entry point', value => value.replace('node scripts/ci_changes.mjs', 'node scripts/other.mjs')],
  ['changed gate entry point', value => value.replace('node scripts/ci_gate.mjs', 'node scripts/other.mjs')],
  ['no needs payload', value => value.replace('NEEDS: ${{ toJSON(needs) }}', 'NEEDS: {}')],
  ['gate omitted after failure', value => value.replace('  gate:\n    if: always()', '  gate:\n    if: success()')],
  ['masked pipeline failure', value => value.replace('set -euo pipefail', 'set -eu')],
]) {
  test(`workflow rejects ${name}`, () => {
    assert.throws(() => validateWiring(mutate(workflow), hygiene));
  });
}

test('removing migrated decisions tests from hygiene is rejected', () => {
  assert.throws(() => validateWiring(workflow, hygiene.replace('Tests/Tooling/test_ci_decisions.mjs', '')));
});

test('the actual scope pipeline propagates a classifier failure through tee', () => {
  const scope = job(workflow, 'changes');
  const marker = '        run: |\n';
  assert.ok(scope.includes(marker));
  const script = scope.slice(scope.indexOf(marker) + marker.length).split('\n').map(line => line.slice(10)).join('\n');
  const dir = mkdtempSync(join(tmpdir(), 'secreteo-ci-pipe-'));
  try {
    writeFileSync(join(dir, 'node'), '#!/bin/sh\nexit 42\n', { mode: 0o755 });
    const options = { cwd: dir, encoding: 'utf8', env: {
      PATH: `${dir}:/usr/bin:/bin`, EVENT_NAME: 'pull_request', BASE_SHA: '', HEAD_SHA: 'synthetic',
      GITHUB_REPOSITORY: 'fixture/repo', GITHUB_OUTPUT: join(dir, 'outputs'),
    } };
    assert.equal(spawnSync('/bin/bash', ['-e', '-c', script], options).status, 42);
    assert.equal(spawnSync('/bin/bash', ['-e', '-c', script.replace('set -euo pipefail', '')], options).status, 0,
      'The negative control reproduces tee hiding the failure');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
