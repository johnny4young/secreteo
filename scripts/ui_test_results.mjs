import { readFileSync, copyFileSync, chmodSync, statSync, realpathSync } from 'node:fs';
import { resolve, basename, join } from 'node:path';
import { fileURLToPath } from 'node:url';

function json(input) {
  return JSON.parse(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(input));
}
function object(value) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('Expected a JSON object');
  return value;
}
function list(value) {
  if (!Array.isArray(value)) throw new Error('Expected a JSON array');
  return value;
}
function string(value) {
  if (typeof value !== 'string') throw new Error('Expected a JSON string');
  // Python UTF-8 output and filesystem paths reject unpaired surrogates.
  if (!value.isWellFormed()) throw new Error('Invalid Unicode surrogate');
  return value;
}
export function summary(input, write) {
  const document = object(json(input));
  for (const failure of list(document.testFailures === undefined ? [] : document.testFailures)) {
    object(failure);
    write(`${string(failure.testName)}: ${string(failure.failureText)}\n`);
  }
}
export function attachments(source, target) {
  const manifest = list(json(readFileSync(resolve(source, 'manifest.json'))));
  for (const test of manifest) {
    object(test);
    for (const attachment of list(test.attachments === undefined ? [] : test.attachments)) {
      object(attachment);
      const name = string(attachment.suggestedHumanReadableName === undefined ? '' : attachment.suggestedHumanReadableName);
      if (!name.startsWith('pr-')) continue;
      const from = resolve(source, string(attachment.exportedFileName));
      let to = resolve(target, `${name.split('_')[0]}.png`);
      let destination;
      try { destination = statSync(to); } catch (error) { if (error.code !== 'ENOENT') throw error; }
      if (destination?.isDirectory()) {
        to = join(to, basename(from));
        try { destination = statSync(to); } catch (error) { if (error.code !== 'ENOENT') throw error; destination = undefined; }
      }
      const original = statSync(from);
      if (!original.isFile()) throw new Error('Attachment must be a regular file');
      if (destination && original.dev === destination.dev && original.ino === destination.ino) throw new Error('Source and destination are the same file');
      copyFileSync(from, to);
      chmodSync(to, original.mode & 0o7777);
    }
  }
}
function isMain() {
  try { return process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url); }
  catch { return false; }
}
if (isMain()) {
  try {
    const [command, source, target, ...extra] = process.argv.slice(2);
    if (command === 'summary' && source === undefined) summary(readFileSync(0), line => process.stdout.write(line));
    else if (command === 'attachments' && source !== undefined && target !== undefined && !extra.length) attachments(source, target);
    else throw new Error('Usage: node scripts/ui_test_results.mjs summary | attachments SOURCE TARGET');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
