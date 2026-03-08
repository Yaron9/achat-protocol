'use strict';

/**
 * run_all.js - Windows-compatible test runner
 * Runs each test .sh via bash (Git Bash on Windows), or node-based tests.
 */

const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const SKILL_DIR = path.join(__dirname, '..');
const TEST_DIR = __dirname;

const TEST_SCRIPTS = [
  'test_phase0.sh',
  'test_step2.sh',
  'test_step3.sh',
  'test_step4.sh',
  'test_step5.sh',
  'test_step6.sh',
  'test_step7.sh',
  'test_step8.sh',
  'test_step9.sh',
];

// Detect bash executable
function findBash() {
  // Windows: try bash.exe (Git Bash), then wsl bash
  const candidates = process.platform === 'win32'
    ? ['bash.exe', 'C:\\Program Files\\Git\\bin\\bash.exe', 'C:\\Windows\\System32\\bash.exe']
    : ['bash'];

  for (const c of candidates) {
    const result = spawnSync(c, ['--version'], { encoding: 'utf8' });
    if (result.status === 0) return c;
  }
  return null;
}

const bash = findBash();
let allPassed = true;

for (const script of TEST_SCRIPTS) {
  const scriptPath = path.join(TEST_DIR, script);
  if (!fs.existsSync(scriptPath)) {
    console.log(`[run_all] SKIP ${script} (not found)`);
    continue;
  }

  if (!bash) {
    console.warn(`[run_all] SKIP ${script} (bash not found on this system)`);
    continue;
  }

  console.log(`\n[run_all] Running ${script} ...`);
  const result = spawnSync(bash, [scriptPath], {
    cwd: SKILL_DIR,
    stdio: 'inherit',
    encoding: 'utf8',
  });

  if (result.status !== 0) {
    console.error(`[run_all] FAILED: ${script} (exit code ${result.status})`);
    allPassed = false;
  } else {
    console.log(`[run_all] PASSED: ${script}`);
  }
}

if (allPassed) {
  console.log('\n=== All tests passed ===');
  process.exit(0);
} else {
  console.error('\n=== Some tests FAILED ===');
  process.exit(1);
}
