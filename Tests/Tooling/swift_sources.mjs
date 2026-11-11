import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';

const UTF8 = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });

export function gitEnvironment() {
  return {
    ...Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_'))),
    GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null',
  };
}

export function readText(bytes) {
  return UTF8.decode(bytes).replace(/\r\n?/g, '\n');
}

export const lineOf = (text, offset) => text.slice(0, offset).split('\n').length;

export function readSwiftSources(repo, roots) {
  // A repository above `repo` must never stand in for a missing one.
  const env = { ...gitEnvironment(), GIT_CEILING_DIRECTORIES: path.dirname(path.resolve(repo)) };
  const output = execFileSync('git', [
    'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...roots,
  ], { cwd: repo, env });
  const names = UTF8.decode(output).split('\0').filter(Boolean);
  return [...new Set(names)].sort()
    .filter(name => name.endsWith('.swift') && statSync(path.join(repo, name), { throwIfNoEntry: false })?.isFile())
    .map(name => [name, readText(readFileSync(path.join(repo, name)))]);
}
