# A-Chat Protocol — 开放 Agent 通信协议

> 状态：Draft v0.5 | 作者：Jarvis + 芒格修订 | 日期：2026-03-02
> 定位：**Agent 文明的基础设施——从通信协议出发，构建 Agent Internet 全栈生态**

---

## 零、核心产品洞察：不改变用户习惯

**终极愿景：人人有自己的 agent，但不需要下载新 App。**

你的 agent 住在微信、飞书、Telegram——用户继续用熟悉的界面，
agent 在背后用 A-Chat 协议和全世界的 agent 通信。

### 类比：Email 协议的成功路径

Email 之所以成功，不是因为它创造了新入口，而是任何客户端（QQ邮箱/Gmail/Outlook）都能互通。

```
A-Chat 目标相同：
用户 A 的 agent 住在微信 ──→ A-Chat 协议 ←── 用户 B 的 agent 住在飞书
两个用户从未离开自己熟悉的 App，但他们的 agent 已经在协作。
```

### 架构含义：Platform Bridge 层

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│微信小程序 │  │ 飞书 Bot │  │Telegram  │  │ 任意 App │
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     └──────────────┴─────────────┴──────────────┘
                          │
               Platform Bridge Layer
              （协议适配 · 身份映射 · 消息转换）
                          │
             ┌────────────▼────────────┐
             │      A-Chat Protocol     │
             │   DID · Thread · PSC     │
             └────────────┬────────────┘
                          │
             ┌────────────▼────────────┐
             │      全球 Agent 网络      │
             │   任意 agent 跨平台互通   │
             └─────────────────────────┘
```

**你的 DID 身份不属于任何平台，它属于你。**
换 App 不换身份，换设备不换身份，换模型不换身份。

### 对产品策略的影响

| 维度 | 新 App 路线 | A-Chat 嵌入路线 |
|------|-----------|---------------|
| 获客成本 | 极高（要改变用户习惯）| 极低（复用现有平台流量）|
| 冷启动 | 从零用户开始 | 直接继承微信/飞书用户基数 |
| Agent 互通 | 仅限本平台 | 跨平台、跨厂商、全球互通 |
| 竞争壁垒 | App 易被复制 | 协议标准 + 生态 = 极深护城河 |
| 失败风险 | 高（用户不迁移）| 低（不要求迁移）|

### Platform Bridge 的设计要点（今天就要考虑）

1. **消息格式双向转换**：微信/飞书消息 ↔ A-Chat 消息，必须无损
2. **身份锚定**：微信 openid / 飞书 user_id → 映射到唯一 DID（单向绑定，不可逆）
3. **权限模型**：用户显式授权 agent 代表自己发送消息（类 OAuth 流程）
4. **平台限制适配**：微信不支持长连接 → Bridge 轮询补偿；飞书有消息频率限制 → Bridge 做队列
5. **隐私隔离**：平台侧看不到 agent 间的 A-Chat 消息体（端到端加密，平台只是管道）

---

## 一、研究背景：站在巨人肩上

在设计 A-Chat 之前，我们对现有协议进行了深度研究。结论如下：

### 现有协议格局（2026年初）

| 协议 | 发起方 | 定位 | 状态 |
|------|--------|------|------|
| **MCP** | Anthropic | Agent ↔ Tool（垂直）| 生产稳定，广泛采用 |
| **A2A** | Google → Linux Foundation | Agent ↔ Agent（水平，企业内）| v0.3，50+ 合作伙伴，事实标准 |
| **ACP** | IBM BeeAI | Agent ↔ Agent（本地优先）| 已并入 A2A（2025-09）|
| **ANP** | 开源社区，W3C | Agent ↔ Agent（去中心化互联网）| 早期，W3C 标准化进行中 |

**关键判断**：A2A 正在成为 agent 间通信的事实标准（类比 HTTP），ANP 是去中心化方向的补充。A-Chat **不应该**是第五个竞争者，而应该是这两者之上的**扩展层**。

### 向量通信：学术界已经证明可行

| 论文 | 核心机制 | 实测结果 |
|------|---------|---------|
| **Interlat**（2511.09149）| 传输 LLM 最后一层 hidden states | 24× 延迟缩短 |
| **LatentMAS**（2511.20639）| 训练无关，端到端隐层协作 | 4× 加速，70-80% token 减少 |
| **Vision Wormhole**（2602.15382）| 视觉编码器作为跨模型语义桥接 | 解决异构模型空间不对齐 |

**结论**：同族模型间的向量通信**今天就能工程实现**。跨模型、跨厂商的向量通信（Vision Wormhole 方案）也已有论文支撑，不需要等行业标准。

---

## 一、A-Chat 的定位与差异化

### 为什么不直接用 A2A？

A2A 很好，但它缺少三件关键的事：

| A2A 有 | A2A 没有 |
|--------|---------|
| Agent Card（能力发现）| ❌ 持久化多轮对话线程（Thread） |
| Task 委托（单次）| ❌ 渐进式语义压缩（文本→Schema→向量）|
| JSON-RPC 消息 | ❌ 隐空间向量通信（Latent Channel，远期研究方向） |
| HTTP/gRPC 传输 | ❌ 对话历史的 Context Memory Vector |

**A-Chat = A2A 兼容 + 以上四项能力。**

### 定位一句话

> A-Chat 是 agent 之间的"持久关系层"：
> 任何框架都能做单次任务委托，但支持 A-Chat 的 agent 可以跨平台维持长期对话关系——
> 住在微信的 agent 和住在飞书的 agent，无需用户换 App 就能持续协作。

---

## 二、协议分层架构

```
┌──────────────────────────────────────────────────────────┐
│  A-Chat Extension Layer（A-Chat 扩展层）                   │
│                                                          │
│  ┌─────────────────┐  ┌─────────────────────────────┐   │
│  │  Thread Layer   │  │  Latent Channel Layer        │   │
│  │  持久化对话线程  │  │  隐空间向量通信               │   │
│  │  · 多轮上下文   │  │  · Context Memory Vector     │   │
│  │  · 角色流动     │  │  · Hidden State 传输          │   │
│  │  · 对话历史     │  │  · Cross-model Adapter       │   │
│  └─────────────────┘  └─────────────────────────────┘   │
│                                                          │
│              Progressive Semantic Compression            │
│         Text ──→ Structured Schema ──→ Latent Vector     │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  A2A Protocol（任务委托层，直接复用，不重造）               │
│  Agent Card · Task · Artifact · JSON-RPC · HTTP/SSE/gRPC │
├──────────────────────────────────────────────────────────┤
│  ANP / W3C DID（身份与发现层，直接复用，不重造）            │
│  Decentralized Identity · Capability Discovery           │
└──────────────────────────────────────────────────────────┘
```

---

## 三、渐进式语义压缩（PSC）

这是 A-Chat 最核心的设计。

**同一条消息，支持三种语义密度：**

```
Level 0 — 自然语言（向下兼容所有 agent）
"请帮我分析一下最近的用户数据，找出留存率下降的原因"

Level 1 — 结构化 Schema（零歧义，零 token 解析）
{
  "intent": "ANALYZE",
  "capability_id": "data_analysis",
  "payload": {
    "dataset": "user_retention",
    "time_range": "last_30_days",
    "target_metric": "retention_rate",
    "objective": "find_root_cause"
  }
}

Level 2 — 隐空间向量（极致效率，同族模型直接处理）
{
  "latent": <Float32Array, 8192 dims>,  // LLM 最后一层 hidden states
  "compression": "interlat_v1",
  "token_count": 8,                     // 从 50+ 词压缩到 8 个向量
  "model_family": "claude"
}
```

接收方按自身能力**自动选择最高支持的语义层**：
- 普通 agent → Level 0（文字）
- 支持 A-Chat Schema 的 agent → Level 1（结构化）
- 同族支持 Latent Channel 的 agent → Level 2（向量）

**消息中三层并存，接收方取其所能理解的最高层。**

---

## 四、身份层：直接使用 W3C DID

**不自建身份体系。直接使用 ANP 已经实现的 W3C DID 标准。**

```
Agent DID 示例：
did:wba:example.com:user:alice   （基于 Web，与 ANP 兼容）
did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK  （纯密钥，去中心化）
```

Capability Card 完全兼容 A2A Agent Card 格式，额外扩展 A-Chat 能力声明：

```json
{
  "name": "3D-DigitalMe",
  "url": "https://digital-me.agent.example.com",
  "description": "Social media content specialist",
  "capabilities": {
    "a2a": {
      "streaming": true,
      "pushNotifications": true,
      "stateTransitionHistory": false
    },
    "achat": {
      "thread": true,
      "psc_level": 2,
      "latent_channel": {
        "enabled": true,
        "model_family": "claude",
        "embedding_dim": 4096,
        "compression": "interlat_v1"
      }
    }
  },
  "skills": [
    {
      "id": "content_generation",
      "inputModes": ["text", "schema", "latent"],
      "outputModes": ["text", "schema", "latent"]
    }
  ]
}
```

---

## 五、Thread Layer（对话线程）

### 与 A2A Task 的本质区别

```
A2A Task：   发起 → 执行 → 结束（单程）
A-Chat Thread：开始 → 持续对话 → 可能永远不"结束"（对话即关系）
```

### Thread 消息格式（兼容 A2A，扩展 PSC）

```typescript
interface AchatMessage {
  // A2A 兼容字段
  kind: "message";
  messageId: string;
  taskId: string;           // thread_id
  role: "agent";
  parts: MessagePart[];     // A2A 标准 Part 格式

  // A-Chat 扩展字段
  "x-achat": {
    intent: IntentType;     // SAY | ASK | PROPOSE | DECIDE | DELEGATE | UPDATE | BLOCK
    psc_level: 0 | 1 | 2;  // 当前消息使用的语义层
    schema_payload?: Record<string, unknown>;  // Level 1
    latent_payload?: {                          // Level 2
      data: string;         // base64 encoded Float32Array
      dim: number;
      compression: string;
      model_family: string;
    };
    context_vector?: string; // 对话历史压缩向量（base64 Float32Array）
    reply_to?: string;
    thread_meta?: {
      participants: string[];
      topic_label: string;
    };
  };
}
```

### Thread 状态机

```
OPEN → ACTIVE → RESOLVED
         ↓          ↑
       BLOCKED ──────┘
         ↓
       ARCHIVED（7天无活动）
```

---

## 六、Latent Channel（向量通信层）

基于 Interlat 论文的工程实现路径：

### Phase A：同族模型（今天可做）

```
发送方（Claude-3.x）：
  1. 运行推理，收集 last hidden states H = [h₁...h_L]
  2. 压缩：H_compressed = Interlat_compress(H, target_k=8)
  3. 序列化：base64(Float32Array(H_compressed))
  4. 附加到消息 x-achat.latent_payload

接收方（Claude-3.x，同族）：
  1. 反序列化：Float32Array from base64
  2. 注入：H → Communication Adapter → embedding sequence
  3. 继续推理，直接"读懂"发送方意图（无需 token 解码-编码往返）
```

**收益**：同族模型间通信，token 消耗减少 70-80%，延迟缩短 4-24×。

### Phase B：跨模型（Vision Wormhole 方案）

使用视觉编码器作为语义桥接：
- 不同 VLM（视觉语言模型）的视觉 token 输入空间天然对齐
- 将文本 hidden state 投影到视觉 token 空间，再跨模型传递
- 避免 N(N-1) pairwise adapter 的二次复杂度问题

### Phase C：Universal Semantic Space（等行业收敛）

当行业出现类 ImageBind 的 Universal Semantic Embedding 时，直接接入。Capability Card 中的 `latent_channel.model_family` 字段届时扩展为 `universal_space_id`。

---

## 七、传输层：可插拔设计（继承 A2A）

A-Chat 完全复用 A2A 的传输层设计，不重复造轮子：

| 场景 | 传输 | 说明 |
|------|------|------|
| 跨网 agent | HTTPS + SSE | A2A 标准，穿透 NAT |
| 局域网 | HTTP/2 + WebSocket | 持久连接，低延迟 |
| 同机 | Unix Socket | A-Chat 本地优化 |
| 离线/异步 | File（JSONL）| MetaMe 内部使用 |
| 去中心化 | libp2p（ANP 兼容）| 未来扩展 |

---

## 八、防滥用机制

```typescript
const ACHAT_LIMITS = {
  // Thread 限制
  max_messages_per_thread_per_hour: 10,
  max_active_threads_per_agent: 5,
  max_participants_per_thread: 5,
  max_thread_age_days: 7,

  // Latent Channel 限制
  max_latent_payload_kb: 512,           // 8个向量 × 4096dim × 4bytes ≈ 128KB，留余量
  latent_only_for_same_family: true,    // Phase A 阶段：只允许同族模型用向量通道

  // 继承 A2A
  chain_depth_max: 3,
};
```

---

## 九、王总视角（MetaMe 参考实现）

```
/thread list              → 查看所有活跃对话线程
/thread show <id>         → 查看对话历史（含 PSC 级别标注）
/thread new <agents> <topic> → 创建新线程
/thread join <id>         → 加入线程（王总作为人类参与者）
/latent status            → 查看向量通信能力（哪些 agent 对支持）
```

---

## 十、实施计划

### Phase 0（1周）：Thread + A2A 兼容
- 实现 Thread 协议，消息格式兼容 A2A
- PSC Level 0（文本）+ Level 1（Schema）
- MetaMe 内部跑通（Unix Socket 传输）
- `/thread` 系列命令

### Phase 1（2周）：标准化身份
- 集成 W3C DID（使用 `did:key` 方法，最简实现）
- Capability Card 发布到 HTTPS 端点
- 与 A2A 互通测试

### Phase 2（1月）：Platform Bridge + Context Memory Vector

**Platform Bridge（GTM 关键步骤，与 DID 并行）**
- 飞书 Bot 作为第一个 Bridge 实现（企业开发者多，API 开放）
- 消息格式双向转换：飞书消息 ↔ A-Chat Thread 消息
- 身份映射：飞书 user_id → DID（单向绑定）
- 目标 demo：**飞书 Bot A ↔ A-Chat 协议 ↔ 飞书 Bot B 跨租户通信**
- 这是拉到第一批开发者的核心演示

**Context Memory Vector**
- 实现对话历史的 embedding 压缩
- `context_vector` 字段启用
- 同族模型间（Claude-Claude）验证节省 token

### Phase 3（3月）：开放生态
- 独立 npm 包：`@achat/core`（A2A 兼容 + A-Chat 扩展）
- 提交 A2A 社区 RFC（Thread + PSC 作为扩展提案）
- 微信 Bridge（复杂度高，排在飞书之后）

### 远期研究方向（不列入时间承诺）：Latent Channel

> ⚠️ 依赖前提：需要模型厂商（Anthropic/OpenAI）开放 hidden states API，
> 当前 Claude API 不暴露此接口，开发者无法获取。列为研究方向，待行业条件成熟后启动。

- 实现 Interlat 压缩算法（同族模型）
- PSC Level 2 启用
- 开源 `@achat/latent-channel` SDK
- Vision Wormhole 跨模型适配器

---

## 十一、终极形态：Agent Internet 全栈生态

> 当前我们只实现基础通信（Phase 0）。
> 但今天的每一个设计决策，都必须为这张蓝图留好接口。

### 11.1 全景图：Agent 文明的七层生态

```
┌──────────────────────────────────────────────────────────────┐
│  7. Agent 生活层（Lifestyle）                                  │
│     餐厅/地图/点评/预约 — "Agent 版大众点评"                   │
│     Agent 访问真实世界服务的统一接口                            │
├──────────────────────────────────────────────────────────────┤
│  6. Agent 资讯层（Information）                                │
│     新闻订阅 / 朋友圈 / Agent 动态 — "Agent 版朋友圈"          │
│     Agent 发布自己的成果、动态、研究结论                        │
├──────────────────────────────────────────────────────────────┤
│  5. Agent 商业层（Commerce）                                   │
│     能力市场 / 数据交易 / SLA 合约 — "Agent 版淘宝"            │
│     Agent 买卖服务、数据、计算资源                              │
├──────────────────────────────────────────────────────────────┤
│  4. Agent 金融层（Finance）                                    │
│     Agent Pay / 微支付 / 托管 / 结算 — "Agent 版支付宝"        │
│     Agent 之间直接支付、拆账、托管、争议仲裁                    │
├──────────────────────────────────────────────────────────────┤
│  3. Agent 社交层（Social）                                     │
│     关注 / 声誉评分 / 背书 / 协作历史 — "Agent 版微博"          │
│     Agent 的公开身份、口碑、可信度                              │
├──────────────────────────────────────────────────────────────┤
│  2. Agent 协作层（Collaboration）                              │
│     Task 委托 / Thread 对话 / 多播 — A2A + A-Chat 扩展         │
│     ← 当前 Phase 0 聚焦在这一层                                │
├──────────────────────────────────────────────────────────────┤
│  1. Agent 基础层（Foundation）                                 │
│     DID 身份 / 向量通信 / 传输 — ANP + Latent Channel          │
│     Agent 的最小可信单元：我是谁、我能做什么、我怎么说话         │
└──────────────────────────────────────────────────────────────┘
```

### 11.2 各层产品形态

#### Layer 4：Agent Pay（支付层）
- Agent 有原生钱包（绑定 DID，密钥即账户）
- 服务调用自动触发微支付（类似 API 按次计费，但 agent 自主结算）
- 托管合约：A 委托 B 完成任务，预付款托管，完成后自动释放
- 争议仲裁：引入第三方裁决 agent（DAO 化）
- 货币层：稳定币优先（USDC/USDT），或平台积分（前期过渡）

#### Layer 5：Agent Commerce（商业层）
- Capability Marketplace：agent 发布自己的能力，定价，接单
- 数据交易所：agent 出售训练数据、分析结果、私有知识库
- SLA 合约：能力调用附带服务等级协议，违约自动触发赔偿
- 搜索与发现：按领域/评分/价格搜索全球 agent 能力

#### Layer 6：Agent Moments（资讯/社交层）
- Agent 可以发布"动态"：任务完成公告、研究发现、市场洞察
- 关注图谱：agent 可以关注其他 agent，形成信息流
- 朋友圈：类似微信朋友圈，但发布方是 agent，订阅方也是 agent
- 新闻聚合：全球 agent 的公开动态按话题聚合，形成 agent 版新闻

#### Layer 7：Agent Services（生活服务层）
- Agent 访问真实世界服务的标准接口：餐厅、地图、机票、酒店
- "Agent 版大众点评"：标准化服务查询 Schema，任何服务商接入
- 代理执行：agent 代替用户完成预约、下单、支付全流程
- 服务质量反馈：自动收集 agent 的体验数据，形成服务评分

### 11.3 今天的设计决策如何为未来铺路

这是最关键的部分——**Phase 0 做什么、不做什么，直接决定以后是否要推倒重来**。

| 未来层 | 今天必须预留的设计 | 如果今天没做的代价 |
|--------|-------------------|------------------|
| **支付层** | DID = 钱包地址（密钥即账户）；消息必须有签名（不可抵赖）；Capability Card 必须有 `pricing` 字段（哪怕今天填 null） | 支付绑定另一套身份体系，DID 和钱包双轨并存，永久技术债 |
| **商业层** | Capability Card 中的 `skills` 必须有结构化 inputSchema/outputSchema（不能是自由文字）；能力版本化（semver） | 无法自动匹配买家需求和卖家能力，商城变成人工搜索 |
| **社交/声誉层** | 每条消息必须有签名，形成不可篡改的交互历史；Thread 需要有 `visibility` 字段（public/private/group）| 无法回溯声誉，声誉体系从零开始，无历史数据 |
| **生活服务层** | 消息 payload 支持结构化 Schema（Level 1 PSC）；Capability Card 的 skills 支持 `domain` 分类 | 服务接入靠自然语言解析，误差率高，无法规模化 |
| **向量通信** | 消息格式的 `x-achat` 扩展字段今天就要存在（哪怕内容为空）；model_family 字段要规范化 | 未来加向量层需要改消息格式，导致协议版本断裂 |

### 11.4 今天就要加进去的"小决策"

以下改动成本极低，但不做则后悔：

**1. Capability Card 加 pricing 字段（今天填 null）**
```json
"pricing": {
  "model": "per_call",         // per_call | subscription | free
  "currency": null,            // USDC | platform_credit | null(免费)
  "unit_price": null           // 0.001
}
```

**2. 消息加 visibility 字段（今天默认 private）**
```json
"x-achat": {
  "visibility": "private",     // private | group | public
  ...
}
```

**3. Thread 加 topic_tags 结构化标签（今天为空数组）**
```json
"topic_tags": ["content_strategy", "Q2", "budget"]
// 今天不用，未来做资讯聚合和社交发现的基础
```

**4. 每个 skill 加 domain 分类（今天用标准值）**
```json
"skills": [{
  "id": "content_generation",
  "domain": "media",           // media | finance | tech | lifestyle | ...
  "tags": ["xiaohongshu", "viral", "storytelling"]
}]
```

**5. 消息签名必须实现（今天就做，不是"后来补"）**
- 签名是支付不可抵赖的前提
- 签名是声誉体系的信任基础
- 签名成本极低（Ed25519），推迟只有坏处没有好处

---

## 十二、一句话定位

> **A-Chat 今天是 agent 的通信协议，明天是 agent 文明的基础设施。**
> 从 Thread 和 Platform Bridge 起步，身份、支付、社交、商业、服务逐层生长。
> 每一层都依赖下一层的正确设计——所以今天要做对，不要做多。

---

## 参考文献

- [Google A2A Protocol](https://a2a-protocol.org/latest/)
- [A2A GitHub](https://github.com/a2aproject/A2A)
- [ANP Agent Network Protocol](https://github.com/agent-network-protocol/AgentNetworkProtocol)
- [Interlat 论文 arXiv:2511.09149](https://arxiv.org/abs/2511.09149)
- [LatentMAS 论文 arXiv:2511.20639](https://huggingface.co/papers/2511.20639)
- [Vision Wormhole 论文 arXiv:2602.15382](https://arxiv.org/html/2602.15382v1)
- [四协议综述 arXiv:2505.02279](https://arxiv.org/html/2505.02279v1)
- [ACP 并入 A2A 公告](https://lfaidata.foundation/communityblog/2025/08/29/acp-joins-forces-with-a2a-under-the-linux-foundations-lf-ai-data/)
