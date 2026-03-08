# AChat Platform Bridge 规范

**版本**: 0.1.0
**状态**: Draft
**日期**: 2026-03-08

---

## 1. 概述

### 为什么需要 Platform Bridge

AChat 是 agent-to-agent 通信协议，目标是成为 agent 时代的通信基础设施。今天的 agent 分散在微信、飞书、Telegram、本地 CLI 等不同平台——它们无法直接互通。

Platform Bridge 解决这个问题：**任何平台只需实现标准的 Bridge 接口，平台上的 agent 就能加入 AChat 网络**，无需改变用户习惯，无需迁移平台。

```
微信 Bot ──┐
飞书 Bot ──┤── Platform Bridge ── AChat 网络 ── inbox_send / inbox_read
Telegram ──┘
MetaMe ────── LocalAdapter（参考实现）
```

### 设计原则

1. **平台无关**：Bridge 接口屏蔽平台差异，AChat 核心协议不感知平台细节
2. **最小接口**：只需实现 3 个函数，降低适配成本
3. **安全优先**：消息必须验证 Ed25519 签名，必须检查 authorized_senders
4. **幂等路由**：同一平台会话映射到固定的 AChat thread_id，保证多轮对话连续性

---

## 2. 标准接口规范

每个 Platform Bridge 适配器必须实现以下 3 个函数接口：

### 2.1 `normalize(rawMsg) → NormalizedAchatMessage`

将平台原始消息转换为 AChat 标准格式。

**输入**: `IncomingMessage`（平台消息标准化后的中间格式）

```typescript
interface IncomingMessage {
  platform: string;        // "wechat" | "feishu" | "telegram" | "metame" | ...
  chat_id: string;         // 平台侧会话/群组 ID
  sender_id: string;       // 发送方在平台上的 ID
  sender_name?: string;    // 发送方显示名称（可选）
  text: string;            // 消息文本内容
  ts: string;              // ISO 8601 时间戳
  raw?: object;            // 平台原始消息体（原样保留）
}
```

**输出**: `NormalizedAchatMessage`（可直接传给 inbox_send）

```typescript
interface NormalizedAchatMessage {
  from: string;            // AChat agent key（平台 ID → agent key 映射）
  to: string;              // 目标 agent key
  subject: string;         // 消息主题（适配器自动生成）
  body: string;            // 消息正文（= IncomingMessage.text）
  intent: string;          // "SAY" | "ASK" | "PROPOSE" | ... 默认 "SAY"
  thread_id: string;       // AChat Thread ID（UUID v4）
  platform_ref?: {         // 平台来源引用（用于回调）
    platform: string;
    chat_id: string;
    sender_id: string;
    message_ts: string;
  };
}
```

**实现要点**：
- `from` 字段：适配器维护 `platform_sender_id → achat_agent_key` 映射表
- `thread_id`：适配器维护 `platform_chat_id → thread_id` 映射，同一会话复用同一 thread_id
- `subject` 默认格式：`[{platform}] 来自 {sender_name || sender_id} 的消息`
- `intent` 可通过解析消息前缀识别（如 `/ask` → `ASK`，`/propose` → `PROPOSE`），默认 `SAY`

---

### 2.2 `send(outMsg) → void`

将 AChat 消息发送到目标平台。

**输入**: `OutgoingMessage`

```typescript
interface OutgoingMessage {
  platform: string;        // 目标平台
  chat_id: string;         // 目标会话/群组 ID
  text: string;            // 消息正文
  thread_id?: string;      // AChat Thread ID（可选）
  reply_to_id?: string;    // 平台侧消息 ID（可选，用于引用回复）
}
```

**实现要点**：
- 适配器负责调用平台 API（HTTP / 本地 IPC / 文件系统）发送消息
- 发送前必须验证目标 agent 的 Ed25519 签名（见第 4 节安全要求）
- 发送失败时记录错误，不应 crash，应返回错误信息
- 本地模式：调用 `inbox_send <to> <from> <subject> <body>`

---

### 2.3 `getCapabilities() → BridgeAdapter`

返回当前适配器的元数据（manifest）。

**输出**: `BridgeAdapter`

```typescript
interface BridgeAdapter {
  name: string;            // 适配器名称
  platform: string;        // 适配的目标平台
  version: string;         // 适配器版本（semver）
  capabilities: string[];  // 支持的能力列表（见下方）
  endpoint?: string;       // 服务端点 URI（本地模式可省略）
  auth_type: string;       // 认证方式
}
```

**capabilities 枚举**：

| 值 | 说明 |
|----|------|
| `normalize` | 支持消息标准化（必须） |
| `send` | 支持消息发送（必须） |
| `receive_webhook` | 支持接收平台 Webhook |
| `signature_verify` | 支持 Ed25519 签名验证 |
| `thread_tracking` | 支持多轮会话 thread_id 追踪 |
| `media_send` | 支持发送图片/文件等富媒体 |

---

## 3. 参考实现：MetaMe Local Adapter

MetaMe Dispatch Adapter 是 Platform Bridge 的参考实现，对应本地文件系统通信模式。

### 3.1 三个接口的映射

| Bridge 接口 | MetaMe 实现 |
|-------------|-------------|
| `normalize(rawMsg)` | 将 dispatch_to 参数映射为 NormalizedAchatMessage（from=dispatch源agent, to=目标agent, body=消息内容） |
| `send(outMsg)` | 调用 `inbox_send <to> <from> <subject> <body>` 写入本地文件系统 inbox |
| `getCapabilities()` | 读取 `~/.metame/agents/<agent_key>/agent.yaml`，生成 BridgeAdapter manifest |

### 3.2 字段映射表

| NormalizedAchatMessage 字段 | MetaMe 来源 |
|----------------------------|-------------|
| `from` | dispatch_to CLI 的 `--from` 参数，或环境变量 `METAME_AGENT_ID` |
| `to` | dispatch_to 的目标 agent key |
| `subject` | `[metame] 来自 {from} 的消息` |
| `body` | dispatch_to 的消息内容参数 |
| `intent` | 默认 `SAY`（本地模式暂不解析前缀） |
| `thread_id` | 由 inbox_send 自动生成 UUID v4 |
| `platform_ref.platform` | `"metame"` |
| `platform_ref.chat_id` | `~/.metame/memory/inbox/{to}/` 目录路径 |

### 3.3 bridge_stub 参考实现

参见 `bin/bridge_stub`，提供以下命令：

```bash
# 标准化一条消息
bridge_stub normalize <json_file>

# 发送消息（本地：调用 inbox_send）
bridge_stub send <json_file>

# 打印适配器元数据
bridge_stub capabilities
```

---

## 4. 平台 Adapter 草案

### 4.1 微信 Adapter（字段映射）

| IncomingMessage 字段 | 微信 API 来源 |
|---------------------|--------------|
| `platform` | `"wechat"` |
| `chat_id` | `FromUserName`（微信用户 OpenID 或群 ID） |
| `sender_id` | `FromUserName` |
| `sender_name` | 通过 `getUserInfo` API 获取，或 `NickName` 字段 |
| `text` | `Content`（文本消息）|
| `ts` | `CreateTime`（Unix timestamp → ISO 8601 转换） |
| `raw` | 完整微信 XML/JSON 消息体 |

**发送映射**（`send`）:

| OutgoingMessage 字段 | 微信 API 参数 |
|---------------------|--------------|
| `chat_id` | `ToUserName` |
| `text` | `Content`（被动回复）或 `text.content`（客服消息） |
| `reply_to_id` | 暂不支持（微信不原生支持引用回复） |

**认证**: `auth_type: "webhook_secret"`（微信消息签名验证 + access_token）

---

### 4.2 飞书 Adapter（字段映射）

| IncomingMessage 字段 | 飞书 API 来源 |
|---------------------|--------------|
| `platform` | `"feishu"` |
| `chat_id` | `event.message.chat_id` |
| `sender_id` | `event.sender.sender_id.open_id` |
| `sender_name` | `event.sender.sender_id.user_id`（需额外 API 查询） |
| `text` | `event.message.content`（JSON 解析后的 text 字段） |
| `ts` | `event.message.create_time`（毫秒时间戳 → ISO 8601） |
| `raw` | 完整飞书 Event 结构体 |

**发送映射**（`send`）:

| OutgoingMessage 字段 | 飞书 API 参数 |
|---------------------|--------------|
| `chat_id` | `receive_id`（`chat_id` 类型） |
| `text` | `content.text`（消息卡片或纯文本） |
| `reply_to_id` | `reply_in_thread`（飞书支持消息串回复） |
| `thread_id` | 可映射为飞书 Thread（飞书支持话题功能） |

**认证**: `auth_type: "bearer_token"`（飞书 App Token，定期刷新）

---

## 5. 安全要求

### 5.1 Ed25519 签名验证

所有通过 Platform Bridge 传入 AChat 网络的消息，**必须**在 `normalize` 完成后、写入 inbox 之前验证签名：

```
签名验证流程：
1. 从 NormalizedAchatMessage.from 获取 agent_key
2. 读取 ~/.metame/agents/{agent_key}/agent.yaml 获取 did
3. 从 DID 中提取公钥（did:key 格式）
4. 验证消息签名 signature（payload = from + to + ts + thread_id + body）
5. 签名无效 → 拒绝消息，返回错误
```

注意：本地 MetaMe 模式下，消息由 `inbox_send` 自动签名；外部平台消息通常无法携带 Ed25519 签名，此时适配器应将 `from` 设为**适配器自身的 agent key**，由适配器代为签名。

### 5.2 authorized_senders 检查

适配器调用 `send`（最终写入 inbox）前，**必须**遵循目标 agent 的 `authorized_senders` 白名单：

1. 读取目标 agent 的 `agent.yaml`
2. 如果 `authorized_senders` 非空，检查 `from` agent key 是否在列表中
3. 不在列表 → 写入 `pending/` 目录，不触发通知
4. 在列表（或列表为空）→ 正常写入 `inbox/`

此逻辑已在 `inbox_send` 中实现，适配器调用 `inbox_send` 即可自动获得该保护。

### 5.3 TLS 要求

- 所有与远端平台 API 的通信必须使用 HTTPS（TLS 1.2+）
- 本地 IPC 模式（如 MetaMe local）豁免此要求

---

## 6. JSON Schema 参考

完整字段定义见 `schema/platform_bridge.schema.json`，包含：

- `IncomingMessage` - 平台原始消息中间格式
- `OutgoingMessage` - 发往平台的消息格式
- `BridgeAdapter` - 适配器 manifest
- `NormalizedAchatMessage` - 标准化后的 AChat 消息

---

## 7. 版本历史

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.1.0 | 2026-03-08 | 初始草案，定义三接口规范及微信/飞书字段映射 |
