#!/usr/bin/env node
// Runs the real-model lanes against a named scratch store and fails unless each one
// produces a valid observation. Child output is discarded: XCTest can dump its environment.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { userInfo } from 'node:os';
import { basename, dirname, isAbsolute, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const CASES = ['en-payment-negation.clean', 'es-payment-negation.clean', 'mixed-review.clean', 'non-speech-silence.clean'];
const SPEECH_GATE = 'DictationSessionTests.DictationSpeechGateCorpusTests/testSpeechGateOverEveryPublicCell';
const SPEECH_GATE_KIND = 'dictation-speech-gate-observation';
// D26 in docs/DECISIONS.md: footprint with Parakeet v3 resident and no dictation running.
export const MEMORY_BUDGET_BYTES = 471_859_200;

export class GateInputError extends Error {}

const realish = path => {
  let current = resolve(path);
  const rest = [];
  while (!existsSync(current)) {
    rest.unshift(basename(current));
    const parent = dirname(current);
    if (parent === current) break;
    current = parent;
  }
  return join(realpathSync.native(current), ...rest);
};
// APFS is case-insensitive by default, so a case variant names the same folder.
const inside = (path, root) => {
  const [p, r] = [path.toLowerCase(), root.toLowerCase()];
  return p === r || r === sep || p.startsWith(r + sep);
};

// Stores and caches that belong to installed apps, sandboxed copies included; the gate must never open them.
export function protectedRoots(home) {
  const library = join(home, 'Library');
  const support = join(library, 'Application Support');
  return [join(support, 'com.johnny4young.local-models'), join(support, 'Portavoz'),
    join(support, 'Portavoz Release'), join(support, 'FluidAudio'), join(support, 'com.johnny4young.secreteo'),
    join(support, 'com.johnny4young.secreteo.dev'), join(library, 'Containers'), join(library, 'Group Containers')]
    .map(realish);
}

// The account's home, not $HOME, so an overridden HOME cannot move the guard away from the real stores.
export function admit(environment, home = userInfo().homedir) {
  const named = key => {
    const value = environment[key];
    if (typeof value !== 'string' || !isAbsolute(value)) throw new GateInputError(`${key} must be an absolute path`);
    return realish(value);
  };
  const audio = named('SECRETEO_MODEL_GATED_AUDIO');
  const models = named('SECRETEO_MODEL_GATED_MODELS');
  const output = named('SECRETEO_MODEL_GATED_OUTPUT');
  for (const root of protectedRoots(home)) {
    for (const [key, path] of [['SECRETEO_MODEL_GATED_MODELS', models], ['SECRETEO_MODEL_GATED_OUTPUT', output]]) {
      if (inside(path, root) || inside(root, path)) throw new GateInputError(`${key} overlaps an installed app's store`);
    }
  }
  if (!existsSync(join(audio, 'manifest.json'))) throw new GateInputError('SECRETEO_MODEL_GATED_AUDIO has no manifest.json');
  if (!existsSync(models)) throw new GateInputError('SECRETEO_MODEL_GATED_MODELS does not exist');
  if (existsSync(output)) throw new GateInputError('SECRETEO_MODEL_GATED_OUTPUT must not exist yet');
  if (inside(output, models) || inside(models, output) || inside(output, audio)) {
    throw new GateInputError('the output must be separate from the audio and the store');
  }
  return { audio, models, output };
}

function parsed(stdout) {
  try { return JSON.parse(stdout); } catch { return null; }
}

const exitReason = result => `exit ${result.status ?? result.signal ?? result.error?.code}`;

export function launcherVerdict(result) {
  if (result.status !== 0) return exitReason(result);
  const outcome = parsed(result.stdout)?.outcome;
  return outcome === 'observed' ? null : `outcome ${JSON.stringify(outcome ?? null)}`;
}

export function speechGateVerdict(result, receiptPath, manifestPath) {
  if (result.status !== 0) return exitReason(result);
  if (!existsSync(receiptPath)) return 'no receipt: the lane skipped or never finished';
  const receipt = parsed(readFileSync(receiptPath, 'utf8'));
  const manifest = readFileSync(manifestPath);
  const entries = parsed(manifest.toString('utf8'))?.entries;
  if (receipt?.kind !== SPEECH_GATE_KIND || receipt.schemaVersion !== 1) return 'receipt has the wrong kind';
  if (receipt.optimized !== true) return 'receipt came from a Debug build';
  if (receipt.manifestSHA256 !== createHash('sha256').update(manifest).digest('hex')) return 'receipt is for another audio manifest';
  if (typeof receipt.modelRevision !== 'string' || !receipt.modelRevision) return 'receipt names no model revision';
  const expected = Array.isArray(entries) ? entries.map(entry => entry?.caseID).sort() : null;
  const observed = Array.isArray(receipt.cells) ? receipt.cells.map(cell => cell?.caseID).sort() : null;
  if (!expected?.length || JSON.stringify(expected) !== JSON.stringify(observed)) return 'receipt does not cover every cell';
  return null;
}

export function memoryVerdict(result, receiptPath) {
  const launcher = launcherVerdict(result);
  if (launcher) return { failure: launcher };
  const cells = existsSync(receiptPath) ? parsed(readFileSync(receiptPath, 'utf8'))?.cells : null;
  const resting = Array.isArray(cells) ? cells.map(cell => cell?.footprint?.endingBytes) : [];
  if (resting.length < 2 || !resting.every(Number.isSafeInteger)) return { failure: 'fewer than two footprint samples' };
  const memory = { budgetBytes: MEMORY_BUDGET_BYTES, highestRestingBytes: Math.max(...resting), restingBytes: resting,
    highestPeakBytes: Math.max(...cells.map(cell => cell.footprint.peakObservedBytes)) };
  return memory.highestRestingBytes > MEMORY_BUDGET_BYTES
    ? { failure: `resting footprint ${memory.highestRestingBytes} bytes is over the ${MEMORY_BUDGET_BYTES}-byte budget`, memory }
    : { memory };
}

export function lanes({ audio, models, output }, bundle, xctest) {
  const shared = ['--audio-root', audio, '--models', models, '--test-bundle', bundle, '--xctest', xctest];
  const cases = CASES.flatMap(id => ['--case', id]);
  return [
    { name: 'parakeet-v3', kind: 'launcher',
      command: ['python3', '-I', join(ROOT, 'scripts/run_dictation_model_baseline.py'), ...shared, ...cases,
        '--output', join(output, 'parakeet-v3')] },
    { name: 'parakeet-ultra', kind: 'launcher',
      command: ['python3', '-I', join(ROOT, 'scripts/run_dictation_model_comparison.py'), ...shared, ...cases,
        '--output', join(output, 'parakeet-ultra')] },
    { name: 'silero', kind: 'speech-gate', receipt: join(output, 'silero.json'),
      command: [xctest, '-XCTest', SPEECH_GATE, bundle],
      environment: { SECRETEO_SPEECH_GATE_AUDIO: audio, SECRETEO_SPEECH_GATE_MODELS: models,
        SECRETEO_SPEECH_GATE_OUTPUT: join(output, 'silero.json') } },
    { name: 'memory', kind: 'memory', receipt: join(output, 'controller', 'model.json'),
      command: ['python3', '-I', join(ROOT, 'scripts/run_dictation_model_baseline.py'), '--controller', ...shared, ...cases,
        '--output', join(output, 'controller')] },
  ];
}

const minimalEnvironment = extra => ({ HOME: userInfo().homedir, PATH: '/usr/bin:/bin:/usr/sbin:/sbin', LANG: 'en_US.UTF-8', ...extra });

export function runGate(admitted, { bundle, xctest, spawn = spawnSync }) {
  mkdirSync(admitted.output, { recursive: false, mode: 0o700 });
  const results = [];
  for (const lane of lanes(admitted, bundle, xctest)) {
    const [command, ...args] = lane.command;
    const result = spawn(command, args, {
      cwd: ROOT, env: minimalEnvironment(lane.environment), encoding: 'utf8',
      stdio: ['ignore', lane.kind === 'speech-gate' ? 'ignore' : 'pipe', 'ignore'], timeout: 4 * 3600 * 1000,
      maxBuffer: 64 * 1024 * 1024,
    });
    const { failure = null, memory } = lane.kind === 'memory' ? memoryVerdict(result, lane.receipt)
      : { failure: lane.kind === 'launcher' ? launcherVerdict(result)
        : speechGateVerdict(result, lane.receipt, join(admitted.audio, 'manifest.json')) };
    results.push({ lane: lane.name, passed: failure === null, ...(failure ? { failure } : {}), ...(memory ? { memory } : {}) });
  }
  writeFileSync(join(admitted.output, 'summary.json'), `${JSON.stringify({ lanes: results }, null, 2)}\n`, { mode: 0o600 });
  return results;
}

function build(spawn = spawnSync) {
  const options = { cwd: ROOT, stdio: ['ignore', 'ignore', 'inherit'] };
  const built = spawn('swift', ['build', '-c', 'release', '--build-tests', '-Xswiftc', '-enable-testing',
    '-Xswiftc', '-warnings-as-errors'], options);
  if (built.status !== 0) throw new Error('release test build failed');
  const binPath = spawn('swift', ['build', '-c', 'release', '--show-bin-path'], { cwd: ROOT, encoding: 'utf8' });
  const xctest = spawn('xcrun', ['--find', 'xctest'], { encoding: 'utf8' });
  if (binPath.status !== 0 || xctest.status !== 0) throw new Error('could not locate the test bundle or xctest');
  return { bundle: join(binPath.stdout.trim(), 'DictationSessionTests.xctest'), xctest: xctest.stdout.trim() };
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); } catch { return false; }
}

if (isMain()) {
  try {
    const admitted = admit(process.env);
    const results = runGate(admitted, build());
    for (const { lane, passed, failure, memory } of results) {
      const detail = failure ?? (memory ? `highest resting ${memory.highestRestingBytes} of ${memory.budgetBytes} bytes` : '');
      console.log(`${passed ? 'PASS' : 'FAIL'} ${lane}${detail ? `: ${detail}` : ''}`);
    }
    console.log(`Receipts in ${admitted.output}`);
    if (!results.every(result => result.passed)) process.exitCode = 1;
  } catch (error) {
    console.error(`test-model-gated: ${error.message}`);
    process.exitCode = error instanceof GateInputError ? 64 : 1;
  }
}
