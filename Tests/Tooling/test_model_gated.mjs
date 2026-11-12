import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CASES, GateInputError, MEMORY_BUDGET_BYTES, admit, lanes, runGate } from '../../scripts/model_gated.mjs';

const script = fileURLToPath(new URL('../../scripts/model_gated.mjs', import.meta.url));
const makefile = readFileSync(new URL('../../Makefile', import.meta.url), 'utf8');
const decisions = readFileSync(new URL('../../docs/DECISIONS.md', import.meta.url), 'utf8');
const cells = ['en-payment-negation.clean', 'non-speech-silence.clean'];

function scratch(t) {
  const root = mkdtempSync(join(tmpdir(), 'model-gated-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const home = join(root, 'home');
  const audio = join(root, 'audio');
  const models = join(root, 'models');
  mkdirSync(join(home, 'Library', 'Application Support', 'com.johnny4young.local-models'), { recursive: true });
  mkdirSync(audio);
  mkdirSync(models);
  writeFileSync(join(audio, 'manifest.json'), JSON.stringify({ entries: cells.map(caseID => ({ caseID })) }));
  const environment = { SECRETEO_MODEL_GATED_AUDIO: audio, SECRETEO_MODEL_GATED_MODELS: models,
    SECRETEO_MODEL_GATED_OUTPUT: join(root, 'out') };
  return { root, home, audio, models, environment };
}

function goodReceipt(audio) {
  const manifestSHA256 = createHash('sha256').update(readFileSync(join(audio, 'manifest.json'))).digest('hex');
  return { kind: 'dictation-speech-gate-observation', schemaVersion: 1, optimized: true, manifestSHA256,
    modelRevision: 'pinned', cells: cells.map(caseID => ({ caseID })) };
}

const footprint = (endingBytes, peakObservedBytes = endingBytes + 1) => ({ footprint: { endingBytes, peakObservedBytes } });

function fakeSpawn({ outcome = 'observed', status = 0, receipt, resting = [300_000_000, 310_000_000] } = {}) {
  const calls = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, options });
    if (command.endsWith('xctest')) {
      const output = options.env.SECRETEO_SPEECH_GATE_OUTPUT;
      const value = typeof receipt === 'function' ? receipt(goodReceipt(options.env.SECRETEO_SPEECH_GATE_AUDIO)) : receipt;
      if (value !== null) {
        writeFileSync(output, JSON.stringify(value ?? goodReceipt(options.env.SECRETEO_SPEECH_GATE_AUDIO)));
      }
      return { status };
    }
    if (args.includes('--controller')) {
      const output = args[args.indexOf('--output') + 1];
      mkdirSync(output);
      writeFileSync(join(output, 'model.json'), JSON.stringify({ cells: resting.map(bytes => footprint(bytes)) }));
    }
    return { status, stdout: JSON.stringify({ outcome }) };
  };
  return { spawn, calls };
}

const tools = spawn => ({ bundle: '/scratch/DictationSessionTests.xctest', xctest: '/usr/bin/xctest', spawn });

test('every lane passing makes the gate pass and writes a summary', t => {
  const { environment, home } = scratch(t);
  const admitted = admit(environment, home);
  const { spawn, calls } = fakeSpawn();
  const results = runGate(admitted, tools(spawn));
  assert.deepEqual(results.map(result => [result.lane, result.passed]),
    [['parakeet-v3', true], ['parakeet-ultra', true], ['silero', true], ['memory', true]]);
  assert.equal(JSON.parse(readFileSync(join(admitted.output, 'summary.json'), 'utf8')).lanes.length, 4);
  assert.deepEqual(results.at(-1).memory, { budgetBytes: MEMORY_BUDGET_BYTES, highestRestingBytes: 310_000_000,
    restingBytes: [300_000_000, 310_000_000], highestPeakBytes: 310_000_001 });
  const launchers = ['HOME', 'LANG', 'PATH'];
  const speechGate = [...launchers, 'SECRETEO_SPEECH_GATE_AUDIO', 'SECRETEO_SPEECH_GATE_MODELS', 'SECRETEO_SPEECH_GATE_OUTPUT'].sort();
  for (const call of calls) {
    assert.deepEqual(Object.keys(call.options.env).sort(), call.command.endsWith('xctest') ? speechGate : launchers,
      'children get a minimal environment, and never an install switch');
    assert.equal(call.options.stdio[2], 'ignore', 'child diagnostics are never kept');
  }
});

test('a launcher that exits zero without an observation fails its lane', t => {
  const { environment, home } = scratch(t);
  const results = runGate(admit(environment, home), tools(fakeSpawn({ outcome: 'failed' }).spawn));
  assert.deepEqual(results.filter(result => !result.passed).map(result => result.lane), ['parakeet-v3', 'parakeet-ultra', 'memory']);
});

test('a nonzero exit fails every lane', t => {
  const { environment, home } = scratch(t);
  const results = runGate(admit(environment, home), tools(fakeSpawn({ status: 2 }).spawn));
  assert.ok(results.every(result => !result.passed && result.failure === 'exit 2'));
});

test('a speech gate that skipped leaves no receipt and fails', t => {
  const { environment, home } = scratch(t);
  const silero = runGate(admit(environment, home), tools(fakeSpawn({ receipt: null }).spawn)).find(result => result.lane === 'silero');
  assert.equal(silero.passed, false);
  assert.match(silero.failure, /no receipt/);
});

for (const [name, receipt, reason] of [
  ['a Debug receipt', good => ({ ...good, optimized: false }), /Debug/],
  ['a partial receipt', good => ({ ...good, cells: [{ caseID: cells[0] }] }), /every cell/],
  ['another kind', good => ({ ...good, kind: 'other' }), /wrong kind/],
  ['another manifest', good => ({ ...good, manifestSHA256: '0'.repeat(64) }), /another audio manifest/],
  ['no model revision', good => ({ ...good, modelRevision: '' }), /model revision/],
]) {
  test(`the speech gate refuses ${name}`, t => {
    const { environment, home } = scratch(t);
    const silero = runGate(admit(environment, home), tools(fakeSpawn({ receipt }).spawn)).find(result => result.lane === 'silero');
    assert.equal(silero.passed, false);
    assert.match(silero.failure, reason);
  });
}

test('the gate refuses missing, relative and reused paths', t => {
  const { environment, home, root } = scratch(t);
  for (const key of Object.keys(environment)) {
    assert.throws(() => admit({ ...environment, [key]: undefined }, home), GateInputError);
    assert.throws(() => admit({ ...environment, [key]: 'relative/path' }, home), GateInputError);
  }
  mkdirSync(join(root, 'out'));
  assert.throws(() => admit(environment, home), /must not exist/);
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_OUTPUT: join(environment.SECRETEO_MODEL_GATED_MODELS, 'out') }, home),
    /separate/);
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_OUTPUT: join(environment.SECRETEO_MODEL_GATED_AUDIO, 'out') }, home),
    /separate/);
});

test('the gate never opens an installed app store', t => {
  const { environment, home } = scratch(t);
  const support = join(home, 'Library', 'Application Support');
  for (const store of ['com.johnny4young.local-models', 'Portavoz/Models', 'FluidAudio/Models']) {
    mkdirSync(join(support, store), { recursive: true });
    assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: join(support, store) }, home), /installed app/);
  }
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: support }, home), /installed app/);
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: '/' }, home), /installed app/);
  const shared = join(support, 'com.johnny4young.local-models');
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_OUTPUT: join(shared, 'out') }, home), /installed app/);
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: shared.toUpperCase() }, home), /installed app/);
  const link = join(environment.SECRETEO_MODEL_GATED_AUDIO, '..', 'link');
  symlinkSync(shared, link);
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: link }, home), /installed app/);
  mkdirSync(join(home, 'Library', 'Containers', 'some.app'), { recursive: true });
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: join(home, 'Library', 'Containers', 'some.app') }, home),
    /installed app/);
});

test('an overridden HOME does not move the guard off the real stores', t => {
  const { environment, home } = scratch(t);
  // Only resolves the path; nothing in the real store is read.
  const real = join(userInfo().homedir, 'Library', 'Application Support', 'com.johnny4young.local-models', 'never-created');
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    `import { admit } from ${JSON.stringify(script)};
     try { admit(${JSON.stringify({ ...environment, SECRETEO_MODEL_GATED_MODELS: real })}); process.exit(0); }
     catch (error) { console.error(error.message); process.exit(3); }`], { env: { PATH: process.env.PATH, HOME: home }, encoding: 'utf8' });
  assert.equal(result.status, 3);
  assert.match(result.stderr, /installed app/);
});

test('launchers get room for a full report on stdout', t => {
  const { environment, home } = scratch(t);
  const spawn = fakeSpawn().spawn;
  const results = runGate(admit(environment, home), tools((command, args, options) => {
    const result = spawn(command, args, options);
    assert.ok(options.maxBuffer >= 16 * 1024 * 1024);
    return result;
  }));
  assert.ok(results.every(result => result.passed));
});

test('a launcher that cannot start fails with its error code', t => {
  const { environment, home } = scratch(t);
  const results = runGate(admit(environment, home), tools(() => ({ status: null, signal: null, error: { code: 'ENOENT' } })));
  assert.ok(results.every(result => result.failure === 'exit ENOENT'));
});

test('the lanes cover v3, Ultra and Silero on the store they were given', t => {
  const { environment, home } = scratch(t);
  const admitted = admit(environment, home);
  const { models } = admitted;
  const selected = lanes(admitted, '/b', '/x');
  assert.deepEqual(selected.map(lane => lane.name), ['parakeet-v3', 'parakeet-ultra', 'silero', 'memory']);
  assert.ok(selected[3].command.includes('--controller'), 'memory comes from the controller lane');
  for (const lane of [...selected.slice(0, 2), selected[3]]) {
    assert.equal(lane.command[lane.command.indexOf('--models') + 1], models);
    assert.deepEqual(lane.command.filter((_, index) => lane.command[index - 1] === '--case'), CASES);
  }
  assert.equal(selected[2].environment.SECRETEO_SPEECH_GATE_MODELS, models);
  assert.equal(selected[2].environment.SECRETEO_SPEECH_GATE_INSTALL, undefined, 'a gate run never downloads');
});

test('the command refuses to run without a named scratch store', () => {
  const result = spawnSync(process.execPath, [script], { env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(result.status, 64);
  assert.match(result.stderr, /SECRETEO_MODEL_GATED_AUDIO/);
});

test('make test-model-gated runs this gate and keeps its exit code', () => {
  assert.match(makefile, /^\.PHONY:.*\btest-model-gated\b/m);
  const result = spawnSync('make', ['-s', 'test-model-gated'], {
    cwd: fileURLToPath(new URL('../..', import.meta.url)), env: { PATH: process.env.PATH }, encoding: 'utf8' });
  assert.equal(result.status, 2, 'make reports a failed recipe');
  assert.match(result.stderr, /SECRETEO_MODEL_GATED_AUDIO/);
  assert.match(result.stderr, /Error 64/, 'the gate exits 64 for missing input');
});

test('a resting footprint over the budget fails the memory lane', t => {
  const { environment, home } = scratch(t);
  const memory = runGate(admit(environment, home), tools(fakeSpawn({ resting: [300_000_000, MEMORY_BUDGET_BYTES + 1] }).spawn)).at(-1);
  assert.equal(memory.passed, false);
  assert.match(memory.failure, /over the 471859200-byte budget/);
  assert.equal(memory.memory.highestRestingBytes, MEMORY_BUDGET_BYTES + 1);
});

test('the memory lane accepts a reading exactly at the budget', t => {
  const { environment, home } = scratch(t);
  const memory = runGate(admit(environment, home), tools(fakeSpawn({ resting: [MEMORY_BUDGET_BYTES, 1] }).spawn)).at(-1);
  assert.equal(memory.passed, true);
});

test('one footprint reading is not a measurement', t => {
  const { environment, home } = scratch(t);
  const memory = runGate(admit(environment, home), tools(fakeSpawn({ resting: [300_000_000] }).spawn)).at(-1);
  assert.equal(memory.passed, false);
  assert.match(memory.failure, /fewer than two/);
});

test('the budget is the number written in D26', () => {
  const section = decisions.slice(decisions.indexOf('## D26.'));
  const written = Number(/\(([\d,]+) bytes\)/.exec(section)?.[1].replaceAll(',', ''));
  assert.equal(written, MEMORY_BUDGET_BYTES);
});
