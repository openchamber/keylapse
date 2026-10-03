#!/usr/bin/env node
/**
 * Keylapse local development helper, in the spirit of OpenChamber's oc-dev.
 *
 *   bun kl-dev            interactive menu
 *   bun kl-dev <action>   one action, no questions
 *
 * Actions:
 *   reset     Back to the state before the first launch: quit Keylapse, revoke its
 *             Accessibility and Input Monitoring permissions, forget all its preferences
 *             (welcome page, shortcuts, behavior), then open the app in /Applications again.
 *   build     Release build, signed: dist/Keylapse.app and dist/Keylapse.zip.
 *   install   Build, quit Keylapse, copy it to /Applications and open it.
 *   package   Zip for a tester on the Desktop: ~/Desktop/Keylapse-<version>.zip, holding the app
 *             and Keylapse Reset.command (first launch again, without the repository).
 *   preview   For an agent, which cannot see the screen: renders the window to PNGs in
 *             dist/previews (settings, welcome before and after setup, welcome after the
 *             correction) and prints the paths. Extra flags go to --check-settings, e.g.
 *             `bun kl-dev preview --preview-many-layouts`, which renders that one state.
 *   watch     The nearest thing to hot reload for a compiled app: a debug build runs from
 *             .build, and every saved .swift file rebuilds it (incremental, seconds) and
 *             relaunches it so the window reopens with the change. The debug binary has no
 *             bundle, so macOS does not give it the permissions: the window and the welcome
 *             page can be checked, the keyboard shortcuts cannot.
 *
 * No dependencies on purpose: node or bun is enough.
 */
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, watch as watchFiles } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createInterface } from 'node:readline/promises';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const bundleID = 'com.openchamber.keylapse';
const installed = '/Applications/Keylapse.app';
const built = path.join(root, 'dist', 'Keylapse.app');
const zip = path.join(root, 'dist', 'Keylapse.zip');

const actions = [
  ['reset', 'Reset to before the first launch (quit, revoke permissions, forget preferences)'],
  ['build', 'Build dist/Keylapse.app and dist/Keylapse.zip'],
  ['install', 'Build, install into /Applications and open'],
  ['package', 'Zip for a tester on the Desktop'],
  ['watch', 'Rebuild and relaunch on every saved .swift file (debug build)'],
  ['preview', 'Render the window states to PNGs in dist/previews'],
];

function run(command, args, { quiet = false } = {}) {
  const result = spawnSync(command, args, { cwd: root, stdio: quiet ? 'pipe' : 'inherit', encoding: 'utf8' });
  if (result.error) throw result.error;
  return result;
}

function say(text) { console.log(`\n${text}`); }

function version() {
  const plist = readFileSync(path.join(root, 'Resources', 'Info.plist'), 'utf8');
  return plist.match(/CFBundleShortVersionString<\/key>\s*<string>([^<]+)</)?.[1] ?? 'dev';
}

function quit() {
  const running = run('pgrep', ['-x', 'Keylapse'], { quiet: true }).status === 0;
  if (!running) return;
  run('osascript', ['-e', 'tell application "Keylapse" to quit'], { quiet: true });
  for (let i = 0; i < 20 && run('pgrep', ['-x', 'Keylapse'], { quiet: true }).status === 0; i += 1) {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
  }
  run('pkill', ['-x', 'Keylapse'], { quiet: true });
  console.log('Keylapse quit.');
}

function reset() {
  quit();
  for (const service of ['Accessibility', 'ListenEvent']) {
    const result = run('tccutil', ['reset', service, bundleID], { quiet: true });
    const label = service === 'ListenEvent' ? 'Input Monitoring' : service;
    console.log(result.status === 0 ? `${label} permission revoked.` : `${label}: ${result.stderr.trim() || 'nothing to revoke'}`);
  }
  const prefs = run('defaults', ['delete', bundleID], { quiet: true });
  console.log(prefs.status === 0 ? 'Preferences forgotten (welcome page, shortcuts, behavior).' : 'No preferences were stored.');
  if (existsSync(installed)) {
    run('open', [installed]);
    say(`Done. Opened ${installed} as on the first launch.`);
  } else {
    say('Done. Keylapse is not in /Applications: bun kl-dev install puts it there.');
  }
  say('Launch at login is kept by macOS, not by Keylapse: if it is on, turn it off in System Settings → General → Login Items.');
}

function build() {
  const result = run('bash', ['scripts/build.sh']);
  if (result.status !== 0) throw new Error('Build failed.');
}

function install() {
  build();
  quit();
  const copy = run('ditto', [built, installed]);
  if (copy.status !== 0) throw new Error(`Could not copy to ${installed}.`);
  run('open', [installed]);
  say(`Installed and opened ${installed}.`);
}

function pack() {
  if (!existsSync(built)) {
    console.log('No build yet, building first.');
    build();
  }
  // One archive for a tester: a folder with the app and a double-clickable reset beside it.
  const name = `Keylapse-${version()}`;
  const stage = path.join(os.tmpdir(), `keylapse-package-${process.pid}`, name);
  mkdirSync(stage, { recursive: true });
  const reset = path.join(root, 'scripts', 'Keylapse Reset.command');
  if (run('ditto', [built, path.join(stage, 'Keylapse.app')]).status !== 0
      || run('ditto', [reset, path.join(stage, 'Keylapse Reset.command')]).status !== 0) throw new Error('Could not collect the files.');
  const target = path.join(os.homedir(), 'Desktop', `${name}.zip`);
  if (run('ditto', ['-c', '-k', '--keepParent', stage, target]).status !== 0) throw new Error(`Could not write ${target}.`);
  run('rm', ['-rf', path.dirname(stage)], { quiet: true });
  say(`Ready to send: ${target}`);
  console.log('Inside: Keylapse.app and Keylapse Reset.command. Signed with the local certificate, so macOS blocks the first open of each: allow it in System Settings → Privacy & Security → Open Anyway.');
}

const previewStates = [
  ['settings', ['--preview-settings-page', '--preview-setup-ready']],
  ['settings-before-setup', ['--preview-settings-page', '--preview-missing-permissions']],
  ['welcome-before-setup', ['--preview-welcome', '--preview-missing-permissions']],
  ['welcome-ready', ['--preview-welcome', '--preview-setup-ready']],
  ['welcome-corrected', ['--preview-welcome', '--preview-setup-ready', '--preview-demo-done']],
];

function preview(extraFlags) {
  const result = run('swift', ['build'], { quiet: true });
  if (result.status !== 0) throw new Error(result.stderr.split('\n').filter((line) => line.includes('error:')).join('\n') || 'Build failed.');
  const bin = path.join(run('swift', ['build', '--show-bin-path'], { quiet: true }).stdout.trim(), 'Keylapse');
  const folder = path.join(root, 'dist', 'previews');
  mkdirSync(folder, { recursive: true });
  // A custom state means the settings page unless the welcome page is asked for; otherwise the
  // page would depend on whether the welcome has been dismissed on this Mac.
  const page = extraFlags.includes('--preview-welcome') ? [] : ['--preview-settings-page'];
  const states = extraFlags.length ? [['custom', [...page, ...extraFlags]]] : previewStates;
  for (const [name, flags] of states) {
    const file = path.join(folder, `${name}.png`);
    const render = run(bin, ['--check-settings', file, ...flags], { quiet: true });
    const report = (render.stdout + render.stderr).split('\n').find((line) => line.startsWith('PASS') || line.startsWith('FAIL')) ?? 'no report';
    console.log(`${file}\n  ${report}`);
  }
}

function watch() {
  quit();
  let child = null;
  let timer = null;
  let building = false;
  let again = false;
  const relaunch = () => {
    if (building) { again = true; return; }
    building = true;
    const started = Date.now();
    process.stdout.write('Building… ');
    const result = run('swift', ['build'], { quiet: true });
    building = false;
    if (result.status !== 0) {
      console.log('failed.');
      console.log(result.stderr.split('\n').filter((line) => line.includes('error:')).join('\n') || result.stderr);
    } else {
      const bin = path.join(run('swift', ['build', '--show-bin-path'], { quiet: true }).stdout.trim(), 'Keylapse');
      if (child) { child.kill(); child = null; }
      child = spawn(bin, [], { cwd: root, stdio: 'ignore' });
      child.on('exit', () => { child = null; });
      console.log(`${((Date.now() - started) / 1000).toFixed(1)} s, relaunched at ${new Date().toLocaleTimeString()}.`);
    }
    if (again) { again = false; relaunch(); }
  };
  relaunch();
  watchFiles(path.join(root, 'Sources'), { recursive: true }, (_event, file) => {
    if (!file?.endsWith('.swift')) return;
    clearTimeout(timer);
    timer = setTimeout(relaunch, 400);
  });
  console.log('Watching Sources/. Save a file to rebuild; Ctrl+C stops and quits the app.');
  const stop = () => { if (child) child.kill(); process.exit(0); };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  process.on('SIGHUP', stop);
  process.on('exit', () => { if (child) child.kill(); });
}

const handlers = { reset, build, install, package: pack, watch, preview: () => preview(process.argv.slice(3)) };

async function choose() {
  console.log('Keylapse dev\n');
  actions.forEach(([name, description], index) => console.log(`  ${index + 1}. ${name.padEnd(8)} ${description}`));
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const answer = (await rl.question('\nNumber or name (Enter to quit): ')).trim();
  rl.close();
  if (!answer) return null;
  const byNumber = actions[Number(answer) - 1]?.[0];
  return byNumber ?? answer;
}

const requested = process.argv[2];
if (requested === '-h' || requested === '--help') {
  console.log('bun kl-dev [reset|build|install|package|watch|preview [--preview-… flags]]');
  process.exit(0);
}
const action = requested ?? (process.stdin.isTTY ? await choose() : null);
if (action === 'watch') { watch(); } else {
if (!action) process.exit(0);
if (!handlers[action]) {
  console.error(`Unknown action "${action}". Use one of: ${Object.keys(handlers).join(', ')}.`);
  process.exit(1);
}
try {
  handlers[action]();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
}
