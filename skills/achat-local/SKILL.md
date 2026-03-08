# achat-local · AChat Phase 0 本地通信

## 概述

**skill 名称**：achat-local
**版本**：0.1.0
**阶段**：AChat Phase 0
**用途**：MetaMe 内部 agent 间异步消息通信（本机）

---

## 使用方法

### 发消息

```bash
node ~/AGI/AChat-worktree-phase0/skills/achat-local/bin/inbox_send \
  <to_key> <from_key> <subject> "<message_body>"
```

示例：
```bash
node .../bin/inbox_send metame achat_pm "协议评审请求" "Phase 0 Thread 协议草稿已完成，请评审。"
```

### 收消息（查看未读）

```bash
node ~/AGI/AChat-worktree-phase0/skills/achat-local/bin/inbox_read <my_key>
```

### 查历史（所有消息）

```bash
node ~/AGI/AChat-worktree-phase0/skills/achat-local/bin/inbox_read <my_key> --all
```

---

## 协议规范（PSC Level 0）

### 消息文件格式

消息以 `.md` 文件存储于 `~/.metame/memory/inbox/{to_key}/`。

**文件头（Header）**：
```
FROM: {from_key}
TO: {to_key}
TS: {ISO 8601 timestamp}
SUBJECT: {subject}
THREAD_ID: {uuid v4}
PSC_LEVEL: 0
```

空行分隔后为消息正文。

### 消息 Schema

完整 JSON Schema 见 `schema/message.schema.json`。

**PSC（Progressive Semantic Compression）级别**：
- Level 0：纯文本，人类可读，无结构约束（当前阶段）
- Level 1：结构化 Schema（规划中）
- Level 2：隐层向量压缩（远期）

### x-achat Intent 语义标注（可选）

| Intent | 含义 |
|--------|------|
| SAY | 普通陈述 |
| ASK | 发起问题/请求 |
| PROPOSE | 提案/建议 |
| DECIDE | 决策通知 |
| DELEGATE | 任务委托 |
| UPDATE | 状态更新 |
| BLOCK | 阻塞通知 |

---

## 目录结构

```
skills/achat-local/
├── SKILL.md              ← 本文档
├── bin/
│   ├── inbox_send        ← 发消息脚本
│   └── inbox_read        ← 读消息脚本
├── schema/
│   └── message.schema.json ← AChat Phase 0 消息 Schema
└── test/
    └── test_phase0.sh    ← 自动化测试
```

---

## 限制

- **仅限本机**：依赖本地文件系统，无跨网络通信能力
- **无加密**：Phase 0 不含签名/加密，生产场景不可用
- **无 ACK**：发送后无送达确认机制
- **无持久连接**：基于文件轮询，非实时推送

---

## 依赖

- Node.js >= 16（内置模块：fs, path, crypto, child_process, os）
- MetaMe dispatch_to 命令（用于发送通知）
- `~/.metame/memory/inbox/` 目录结构
