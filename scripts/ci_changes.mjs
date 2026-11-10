#!/usr/bin/env node
import { readFileSync, realpathSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const DOCS_ONLY = ['docs/*', '*.md', 'LICENSE', 'site/*', '.github/ISSUE_TEMPLATE/*'];
const CI = ['.github/workflows/ci.yml', 'scripts/ci_changes.mjs', 'scripts/ci_gate.mjs', 'scripts/ci_reuse_gate.py',
  'scripts/ci_changes.py', 'scripts/ci_gate.py'];
const DELIVERY = ['Sources/DictationSession/Delivery/*', 'Sources/DictationSession/Triggers/*',
  'Tests/DictationSessionTests/Delivery/*', 'Tests/DictationSessionTests/Triggers/*',
  'spikes/tcc-adhoc/*', 'scripts/run-signed-handoff.sh', ...CI];
const RELEASE = ['scripts/package-release.sh', 'scripts/sign-app.sh', 'scripts/release-dryrun.sh',
  'scripts/generate-appcast.sh', 'scripts/verify_release.py', 'scripts/verify_appcast.py',
  'scripts/verify-ed-signature.swift', 'scripts/smoke-launch.sh', 'scripts/enable-gatekeeper.sh',
  'scripts/fetch-sparkle.sh', 'scripts/throwaway-sparkle-key.swift', 'project.yml',
  'Apps/Secreteo/Info.plist', 'Apps/Secreteo/Secreteo.entitlements',
  'Apps/Secreteo/SecreteoMain.swift', 'Apps/Secreteo/SparkleUpdater.swift', ...CI];

function matches(path, patterns) {
  // Current patterns have at most one *, which also matches separators and newlines.
  return patterns.some(pattern => {
    const star = pattern.indexOf('*');
    if (star < 0) return path === pattern;
    return path.length >= pattern.length - 1 && path.startsWith(pattern.slice(0, star))
      && path.endsWith(pattern.slice(star + 1));
  });
}

export function classify(paths) {
  if (!paths.length) return { code: true, delivery: true, release: true };
  return {
    code: !paths.every(path => matches(path, DOCS_ONLY)),
    delivery: paths.some(path => matches(path, DELIVERY)),
    release: paths.some(path => matches(path, RELEASE)),
  };
}

export function main(args, input = '') {
  // Preserve universal newlines and the existing strip set; BOM is not whitespace.
  const whitespace = /^[\t-\r\u001c-\u0020\u0085\p{Zs}\u2028\u2029]+|[\t-\r\u001c-\u0020\u0085\p{Zs}\u2028\u2029]+$/gu;
  const paths = args.length ? args : input.split(/\r\n|\r|\n/).map(line => line.replace(whitespace, '')).filter(Boolean);
  return Object.entries(classify(paths)).map(([name, value]) => `${name}=${value}\n`).join('');
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); }
  catch { return false; }
}

if (isMain()) {
  try {
    const args = process.argv.slice(2);
    const input = args.length ? '' : new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(readFileSync(0));
    process.stdout.write(main(args, input));
  } catch {
    console.error('Could not classify changed paths.');
    process.exitCode = 1;
  }
}
