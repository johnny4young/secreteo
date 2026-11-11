import assert from 'node:assert/strict';
import { test } from 'node:test';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, writeFileSync, rmSync, existsSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { proof, main, withDeadline } from '../../scripts/ci_reuse_gate.mjs';

const REPO = 'owner/repo';
const MERGED = 'a'.repeat(40), HEAD = 'b'.repeat(40), TREE = 'c'.repeat(40);
const ROOT = fileURLToPath(new URL('../..', import.meta.url));
const runsPath = `repos/${REPO}/actions/runs?head_sha=${HEAD}&event=pull_request&per_page=100`;
const run = (id = 7, overrides = {}) => ({ id, path: '.github/workflows/ci.yml', head_sha: HEAD,
  event: 'pull_request', status: 'completed', conclusion: 'success', run_attempt: 1,
  html_url: `https://github.com/${REPO}/actions/runs/${id}`, ...overrides });
const gate = (overrides = {}) => ({ name: 'gate', status: 'completed', conclusion: 'success',
  head_sha: HEAD, run_id: 7, run_attempt: 1, ...overrides });
const page = (key, values) => ({ total_count: values.length, [key]: values });
const mergedPull = () => ({ merge_commit_sha: MERGED, merged_at: '2026-11-05T00:00:00Z', head: { sha: HEAD } });
function world() {
  const responses = {
    [`repos/${REPO}/commits/${MERGED}/pulls?per_page=100`]: [mergedPull()],
    [`repos/${REPO}/git/commits/${MERGED}`]: { tree: { sha: TREE } },
    [`repos/${REPO}/git/commits/${HEAD}`]: { tree: { sha: TREE } },
    [runsPath]: page('workflow_runs', [run()]),
    [`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`]: page('jobs', [gate()]),
  };
  const calls = [];
  return { responses, calls, api: path => { calls.push(path); assert.ok(Object.hasOwn(responses, path), path); return responses[path]; } };
}
const output = () => ({ lines: [], log(value) { this.lines.push(value); }, error(value) { this.lines.push(value); } });

test('the tree a pull request proved reuses its gate', () => {
  const w = world();
  assert.equal(proof(w.api, REPO, MERGED), run().html_url);
  assert.equal(w.calls.length, 6);
});
test('a different tree runs everything', () => {
  const w = world(); w.responses[`repos/${REPO}/git/commits/${HEAD}`].tree.sha = 'd'.repeat(40);
  assert.equal(proof(w.api, REPO, MERGED), null);
});
test('a failed gate runs everything', () => {
  const w = world(); w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].conclusion = 'failure';
  assert.equal(proof(w.api, REPO, MERGED), null);
});
test('an unfinished gate runs everything', () => {
  const w = world(); w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].conclusion = null;
  assert.equal(proof(w.api, REPO, MERGED), null);
});
test('only the newest run counts', () => {
  for (const [oldResult, newResult, expected] of [['success','failure',null], ['failure','success',run(9).html_url]]) {
    const w = world(); w.responses[runsPath] = page('workflow_runs', [run(), run(9)]);
    w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`] = page('jobs',[gate({ conclusion: oldResult })]);
    w.responses[`repos/${REPO}/actions/runs/9/attempts/1/jobs?per_page=100`] = page('jobs',[gate({ run_id: 9, conclusion: newResult })]);
    assert.equal(proof(w.api, REPO, MERGED), expected);
  }
});
test('a gate job from another workflow does not count', () => {
  const w = world(); w.responses[runsPath].workflow_runs[0].path = '.github/workflows/other.yml';
  assert.equal(proof(w.api, REPO, MERGED), null);
});
test('a commit no pull request merged runs everything', () => {
  for (const pulls of [[], [{...mergedPull(), merged_at:null}], [{...mergedPull(), merge_commit_sha:'d'.repeat(40)}]]) {
    const w = world(); w.responses[`repos/${REPO}/commits/${MERGED}/pulls?per_page=100`] = pulls;
    assert.equal(proof(w.api, REPO, MERGED), null);
  }
});
test('any API error runs everything', () => {
  for (const error of [new Error('private API error'), new TypeError('missing tree'), new SyntaxError('not JSON')]) {
    const log = output();
    assert.equal(main(() => {throw error;}, REPO, MERGED, log), 1);
    assert.doesNotMatch(log.lines.join('\n'), /private|missing tree|not JSON/);
  }
});
test('a proven tree exits zero', () => {
  const w=world(), log=output();
  assert.equal(main(w.api,REPO,MERGED,log),0);
  assert.deepEqual(log.lines,[`This tree passed gate in ${run().html_url}`]);
});

for (const [name, mutate] of [
  ['ambiguous merge', w => w.responses[`repos/${REPO}/commits/${MERGED}/pulls?per_page=100`].push(mergedPull())],
  ['possibly truncated associated pulls', w => w.responses[`repos/${REPO}/commits/${MERGED}/pulls?per_page=100`] = [mergedPull(), ...Array.from({length:99},()=>({}))]],
  ['missing head', w => w.responses[`repos/${REPO}/commits/${MERGED}/pulls?per_page=100`][0].head = {}],
  ['null matching trees', w => { w.responses[`repos/${REPO}/git/commits/${MERGED}`].tree.sha=null; w.responses[`repos/${REPO}/git/commits/${HEAD}`].tree.sha=null; }],
  ['truncated runs', w => w.responses[runsPath].total_count=2],
  ['duplicate newest run ID', w => w.responses[runsPath]=page('workflow_runs',[run(),run()])],
  ['unsafe run ID', w => w.responses[runsPath].workflow_runs[0].id=Number.MAX_SAFE_INTEGER+1],
  ['wrong run head', w => w.responses[runsPath].workflow_runs[0].head_sha=MERGED],
  ['wrong run event', w => w.responses[runsPath].workflow_runs[0].event='push'],
  ['pending rerun', w => w.responses[runsPath].workflow_runs[0].status='queued'],
  ['failed run', w => w.responses[runsPath].workflow_runs[0].conclusion='failure'],
  ['missing attempt', w => delete w.responses[runsPath].workflow_runs[0].run_attempt],
  ['malformed run URL', w => w.responses[runsPath].workflow_runs[0].html_url='bad\n::notice::value'],
  ['truncated jobs', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].total_count=2],
  ['missing gate', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`]=page('jobs',[])],
  ['duplicate gate', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`]=page('jobs',[gate(),gate()])],
  ['wrong job run', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].run_id=8],
  ['wrong job attempt', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].run_attempt=2],
  ['wrong job head', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].head_sha=MERGED],
  ['unfinished successful job', w => w.responses[`repos/${REPO}/actions/runs/7/attempts/1/jobs?per_page=100`].jobs[0].status='in_progress'],
]) {
  test(`${name} cannot prove reuse`, () => {const w=world();mutate(w);assert.equal(main(w.api,REPO,MERGED,output()),1);});
}

for (const [name, newer] of [['rerun',run(7,{run_attempt:2})],['new run',run(9)],['cancelled run',run(7,{conclusion:'cancelled'})]]) {
  test(`a ${name} appearing during proof invalidates reuse`, () => {
    const w=world();let reads=0;
    const api=path=>path===runsPath && ++reads>1 ? page('workflow_runs',[newer]) : w.api(path);
    assert.equal(proof(api,REPO,MERGED),null);
  });
}

test('malformed API envelopes fail closed at every read', () => {
  const valid=world();proof(valid.api,REPO,MERGED);
  for(const path of new Set(valid.calls)) for(const payload of [null, false, 0, '', [], {}]) {
    const w=world();w.responses[path]=payload;
    assert.equal(main(w.api,REPO,MERGED,output()),1,`${path}: ${JSON.stringify(payload)}`);
  }
});

test('invalid arguments never query GitHub', () => {
  for(const [repo,sha] of [[null,MERGED],['../repo',MERGED],['owner/..',MERGED],[REPO,''],[REPO,'x'.repeat(40)]]) {
    let called=false;
    assert.equal(main(()=>{called=true;return {};},repo,sha,output()),1);
    assert.equal(called,false);
  }
});

function cliFixture(t) {
  const root=mkdtempSync(join(tmpdir(),'reuse-proof-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const w=world(), responses=join(root,'responses.json'), marker=join(root,'invoked');
  writeFileSync(responses,JSON.stringify(w.responses));
  writeFileSync(join(root,'gh'), `#!/usr/bin/env node\nconst fs=require('node:fs');\nfs.writeFileSync(process.env.PROOF_MARKER,'yes');\nif(process.env.PROOF_MODE==='error'){process.stderr.write('PRIVATE-SENTINEL');process.exit(23);}\nif(process.env.PROOF_MODE==='json'){process.stdout.write('not JSON PRIVATE-SENTINEL');process.exit(0);}\nif(process.env.PROOF_MODE==='utf8'){process.stdout.write(Buffer.from([255]));process.exit(0);}\nconst data=JSON.parse(fs.readFileSync(process.env.PROOF_RESPONSES));\nconst value=data[process.argv[3]];\nif(process.argv[2]!=='api'||value===undefined)process.exit(24);\nprocess.stdout.write(JSON.stringify(value));\n`,{mode:0o755});
  const env={ PATH:`${root}:${dirname(process.execPath)}:/usr/bin:/bin`, PROOF_RESPONSES:responses, PROOF_MARKER:marker };
  return { root,env,marker };
}
for(const mode of ['valid','error','json','utf8']) {
  test(`the real CLI handles ${mode} GitHub output`, t=>{
    const {env,marker}=cliFixture(t);
    const result=spawnSync(process.execPath,['scripts/ci_reuse_gate.mjs',REPO,MERGED],{cwd:ROOT,env:{...env,PROOF_MODE:mode},encoding:'utf8'});
    assert.ifError(result.error);assert.equal(result.status,mode==='valid'?0:1,result.stderr);
    assert.ok(existsSync(marker));assert.doesNotMatch(result.stdout+result.stderr,/PRIVATE-SENTINEL/);
    if(mode==='valid')assert.match(result.stdout,/This tree passed gate/);
  });
}
test('importing the module does not query GitHub or run the CLI', t=>{
  const {env,marker}=cliFixture(t);
  const result=spawnSync(process.execPath,['--input-type=module','-e',`import ${JSON.stringify(pathToFileURL(join(ROOT,'scripts/ci_reuse_gate.mjs')).href)}; console.log('imported');`],{env,encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);assert.equal(result.stdout,'imported\n');assert.equal(existsSync(marker),false);
});

test('missing, extra and invalid CLI arguments do not query GitHub', t => {
  const {env,marker}=cliFixture(t);
  for(const args of [[],[REPO],[REPO,MERGED,'extra'],[REPO,'bad']]) {
    const result=spawnSync(process.execPath,['scripts/ci_reuse_gate.mjs',...args],{cwd:ROOT,env,encoding:'utf8'});
    assert.equal(result.status,1);assert.equal(existsSync(marker),false);
  }
});

const workflow=readFileSync(new URL('../../.github/workflows/ci.yml',import.meta.url),'utf8');
const changes=workflow.slice(workflow.indexOf('  changes:\n'),workflow.indexOf('\n  unit:\n'));
const script=changes.slice(changes.indexOf('        run: |\n')+'        run: |\n'.length)
  .split('\n').map(line=>line.slice(10)).join('\n');
for(const [mode,event,reuses] of [['valid','push',true],['error','push',false],['json','push',false],['utf8','push',false],['valid','pull_request',false]]) {
  test(`the actual scope pipeline ${reuses?'reuses':'runs everything'} for ${event}/${mode}`,t=>{
    const {root,env,marker}=cliFixture(t),outputs=join(root,'outputs');
    mkdirSync(join(root,'scripts'));
    for(const name of ['ci_reuse_gate.mjs','ci_changes.mjs']) copyFileSync(join(ROOT,'scripts',name),join(root,'scripts',name));
    // The empty diff avoids Git and must select every job unless the proof succeeds.
    const result=spawnSync('/bin/bash',['-e','-c',script],{cwd:root,env:{...env,PROOF_MODE:mode,
      EVENT_NAME:event,BASE_SHA:'',HEAD_SHA:MERGED,GITHUB_REPOSITORY:REPO,GITHUB_OUTPUT:outputs},encoding:'utf8'});
    assert.equal(result.status,0,result.stderr);
    assert.equal(readFileSync(outputs,'utf8'),['code','delivery','release'].map(name=>`${name}=${!reuses}\n`).join(''));
    assert.equal(existsSync(marker),event==='push');
  });
}

test('workflow keeps proof conditional on push and in canonical hygiene',()=>{
  assert.match(changes,/if \[ "\$EVENT_NAME" = push \]; then\n\s+run_jobs=true\n\s+if node scripts\/ci_reuse_gate\.mjs "\$GITHUB_REPOSITORY" "\$HEAD_SHA"; then/);
  const hygiene=readFileSync(new URL('../../scripts/check-repository-hygiene.sh',import.meta.url),'utf8');
  assert.ok(hygiene.includes('Tests/Tooling/test_ci_reuse.mjs'));
});

test('an unclassified newer run cannot be ignored as another workflow',()=>{
  const w=world();w.responses[runsPath]=page('workflow_runs',[run(),{id:9}]);
  assert.equal(proof(w.api,REPO,MERGED),null);
});

test('a tree hash with a trailing newline is not a valid Git tree',()=>{
  const w=world();
  for(const sha of [MERGED,HEAD])w.responses[`repos/${REPO}/git/commits/${sha}`].tree.sha=TREE+'\n';
  assert.equal(proof(w.api,REPO,MERGED),null);
});

test('an unproved push runs every job even when its diff would be docs-only',t=>{
  const {root,env}=cliFixture(t),outputs=join(root,'outputs');
  mkdirSync(join(root,'scripts'));
  for(const name of ['ci_reuse_gate.mjs','ci_changes.mjs'])copyFileSync(join(ROOT,'scripts',name),join(root,'scripts',name));
  writeFileSync(join(root,'git'),'#!/bin/sh\nprintf "README.md\\n"\n',{mode:0o755});
  const result=spawnSync('/bin/bash',['-e','-c',script],{cwd:root,env:{...env,PROOF_MODE:'error',
    EVENT_NAME:'push',BASE_SHA:'d'.repeat(40),HEAD_SHA:MERGED,GITHUB_REPOSITORY:REPO,GITHUB_OUTPUT:outputs},encoding:'utf8'});
  assert.equal(result.status,0,result.stderr);
  assert.equal(readFileSync(outputs,'utf8'),'code=true\ndelivery=true\nrelease=true\n');
});

test('a slow API exhausts the proof budget and runs everything', () => {
  let clock = 0;
  const timeouts = [];
  const slow = (path, timeout) => { timeouts.push(timeout); clock += 20_000; return world().api(path); };
  assert.equal(main(withDeadline(slow, 45_000, () => clock), REPO, MERGED, output()), 1);
  assert.deepEqual(timeouts, [15_000, 15_000, 5_000]);
});
