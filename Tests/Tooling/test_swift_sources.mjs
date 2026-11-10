import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, readFileSync, mkdirSync, mkdtempSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { gitEnvironment, readSwiftSources } from './swift_sources.mjs';

function fixture(t) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'swift-source-contract-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const env = gitEnvironment();
  delete env.NODE_TEST_CONTEXT;
  const git = (...args) => execFileSync('git', ['-c', 'core.hooksPath=/dev/null', ...args], { cwd: root, env });
  git('init', '-q', '-b', 'main');
  const write = (name, text) => {
    mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
    writeFileSync(path.join(root, name), text);
  };
  return { root, env, git, write };
}

test('discovery includes tracked and untracked Swift paths without splitting or quoting them', t => {
  const { root, git, write } = fixture(t);
  const names = ['Sources/with space.swift', 'Sources/café.swift', 'Apps/line\nbreak.swift', 'Sources/tab\tname.swift', 'Sources/carriage\rreturn.swift'];
  for (const name of names) write(name, 'let value = 1\n');
  write('Sources/deleted.swift', '');
  git('add', '--', names[0], names[1], 'Sources/deleted.swift');
  unlinkSync(path.join(root, 'Sources/deleted.swift'));
  write('.gitignore', 'ignored.swift\n');
  write('Sources/ignored.swift', 'print("not in the source set")');
  write('Sources/readme.txt', 'not Swift');
  assert.deepEqual(readSwiftSources(root, ['Sources', 'Apps']).map(([name]) => name), names.sort());
});

test('malformed UTF-8 source fails the check rather than disappearing', t => {
  const { root, write } = fixture(t);
  write('Sources/bad.swift', Buffer.from([0xff]));
  assert.throws(() => readSwiftSources(root, ['Sources']));
});

for (const [name, file, sourcePath, badSource] of [
  ['log privacy', 'test_log_privacy.mjs', 'Sources/space café.swift', 'print(secret)\n'],
  ['stop tail', 'test_stop_tail_in_tests.mjs', 'Tests/space café.swift', 'let d = DictationSessionDependencies(a: 1)\n'],
]) {
  test(`${name} rejects an offending source with a spaced Unicode path through its actual test entrypoint`, t => {
    const { root, env, write } = fixture(t);
    write('Tests/Tooling/.keep', '');
    for (const module of [file, 'swift_sources.mjs']) {
      copyFileSync(new URL(module, import.meta.url), path.join(root, 'Tests/Tooling', module));
    }
    write(sourcePath, badSource);
    const child = spawnSync(process.execPath, ['--test', `Tests/Tooling/${file}`], { cwd: root, env, encoding: 'utf8' });
    assert.ifError(child.error);
    assert.equal(child.status, 1, child.stdout + child.stderr);
    assert.ok((child.stdout + child.stderr).includes(sourcePath), 'The diagnostic must identify the actual path');
  });
}

test('an empty repository has no Swift inputs', t => {
  const { root } = fixture(t);
  assert.deepEqual(readSwiftSources(root, ['Sources', 'Apps']), []);
});

test('a failed Git inventory fails closed', t => {
  const { root } = fixture(t);
  rmSync(path.join(root, '.git'), { recursive: true });
  assert.throws(() => readSwiftSources(root, ['Sources']));
});

test('fixtures and readers ignore inherited Git paths, index and injected configuration', t => {
  const outside = mkdtempSync(path.join(os.tmpdir(), 'git-env-sentinel-'));
  t.after(() => rmSync(outside, { recursive: true, force: true }));
  const index = path.join(outside, 'index');
  writeFileSync(index, 'external index sentinel');
  const poison = {
    GIT_INDEX_FILE: index, GIT_DIR: path.join(outside, 'repo.git'), GIT_WORK_TREE: outside,
    GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'core.bare', GIT_CONFIG_VALUE_0: 'true',
    GIT_CONFIG_GLOBAL: path.join(outside, 'config'), GIT_OBJECT_DIRECTORY: path.join(outside, 'objects'),
  };
  const previous = Object.fromEntries(Object.keys(poison).map(key => [key, process.env[key]]));
  try {
    Object.assign(process.env, poison);
    const { root, git, write, env } = fixture(t);
    write('Sources/check.swift', 'let value = 1');
    git('add', '--', 'Sources/check.swift');
    assert.deepEqual(readSwiftSources(root, ['Sources']).map(([name])=>name), ['Sources/check.swift']);
    for (const key of Object.keys(poison)) {
      if (key !== 'GIT_CONFIG_GLOBAL') assert.equal(env[key], undefined, key);
    }
    assert.equal(env.GIT_CONFIG_GLOBAL, '/dev/null');
    assert.equal(readFileSync(index, 'utf8'), 'external index sentinel');
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key]; else process.env[key] = value;
    }
  }
});
