import { execFileSync } from 'node:child_process';
import { readFileSync, statSync } from 'node:fs';
import path from 'node:path';

export function gitEnvironment() {
  return {
    ...Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_'))),
    GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null',
  };
}

export function readText(bytes) {
  return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true })
    .decode(bytes).replace(/\r\n?/g, '\n');
}

export function readSwiftSources(repo, roots) {
  const output = execFileSync('git', [
    'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', ...roots,
  ], { cwd: repo, env: gitEnvironment() });
  const names = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true })
    .decode(output).split('\0').filter(Boolean);
  return [...new Set(names)].sort()
    .filter(name => name.endsWith('.swift') && statSync(path.join(repo, name), { throwIfNoEntry: false })?.isFile())
    .map(name => [name, readText(readFileSync(path.join(repo, name)))]);
}
