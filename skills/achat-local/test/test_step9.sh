#!/bin/bash
set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== Step 9: Mac+Windows 跨平台兼容 ==="

# 1. lib/platform.js 加载正常
out=$(node -e "const p=require('$SKILL_DIR/lib/platform'); console.log(p.METAME_DIR);" 2>&1)
if echo "$out" | grep -q '\.metame'; then
  pass "lib/platform.js 加载正常，METAME_DIR 包含 .metame"
else
  fail "lib/platform.js 加载失败或 METAME_DIR 异常: $out"
fi

# 2. IS_WINDOWS 在 macOS 上为 false
out=$(node -e "const p=require('$SKILL_DIR/lib/platform'); console.log(p.IS_WINDOWS);" 2>&1)
if [ "$out" = "false" ]; then
  pass "IS_WINDOWS 在 macOS 上为 false"
else
  fail "IS_WINDOWS 值不正确: $out"
fi

# 3. requireYaml 能找到 js-yaml
out=$(node -e "const p=require('$SKILL_DIR/lib/platform'); const y=p.requireYaml(); console.log(typeof y.load);" 2>&1)
if [ "$out" = "function" ]; then
  pass "requireYaml 能找到 js-yaml"
else
  fail "requireYaml 失败: $out"
fi

# 4. 所有 bin/ 脚本不再有硬编码 /Users/yaron 路径
if grep -r "Users/yaron" "$SKILL_DIR/bin/" "$SKILL_DIR/lib/" 2>/dev/null | grep -v "^Binary"; then
  fail "发现硬编码 /Users/yaron 路径"
else
  pass "所有 bin/ 和 lib/ 脚本无硬编码 /Users/yaron 路径"
fi

# 5. 所有 bin/ 脚本 shebang 是 node
fail_shebang=0
for f in "$SKILL_DIR/bin/"*; do
  [ -f "$f" ] || continue
  first=$(head -1 "$f")
  if [ "$first" != "#!/usr/bin/env node" ]; then
    echo "  WARN: $f shebang = $first"
    fail_shebang=1
  fi
done
if [ $fail_shebang -eq 0 ]; then
  pass "所有 bin/ 脚本 shebang 是 #!/usr/bin/env node"
else
  fail "部分 bin/ 脚本 shebang 不是 node"
fi

# 6. package.json 存在且合法
pkg="$SKILL_DIR/package.json"
if [ -f "$pkg" ]; then
  out=$(node -e "const p=require('$pkg'); console.log(p.name);" 2>&1)
  if [ "$out" = "@achat/local" ]; then
    pass "package.json 存在且合法"
  else
    fail "package.json name 字段异常: $out"
  fi
else
  fail "package.json 不存在"
fi

# 7. Windows .cmd 文件存在
cmd_dir="$SKILL_DIR/bin/windows"
missing=0
for cmd in achat-send.cmd achat-read.cmd achat-bridge.cmd achat-keygen.cmd; do
  if [ ! -f "$cmd_dir/$cmd" ]; then
    echo "  MISSING: $cmd_dir/$cmd"
    missing=1
  fi
done
if [ $missing -eq 0 ]; then
  pass "Windows .cmd 文件均存在"
else
  fail "部分 Windows .cmd 文件缺失"
fi

# 8. METAME_DIR 环境变量覆盖生效
out=$(METAME_DIR=/tmp/test-achat node -e "const p=require('$SKILL_DIR/lib/platform'); console.log(p.METAME_DIR);" 2>&1)
if [ "$out" = "/tmp/test-achat" ]; then
  pass "METAME_DIR 环境变量覆盖生效"
else
  fail "METAME_DIR 环境变量覆盖无效: $out"
fi

echo ""
echo "结果: PASS=$PASS  FAIL=$FAIL"

if [ $FAIL -eq 0 ]; then
  echo "=== Step 9 所有测试通过 ✅ ==="
  exit 0
else
  echo "=== Step 9 测试失败 ❌ ==="
  exit 1
fi
