import assert from 'node:assert/strict';
import { after, test } from 'node:test';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';

const roots = [];
after(() => { for (const root of roots) rmSync(root, { recursive: true, force: true }); });
const stub = `#!${process.execPath}
const fs = require('node:fs'), path = require('node:path');
const name = path.basename(process.argv[1]), args = process.argv.slice(2);
const previous = fs.existsSync('calls.jsonl') ? fs.readFileSync('calls.jsonl', 'utf8').trim().split('\\n').map(JSON.parse) : [];
fs.appendFileSync('calls.jsonl', JSON.stringify({name,args}) + '\\n');
if (process.env.FAIL_STAGE === name) process.exit(37);
if (name === 'hdiutil' && previous.filter(row => row.name === name).length < Number(process.env.DMG_RETRIES || 0)) process.exit(38);
if (name === 'xcodebuild') fs.mkdirSync('build/release/Build/Products/Release/Secreteo.app/Contents', {recursive:true});
if (name === 'ditto') fs.cpSync(args[0], args[1], {recursive:true});
if (name === 'hdiutil') fs.writeFileSync(args.at(-1), 'synthetic disk image');
`;
function run({ fail = '', retries = 0, version = '1.2.3' } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'secreteo release timings '));
  roots.push(root);
  mkdirSync(join(root, 'scripts')); mkdirSync(join(root, 'bin'));
  copyFileSync(new URL('../../scripts/package-release.sh', import.meta.url), join(root, 'scripts/package-release.sh'));
  for (const name of ['fetch-sparkle.sh', 'sign-app.sh']) writeFileSync(join(root, 'scripts', name), stub, { mode: 0o755 });
  for (const name of ['xcodegen', 'xcodebuild', 'ditto', 'hdiutil', 'python3', 'sleep']) {
    writeFileSync(join(root, 'bin', name), stub, { mode: 0o755 });
  }
  const result = spawnSync('/bin/bash', ['scripts/package-release.sh', version, 'dryrun'], {
    cwd: root, encoding: 'utf8', env: { PATH: `${join(root, 'bin')}:${process.env.PATH}`, LC_ALL: 'C',
      DRYRUN_SPARKLE_PUBLIC_KEY: 'synthetic-public-key', FAIL_STAGE: fail, DMG_RETRIES: String(retries) },
  });
  let calls = [];
  try { calls = readFileSync(join(root, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse); }
  catch (error) { if (error.code !== 'ENOENT') throw error; }
  return { ...result, root, calls, output: result.stdout + result.stderr };
}
function timings(result) {
  return [...result.output.matchAll(/^PackageTiming version=1\.2\.3 phase=([a-z-]+) real=(\d+) status=(\d+)$/gm)]
    .map(([, phase, real, status]) => ({ phase, real: Number(real), status: Number(status) }));
}

test('packaging reports every stage and total without changing build or verification inputs', () => {
  const result = run();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(timings(result).map(row => row.phase).sort(), ['prepare', 'build', 'copy', 'sign', 'dmg', 'verify', 'total'].sort());
  assert.ok(timings(result).every(row => Number.isFinite(row.real) && row.real >= 0));
  assert.ok(timings(result).every(row => row.status === 0));
  assert.deepEqual(result.calls.map(row => row.name), ['fetch-sparkle.sh', 'xcodegen', 'xcodebuild', 'ditto', 'sign-app.sh', 'ditto', 'hdiutil', 'python3']);
  assert.deepEqual(result.calls.find(row => row.name === 'xcodebuild').args, [
    '-project', 'Secreteo.xcodeproj', '-scheme', 'Secreteo', '-configuration', 'Release',
    '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', 'build/release',
    '-skipPackagePluginValidation', '-quiet', '-showBuildTimingSummary', 'MARKETING_VERSION=1.2.3',
    'SPARKLE_PUBLIC_ED_KEY=synthetic-public-key', 'build',
  ]);
  assert.deepEqual(result.calls.find(row => row.name === 'sign-app.sh').args, ['build/release-stage/1.2.3/Secreteo.app', '-']);
  assert.deepEqual(result.calls.find(row => row.name === 'python3').args, ['scripts/verify_release.py', 'dist/Secreteo-1.2.3.dmg', '1.2.3', 'dryrun']);
  assert.match(readFileSync(join(result.root, 'dist/Secreteo-1.2.3.dmg.sha256'), 'utf8'), /^[a-f0-9]{64}  Secreteo-1\.2\.3\.dmg\n$/);
  assert.doesNotMatch(result.output, /synthetic-public-key|MARKETING_VERSION|SPARKLE_PUBLIC_ED_KEY/);
});

for (const [fail, phase] of [['fetch-sparkle.sh', 'prepare'], ['xcodegen', 'prepare'], ['xcodebuild', 'build'],
  ['ditto', 'copy'], ['sign-app.sh', 'sign'], ['python3', 'verify']]) {
  test(`${fail} failure keeps exit status, reports elapsed time and stops subsequent work`, () => {
    const result = run({ fail });
    assert.equal(result.status, 37, result.stderr);
    assert.equal(result.calls.at(-1).name, fail);
    assert.equal(timings(result).at(-1).phase, phase);
    assert.equal(timings(result).at(-1).status, 37);
    assert.doesNotMatch(result.output, /phase=total|Packaged dist/);
  });
}

test('disk-image retries remain bounded and all attempts belong to the same timing', () => {
  const result = run({ retries: 2 });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.calls.filter(row => row.name === 'hdiutil').length, 3);
  assert.equal(result.calls.filter(row => row.name === 'sleep').length, 2);
  assert.equal(timings(result).filter(row => row.phase === 'dmg').length, 1);
});

test('exhausted disk-image retries still fail without verification or a success total', () => {
  const result = run({ retries: 3 });
  assert.equal(result.status, 1);
  assert.equal(result.calls.filter(row => row.name === 'hdiutil').length, 3);
  assert.equal(result.calls.some(row => row.name === 'python3'), false);
  assert.equal(timings(result).at(-1).phase, 'dmg');
  assert.equal(timings(result).at(-1).status, 1);
  assert.doesNotMatch(result.output, /phase=total|Packaged dist/);
});

test('an invalid version is rejected before tools or timing records run', () => {
  const result = run({ version: '../unowned' });
  assert.equal(result.status, 64);
  assert.deepEqual(result.calls, []);
  assert.deepEqual(timings(result), []);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  test(`${signal} cannot publish successful timing for an interrupted active stage`, { timeout: 3000 }, async () => {
    const source = readFileSync(new URL('../../scripts/package-release.sh', import.meta.url), 'utf8');
    const timing = source.slice(source.indexOf('package_started='), source.indexOf('\nproject_setting()'));
    const child = spawn('/bin/bash', ['-c', `set -euo pipefail\nversion=1.2.3\n${timing}\nbegin_phase build\nprintf 'ready\\n'\n/bin/sleep 1\nfinish_phase 0\necho unexpected-success`], { detached: true });
    let stdout = '', stderr = '', timer;
    child.stdout.on('data', bytes => {
      stdout += bytes;
      if (!timer) timer = setTimeout(() => process.kill(-child.pid, signal), 20);
    });
    child.stderr.on('data', bytes => { stderr += bytes; });
    try {
      const result = await new Promise((resolve, reject) => {
        child.once('error', reject);
        child.once('close', (code, endedBySignal) => resolve({ code, endedBySignal }));
      });
      assert.ok(result.code !== 0 || result.endedBySignal !== null);
      assert.doesNotMatch(stdout, /unexpected-success/);
      assert.doesNotMatch(stderr, /phase=build real=\d+ status=0/);
    } finally {
      clearTimeout(timer);
      if (child.exitCode === null && child.signalCode === null) process.kill(-child.pid, 'SIGKILL');
    }
  });
}
