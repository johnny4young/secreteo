#!/usr/bin/env node
import { readdirSync, readFileSync, realpathSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const whitespace = '[\\t-\\r\\x1c-\\x20\\x85\\xa0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]';
const word = '[\\p{L}\\p{N}_]';
const classPattern = new RegExp(`(?:^|(?<=\n))(?:final )?class (${word}+)${whitespace}*:`, 'gu');
const testPattern = new RegExp(`(?:^|(?<=\n))${whitespace}*func (test${word}*)\\(`, 'gu');

// Python orders Unicode code points, not UTF-16 units or the host locale.
function compare(left, right) {
  const a = Array.from(left, c => c.codePointAt(0));
  const b = Array.from(right, c => c.codePointAt(0));
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

export function testClasses(directory = join(root, 'Tests/SecreteoUITests')) {
  let paths;
  try { paths = readdirSync(directory).filter(name => name.endsWith('.swift')).sort(compare); }
  catch (error) { if (error.code === 'ENOENT') return new Map(); throw error; }
  const found = new Map();
  for (const path of paths) {
    const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true })
      .decode(readFileSync(join(directory, path))).replace(/\r\n?/g, '\n');
    const tests = [...text.matchAll(testPattern)].length;
    const names = [...text.matchAll(classPattern)].map(match => match[1]);
    if (tests && names.length !== 1) throw new Error(`${path}: keep one test class per file to shard it`);
    if (tests) found.set(names[0], tests);
  }
  return found;
}

export function shards(found, count) {
  if (!Number.isSafeInteger(count) || count < 1) throw new Error('count must be a positive safe integer');
  const bins = Array.from({ length: count }, () => ({ size: 0, names: [] }));
  const entries = [...found].sort(([a, x], [b, y]) => y - x || compare(a, b));
  for (const [name, tests] of entries) {
    const smallest = bins.reduce((a, b) => a.size <= b.size ? a : b);
    smallest.size += tests;
    smallest.names.push(name);
  }
  return bins.map(bin => bin.names.sort(compare));
}

export function main(args) {
  const parse = value => {
    if (typeof value !== 'string' || !/^[0-9]+$/.test(value)) throw new Error('index and count must be integers');
    const number = Number(value);
    if (!Number.isSafeInteger(number)) throw new Error('index and count must be safe integers');
    return number;
  };
  const index = parse(args[0]);
  const count = parse(args[1]);
  if (!(1 <= index && index <= count)) throw new Error('index must be between 1 and count');
  return `${shards(testClasses(), count)[index - 1].join('\n')}\n`;
}

function isMain() {
  const entry = process.argv[1];
  if (!entry || entry === '-') return false;
  try { return realpathSync(entry) === fileURLToPath(import.meta.url); }
  catch { return false; }
}

if (isMain()) {
  try { process.stdout.write(main(process.argv.slice(2))); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
