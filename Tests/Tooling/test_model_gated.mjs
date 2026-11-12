import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CASES, GateInputError, admit, lanes, runGate } from '../../scripts/model_gated.mjs';

const script = fileURLToPath(new URL('../../scripts/model_gated.mjs', import.meta.url));
const makefile = readFileSync(new URL('../../Makefile', import.meta.url), 'utf8');
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

function fakeSpawn({ outcome = 'observed', status = 0, receipt } = {}) {
  const calls = [];
  const spawn = (command, args, options) => {
    calls.push({ command, args, options });
    if (command.endsWith('xctest')) {
      const output = options.env.SECRETEO_SPEECH_GATE_OUTPUT;
      if (receipt !== null) {
        writeFileSync(output, JSON.stringify(receipt ?? { kind: 'dictation-speech-gate-observation', schemaVersion: 1,
          optimized: true, cells: cells.map(caseID => ({ caseID })) }));
      }
      return { status };
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
    [['parakeet-v3', true], ['parakeet-ultra', true], ['silero', true]]);
  assert.equal(JSON.parse(readFileSync(join(admitted.output, 'summary.json'), 'utf8')).lanes.length, 3);
  for (const call of calls) {
    assert.deepEqual(Object.keys(call.options.env).filter(key => !key.startsWith('SECRETEO_SPEECH_GATE_')).sort(),
      ['HOME', 'LANG', 'PATH'], 'children get a minimal environment');
    assert.equal(call.options.stdio[2], 'ignore', 'child diagnostics are never kept');
  }
});

test('a launcher that exits zero without an observation fails its lane', t => {
  const { environment, home } = scratch(t);
  const results = runGate(admit(environment, home), tools(fakeSpawn({ outcome: 'failed' }).spawn));
  assert.deepEqual(results.filter(result => !result.passed).map(result => result.lane), ['parakeet-v3', 'parakeet-ultra']);
});

test('a nonzero exit fails every lane', t => {
  const { environment, home } = scratch(t);
  const results = runGate(admit(environment, home), tools(fakeSpawn({ status: 2 }).spawn));
  assert.ok(results.every(result => !result.passed && result.failure === 'exit 2'));
});

test('a speech gate that skipped leaves no receipt and fails', t => {
  const { environment, home } = scratch(t);
  const silero = runGate(admit(environment, home), tools(fakeSpawn({ receipt: null }).spawn)).at(-1);
  assert.equal(silero.passed, false);
  assert.match(silero.failure, /no receipt/);
});

for (const [name, receipt, reason] of [
  ['a Debug receipt', { kind: 'dictation-speech-gate-observation', schemaVersion: 1, optimized: false, cells: cells.map(caseID => ({ caseID })) }, /Debug/],
  ['a partial receipt', { kind: 'dictation-speech-gate-observation', schemaVersion: 1, optimized: true, cells: [{ caseID: cells[0] }] }, /every cell/],
  ['another kind', { kind: 'other', schemaVersion: 1, optimized: true, cells: [] }, /wrong kind/],
]) {
  test(`the speech gate refuses ${name}`, t => {
    const { environment, home } = scratch(t);
    const silero = runGate(admit(environment, home), tools(fakeSpawn({ receipt }).spawn)).at(-1);
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
});

test('the gate never opens an installed app store', t => {
  const { environment, home } = scratch(t);
  const support = join(home, 'Library', 'Application Support');
  for (const store of ['com.johnny4young.local-models', 'Portavoz/Models', 'FluidAudio/Models']) {
    mkdirSync(join(support, store), { recursive: true });
    assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: join(support, store) }, home), /installed app/);
  }
  assert.throws(() => admit({ ...environment, SECRETEO_MODEL_GATED_MODELS: support }, home), /installed app/);
});

test('the lanes cover v3, Ultra and Silero on the store they were given', t => {
  const { environment, home } = scratch(t);
  const admitted = admit(environment, home);
  const { models } = admitted;
  const selected = lanes(admitted, '/b', '/x');
  assert.deepEqual(selected.map(lane => lane.name), ['parakeet-v3', 'parakeet-ultra', 'silero']);
  for (const lane of selected.slice(0, 2)) {
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

test('make test-model-gated runs this gate', () => {
  assert.match(makefile, /^test-model-gated:\n\tnode scripts\/model_gated\.mjs$/m);
  assert.match(makefile, /^\.PHONY:.*\btest-model-gated\b/m);
});
