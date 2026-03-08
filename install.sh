#!/usr/bin/env bash
# AChat Protocol — 一键安装脚本
# 用法：curl -fsSL https://raw.githubusercontent.com/Yaron9/achat-protocol/main/install.sh | bash

set -e

REPO="https://github.com/Yaron9/achat-protocol.git"
INSTALL_DIR="$HOME/.achat"
SKILL_LINK="$HOME/.claude/skills/achat-local"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo ""
echo "  🤝 AChat Protocol 安装程序"
echo "  ─────────────────────────"

# 检查 Node.js
if ! command -v node &>/dev/null; then
  echo -e "${RED}✗ 未找到 Node.js，请先安装 Node.js 18+：https://nodejs.org${NC}"
  exit 1
fi
NODE_VER=$(node -e "console.log(parseInt(process.version.slice(1)))")
if [ "$NODE_VER" -lt 18 ]; then
  echo -e "${RED}✗ Node.js 版本过低（当前 $(node -v)），需要 18+${NC}"
  exit 1
fi
echo -e "  ${GREEN}✓${NC} Node.js $(node -v)"

# 检查 git
if ! command -v git &>/dev/null; then
  echo -e "${RED}✗ 未找到 git${NC}"; exit 1
fi

# 克隆或更新
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "  ↻ 更新现有安装..."
  git -C "$INSTALL_DIR" pull --quiet origin main
else
  echo "  ↓ 克隆仓库到 $INSTALL_DIR ..."
  git clone --quiet "$REPO" "$INSTALL_DIR"
fi
echo -e "  ${GREEN}✓${NC} 仓库就绪"

# 安装 js-yaml（如未安装）
if ! node -e "require('js-yaml')" &>/dev/null 2>&1; then
  echo "  ↓ 安装依赖 js-yaml ..."
  npm install -g js-yaml --quiet
fi
echo -e "  ${GREEN}✓${NC} 依赖就绪"

# 链接到 Claude Code skills 目录
mkdir -p "$(dirname "$SKILL_LINK")"
if [ -L "$SKILL_LINK" ] || [ -e "$SKILL_LINK" ]; then
  rm -f "$SKILL_LINK"
fi
ln -sf "$INSTALL_DIR/skills/achat-local" "$SKILL_LINK"
echo -e "  ${GREEN}✓${NC} Skill 已链接：$SKILL_LINK"

# 生成密钥（如未生成）
AGENT_ID="${ACHAT_AGENT_ID:-achat_agent}"
KEY_FILE="$HOME/.metame/agents/$AGENT_ID/key.json"
if [ ! -f "$KEY_FILE" ]; then
  echo "  🔑 生成 Ed25519 密钥对..."
  node "$INSTALL_DIR/skills/achat-local/bin/keygen" "$AGENT_ID" 2>/dev/null || true
fi

echo ""
echo -e "  ${GREEN}━━━ 安装完成 ━━━${NC}"
echo ""
echo "  快速开始："
echo "    # 发消息"
echo "    node ~/.achat/skills/achat-local/bin/inbox_send <收件人> $AGENT_ID '标题' '内容'"
echo ""
echo "    # 创建多轮对话"
echo "    node ~/.achat/skills/achat-local/bin/thread_create '话题'"
echo ""
echo "  详细文档：https://github.com/Yaron9/achat-protocol"
echo ""
