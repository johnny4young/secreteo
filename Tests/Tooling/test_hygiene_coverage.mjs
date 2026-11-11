import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { test } from 'node:test';

const directory = new URL('../../.github/workflows/', import.meta.url);
const workflows = Object.fromEntries(readdirSync(directory)
  .filter(name => /\.ya?ml$/.test(name))
  .map(name => [name, readFileSync(new URL(name, directory), 'utf8')]));
const gate = readFileSync(new URL('../../scripts/check-repository-hygiene.sh', import.meta.url), 'utf8');
const command = 'scripts/check-repository-hygiene.sh';
const legacy = "python3 -I -m unittest discover -s Tests/Tooling -p 'test_*.py'";
const nodeSuites = ['test_log_privacy', 'test_stop_tail_in_tests', 'test_swift_sources', 'test_ci_reuse', 'test_ui_inventory', 'test_release_timings'];
const pair = `      - run: ${command}\n      - name: Legacy tooling coverage\n        run: ${legacy}\n`;

function job(source, name) {
  const lines = source.split('\n');
  const start = lines.indexOf(`  ${name}:`);
  assert.notEqual(start, -1, `Missing ${name} job`);
  const end = lines.findIndex((line, index) => index > start && /^  \S/.test(line));
  return lines.slice(start, end < 0 ? undefined : end).join('\n');
}

function validate(sources, script) {
  const consumers = Object.entries(sources).flatMap(([name, source]) =>
    [...source.matchAll(/scripts\/check-repository-hygiene\.sh/g)].map(() => name));
  assert.deepEqual(consumers.sort(), ['ci.yml', 'release.yml']);
  const hygiene = job(sources['ci.yml'], 'hygiene');
  const hygieneStep = `      - run: ${command}`;
  assert.ok(hygiene.includes(`${hygieneStep}\n`));
  assert.equal(hygiene.slice(hygiene.indexOf(hygieneStep)).split(/\n      - /)[0].trimEnd(), hygieneStep,
    'Repository hygiene cannot be conditional or allowed to fail');
  assert.doesNotMatch(hygiene, /^    (?:if|continue-on-error|needs):/m,
    'CI hygiene must run independently and unconditionally');
  assert.doesNotMatch(hygiene, /python3/, 'CI legacy coverage runs on an independent runner');
  for (const [file, name] of [['ci.yml', 'legacy-tooling'], ['release.yml', 'verify']]) {
    const block = job(sources[file], name);
    assert.doesNotMatch(block, /^    (?:if|continue-on-error):/m, 'Verification jobs must be unconditional');
    if (file === 'release.yml') {
      assert.ok(block.includes(pair), 'Release keeps repository and legacy checks adjacent');
    } else {
      assert.doesNotMatch(block, /^    needs:/m, 'CI legacy coverage must run independently');
      assert.match(block, /^    runs-on: ubuntu-latest$/m);
      assert.match(block, /uses: actions\/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1/);
    }
    const tail = block.slice(block.indexOf('      - name: Legacy tooling coverage'));
    const step = tail.split(/\n      - /)[0].trimEnd();
    assert.equal(step, `      - name: Legacy tooling coverage\n        run: ${legacy}`,
      'Legacy checks cannot be conditional or allowed to fail');
  }
  const needs = /needs: \[([^\]]+)\]/.exec(job(sources['ci.yml'], 'gate'))?.[1];
  for (const name of ['hygiene', 'legacy-tooling']) {
    assert.ok(needs?.split(',').map(name => name.trim()).includes(name), `gate must require ${name}`);
  }
  const packaging = job(sources['release.yml'], 'package');
  assert.match(packaging, /^    needs: verify$/m);
  assert.doesNotMatch(packaging, /^    if:/m, 'Packaging cannot run after a failed verification');
  assert.doesNotMatch(script, /\bpython[\d.]*\b/, 'Repository hygiene must not invoke Python');
  assert.ok(script.includes('  bash Tests/Tooling/test_repository_hygiene.sh\n'));
  assert.ok(script.includes('Tests/Tooling/test_hygiene_coverage.mjs'));
  for (const name of nodeSuites) {
    assert.ok(script.includes(`Tests/Tooling/${name}.mjs`));
  }
}

test('both verification paths retain all legacy tooling while local hygiene uses Bash and Node', () => {
  validate(workflows, gate);
});

for (const [name, file, mutate] of [
  ['missing CI legacy tests', 'ci.yml', source => source.replace(`        run: ${legacy}`, '        run: true')],
  ['missing release legacy tests', 'release.yml', source => source.replace(`        run: ${legacy}`, '        run: true')],
  ['narrower discovery', 'ci.yml', source => source.replace("-p 'test_*.py'", "-p 'test_ci_scripts.py'")],
  ['conditional legacy step', 'ci.yml', source => source.replace(`        run: ${legacy}`, `        run: ${legacy}\n        if: false`)],
  ['allowed legacy failure', 'release.yml', source => source.replace(`        run: ${legacy}`, `        run: ${legacy}\n        continue-on-error: true`)],
  ['conditional verification job', 'ci.yml', source => source.replace('  hygiene:\n', '  hygiene:\n    if: false\n')],
  ['conditional hygiene step', 'ci.yml', source => source.replace(`      - run: ${command}`, `      - run: ${command}\n        if: false`)],
  ['allowed hygiene step failure', 'ci.yml', source => source.replace(`      - run: ${command}`, `      - run: ${command}\n        continue-on-error: true`)],
  ['missing legacy job', 'ci.yml', source => source.replace('  legacy-tooling:\n', '  removed:\n')],
  ['conditional legacy job', 'ci.yml', source => source.replace('  legacy-tooling:\n', '  legacy-tooling:\n    if: false\n')],
  ['allowed legacy job failure', 'ci.yml', source => source.replace('  legacy-tooling:\n', '  legacy-tooling:\n    continue-on-error: true\n')],
  ['serial CI legacy job', 'ci.yml', source => source.replace('  legacy-tooling:\n', '  legacy-tooling:\n    needs: hygiene\n')],
  ['serial CI hygiene job', 'ci.yml', source => source.replace('  hygiene:\n', '  hygiene:\n    needs: legacy-tooling\n')],
  ['allowed verification failure', 'release.yml', source => source.replace('  verify:\n', '  verify:\n    continue-on-error: true\n')],
  ['missing required hygiene dependency', 'ci.yml', source => source.replace('needs: [hygiene, ', 'needs: [')],
  ['missing required legacy dependency', 'ci.yml', source => source.replace('needs: [hygiene, legacy-tooling, ', 'needs: [hygiene, ')],
  ['release bypassing verification', 'release.yml', source => source.replace('    needs: verify', '    needs: []')],
  ['release packaging after failed verification', 'release.yml', source => source.replace('    needs: verify\n', '    needs: verify\n    if: always()\n')],
]) {
  test(`rejects ${name}`, () => {
    assert.throws(() => validate({ ...workflows, [file]: mutate(workflows[file]) }, gate));
  });
}

test('rejects a new caller without explicit legacy coverage', () => {
  assert.throws(() => validate({ ...workflows, 'new.yml': `- run: ${command}` }, gate));
});

test('rejects silently dropping migrated tests from the local gate', () => {
  assert.throws(() => validate(workflows, gate.replace('  bash Tests/Tooling/test_repository_hygiene.sh\n', '')));
});

test('rejects restoring an implicit Python dependency in local hygiene', () => {
  assert.throws(() => validate(workflows, `${gate}\n${legacy}\n`));
});

for (const name of nodeSuites) {
  test(`rejects dropping ${name} from hygiene`, () => {
    assert.throws(() => validate(workflows, gate.replace(`Tests/Tooling/${name}.mjs`, '')));
  });
}
