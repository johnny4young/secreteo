import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = path => readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');
const notices = read('THIRD-PARTY-NOTICES.md');
const pins = JSON.parse(read('Package.resolved')).pins;
const repository = location => /\/([^/]+?)(?:\.git)?$/.exec(location)?.[1];

export function missingNotices(text, names) {
  return names.filter(name => !text.includes(`\n## ${name}\n`) || !text.includes(`| [${name}](`));
}

test('every resolved package has a row and a license section in the notices', () => {
  const names = pins.map(pin => repository(pin.location));
  assert.ok(names.length > 0 && names.every(Boolean));
  assert.deepEqual(missingNotices(notices, names), []);
});

test('Sparkle, fetched outside SwiftPM, has its notice too', () => {
  assert.match(read('scripts/fetch-sparkle.sh'), /Sparkle/);
  assert.deepEqual(missingNotices(notices, ['Sparkle']), []);
});

test('a package without a notice is reported', () => {
  assert.deepEqual(missingNotices('| [A](x) |\n\n## A\n', ['A', 'B']), ['B']);
  assert.deepEqual(missingNotices('\n## A\n', ['A']), ['A'], 'a section without a table row is incomplete');
});
