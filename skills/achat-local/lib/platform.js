'use strict';

const os = require('os');
const path = require('path');
const fs = require('fs');

const IS_WINDOWS = process.platform === 'win32';

// METAME_DIR: 优先读 METAME_DIR 环境变量，否则默认
// Mac/Linux: ~/.metame
// Windows:   %USERPROFILE%\.metame 或 %APPDATA%\metame
const METAME_DIR = process.env.METAME_DIR || path.join(os.homedir(), '.metame');

// AGENTS_DIR: ~/.metame/agents/
const AGENTS_DIR = path.join(METAME_DIR, 'agents');

// INBOX_DIR: ~/.metame/memory/inbox/
const INBOX_DIR = path.join(METAME_DIR, 'memory', 'inbox');

// THREADS_DIR: ~/.metame/memory/threads/
const THREADS_DIR = path.join(METAME_DIR, 'memory', 'threads');

// JS_YAML 路径（尝试多个位置）
function requireYaml() {
  const candidates = [
    path.join(os.homedir(), 'node_modules', 'js-yaml'),
    path.join(os.homedir(), '.metame', 'node_modules', 'js-yaml'),
    'js-yaml', // 如果全局安装了
  ];
  for (const c of candidates) {
    try { return require(c); } catch (_) {}
  }
  throw new Error('js-yaml not found. Run: npm install -g js-yaml');
}

// 确保目录存在
function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

module.exports = { IS_WINDOWS, METAME_DIR, AGENTS_DIR, INBOX_DIR, THREADS_DIR, requireYaml, ensureDir };
