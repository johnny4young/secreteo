import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { readSwiftSources, readText } from './swift_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const MEMBERWISE = /(?<![\p{L}\p{N}_])DictationSessionDependencies(?:\.init)?\(/gu;
const LIVE = /(?:(?<![\p{L}\p{N}_])DictationSessionDependencies)?\.live\(services:/gu;

function swiftFiles() {
  return readSwiftSources(REPO, ['Tests']);
}

function callEnd(text, opening) {
  let depth = 0;
  for (let index = opening; index < text.length; index++) {
    if (text[index] === '(') depth++;
    if (text[index] === ')') depth--;
    if (depth === 0) return index + 1;
  }
  return text.length;
}

function offenders(files) {
  const found = [];
  for (const [name, text] of files) {
    const line = offset => text.slice(0, offset).split('\n').length;
    for (const match of text.matchAll(MEMBERWISE)) {
      const opening = match.index + match[0].length - 1;
      if (!/(?<![\p{L}\p{N}_])waitForStopTail:/u.test(text.slice(opening, callEnd(text, opening)))) found.push(`${name}:${line(match.index)}`);
    }
    for (const match of text.matchAll(LIVE)) {
      // Reading one member is fine; retaining the live value uses the real tail.
      if (text[callEnd(text, text.indexOf('(', match.index))] !== '.') found.push(`${name}:${line(match.index)}`);
    }
  }
  return found;
}

test('hand-built dependencies choose their stop tail', () => {
  assert.deepEqual(offenders(swiftFiles()), [], 'pass waitForStopTail, or build through the fixture');
});

test('the check catches what it guards', () => {
  const caught = [
    ['DictationSessionDependencies(a: { f(x) }, b: 1)', true],
    ['DictationSessionDependencies.init(a: 1)', true],
    ['DictationSessionDependencies(a: 1, waitForStopTail: t, b: 2)', false],
    ['DictationSessionDependencies(a: 1)\nother.waitForStopTail = t', true],
    ['let d: DictationSessionDependencies = .live(services: s, beginCapture: { {} })', true],
    ['toggle(using: DictationSessionDependencies.live(services: s, beginCapture: { {} }))', true],
    ['DictationSessionDependencies.live(services: s, beginCapture: { {} }).waitForStopTail', false],
    ['feature.makeDictationSessionDependencies()', false],
  ];
  for (const [text, expected] of caught) assert.equal(offenders([['a.swift', text]]).length > 0, expected, text);
});

test('a Unicode word character before the tail label is not a boundary', () => {
  assert.deepEqual(offenders([['a.swift', 'DictationSessionDependencies(a: "éwaitForStopTail:")']]), ['a.swift:1']);
});

test('Swift reads are strict UTF-8 and preserve universal-newline line numbers', () => {
  assert.throws(() => readText(Buffer.from([0xc3, 0x28])));
  assert.equal(readText(Buffer.from([0xef, 0xbb, 0xbf, 0x61])), '\ufeffa');
  for (const ending of ['\r', '\r\n']) {
    const source = readText(Buffer.from(`let x = 1${ending}DictationSessionDependencies(a: 1)`));
    assert.deepEqual(offenders([['a.swift', source]]), ['a.swift:2']);
  }
});
