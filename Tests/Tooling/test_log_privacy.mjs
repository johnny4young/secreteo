import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { readSwiftSources, readText } from './swift_sources.mjs';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
// Stdout is the MCP protocol channel there, not a log.
const STDOUT_ALLOWED = new Set(['Sources/DictationAgents/DictationMCPCommand.swift']);
const SPACE = String.raw`[\t-\r\u001c-\u0020\u0085\p{Zs}\u2028\u2029]`;
const UNREDACTED = new RegExp(
  String.raw`(?:privacy:${SPACE}*|OSLogPrivacy${SPACE}*=${SPACE}*)(?:OSLogPrivacy)?\.public(?![\p{L}\p{N}_])`, 'gu');
const RAW_OUTPUT = /(?<![\p{L}\p{N}_.])(?:(?:Swift|Foundation|Darwin)\.)?(print|debugPrint|NSLog|os_log|dump|fputs|fwrite|puts)\(|FileHandle\.standard(?:Error|Output)|STD(?:ERR|OUT)_FILENO/gu;
const CRASH_CALL = /(?<![\p{L}\p{N}_.])(fatalError|preconditionFailure|precondition|assertionFailure|assert)\(/gu;
const MESSAGE_INDEX = { fatalError: 0, preconditionFailure: 0, assertionFailure: 0, precondition: 1, assert: 1 };
const PLAIN_LITERAL = /^"[^"\\]*"$/;
const COMMENT = new RegExp(String.raw`^${SPACE}*(?://|/\*|\*)`, 'u');

function withoutComments(text) {
  // Blank comment lines but keep line counts, so offsets map to line numbers.
  return text.replace(/\r\n?/g, '\n').split('\n').map(line => COMMENT.test(line) ? '' : line).join('\n');
}
let sourceSnapshot;
function swiftFiles() {
  // These assertions share one immutable source snapshot within this test process.
  return sourceSnapshot ??= readSwiftSources(REPO, ['Sources', 'Apps']).map(([name, text]) => [name, withoutComments(text)]);
}
const STRIP = new RegExp(`^${SPACE}+|${SPACE}+$`, 'gu');
const strip = text => text.replace(STRIP, '');
const lineOf = (text, offset) => text.slice(0, offset).split('\n').length;

function callArguments(text, start) {
  let depth = 0, quoted = false, args = [], current = '';
  for (let index = start; index < text.length; index++) {
    const char = text[index];
    if (quoted) {
      current += char;
      if (char === '\\' && index + 1 < text.length) continue;
      if (char === '"' && text[index - 1] !== '\\') quoted = false;
      continue;
    }
    if (char === '"') quoted = true;
    else if ('([{'.includes(char)) {
      depth++;
      if (depth === 1) continue;
    } else if (')]}'.includes(char)) {
      depth--;
      if (depth === 0) {
        args.push(strip(current));
        return args.filter(Boolean);
      }
    } else if (char === ',' && depth === 1) {
      args.push(strip(current));
      current = '';
      continue;
    }
    current += char;
  }
  return args;
}
function unsafeCrashMessages(text) {
  const offsets = [];
  for (const match of text.matchAll(CRASH_CALL)) {
    const args = callArguments(text, match.index + match[0].length - 1);
    const index = MESSAGE_INDEX[match[1]];
    if (args.length > index && !PLAIN_LITERAL.test(args[index])) offsets.push(match.index);
  }
  return offsets;
}

test('no log marks a value public', () => {
  const offenders = swiftFiles().flatMap(([name, text]) => Array.from(text.matchAll(UNREDACTED), match => `${name}:${lineOf(text, match.index)}`));
  assert.deepEqual(offenders, [], 'a public log value can carry dictated text');
});

test('crash messages are plain literals', () => {
  const offenders = swiftFiles().flatMap(([name, text]) => unsafeCrashMessages(text).map(offset => `${name}:${lineOf(text, offset)}`));
  assert.deepEqual(offenders, [], 'a crash report keeps its message unredacted');
});

test('only the MCP command writes to stdout', () => {
  const offenders = swiftFiles().flatMap(([name, text]) => Array.from(text.matchAll(RAW_OUTPUT))
    .filter(match => !(STDOUT_ALLOWED.has(name) && match[1] === 'print'))
    .map(match => `${name}:${lineOf(text, match.index)}`));
  assert.deepEqual(offenders, [], 'print and NSLog skip redaction');
});

test('the patterns catch what they guard', () => {
  for (const value of ['"\\(text, privacy: .public)"', '\\(text, privacy:\n    .public)', '\\(text, privacy: OSLogPrivacy.public)', 'let p: OSLogPrivacy = .public']) assert.ok(value.match(UNREDACTED), value);
  assert.equal('\\(text, privacy: .publicDetail)'.match(UNREDACTED), null);
  assert.equal('privacy: .publicá'.match(UNREDACTED), null);
  for (const raw of ['print(text)', 'debugPrint(x)', 'NSLog(format)', 'os_log(format)', 'dump(record)', 'fputs(text, stderr)', 'fwrite(buffer, 1, n, stdout)', 'puts(text)', 'Swift.print(text)', 'Foundation.NSLog(format)', 'FileHandle.standardError.write(data)', 'FileHandle.standardOutput.write(data)', 'write(STDERR_FILENO, buffer, n)']) assert.ok(raw.match(RAW_OUTPUT), raw);
  for (const safe of ['controller.print(document)', 'fingerprint(part)', 'outputs(x)']) assert.equal(safe.match(RAW_OUTPUT), null, safe);
  for (const unsafe of ['fatalError("bad \\(text)")', 'fatalError(\n    "bad \\(text)")', 'fatalError(error.localizedDescription)', 'preconditionFailure("\\(x)")', 'assertionFailure(message)', 'precondition(ok,\n    "bad \\(text)")', 'assert(ok, String(describing: error))']) assert.ok(unsafeCrashMessages(unsafe).length, unsafe);
  for (const safe of ['fatalError("unreachable")', 'fatalError()', 'precondition(count > 0)', 'assert(items.contains(where: { $0 > 1 }), "empty")', 'precondition(a, "it\'s, fine")']) assert.deepEqual(unsafeCrashMessages(safe), [], safe);
  assert.equal(withoutComments('/// privacy: .public\nlet x = 1'), '\nlet x = 1');
});

test('CR and CRLF line endings do not hide logs after comment lines', () => {
  for (const ending of ['\r', '\r\n']) {
    const text = withoutComments(`/// comment${ending}print(text)`);
    const match = Array.from(text.matchAll(RAW_OUTPUT))[0];
    assert.ok(match, JSON.stringify(ending));
    assert.equal(lineOf(text, match.index), 2);
  }
});

test('Swift reads reject malformed UTF-8', () => {
  assert.throws(() => readText(Buffer.from([0xc3, 0x28])));
  assert.equal(readText(Buffer.from([0xef, 0xbb, 0xbf, 0x61])), '\ufeffa');
});

for (const value of ['\u001c', '\u0085', '\u2028', '\u3000']) {
  test(`Python whitespace semantics are retained for U+${value.codePointAt(0).toString(16)}`, () => {
    assert.ok(`privacy:${value}.public`.match(UNREDACTED));
    assert.equal(withoutComments(`${value}// privacy: .public`), '');
    assert.deepEqual(unsafeCrashMessages(`fatalError(${value}"literal"${value})`), []);
    assert.equal('privacy: \ufeff.public'.match(UNREDACTED), null);
    assert.equal(withoutComments('\ufeff// privacy: .public'), '\ufeff// privacy: .public');
  });
}
