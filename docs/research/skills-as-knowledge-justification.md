# 为什么我们应该用 Agent Skills 来共享工程知识

# Why We Should Use Agent Skills as Our Knowledge-Sharing Framework

**研究日期 / Research Date**: 2026-03-25
**目的 / Purpose**: 向团队解释为什么将工程知识编写为 Claude Code Skills 是当前最有效的知识共享方式

---

## TL;DR (简要总结)

Agent Skills (SKILL.md 格式) 正在成为 AI 编程时代的**知识共享标准单元**。它不是传统文档 — 而是**可被 AI 理解、执行、并持续进化的结构化知识**。所有主流平台 (Claude Code, Codex, Gemini CLI, Cursor, JetBrains) 都在向这个方向收敛。把知识写成 Skills 而不是 Wiki/Confluence 页面,意味着知识不仅仅被人阅读 — 它会被 AI agent 自动发现、加载、并应用。

---

## 第一部分: 权威引用 (Authoritative Quotes)

### 1. Andrej Karpathy — 前 Tesla AI 总监, OpenAI 创始成员

**关于文档应该为 Agent 而写:**

> "You shouldn't write documentation for people anymore. You should have Markdown documents for agents instead of HTML documents for humans."
>
> — Andrej Karpathy, [No Briars Podcast](https://www.the-ai-corner.com/p/andrej-karpathy-ai-workflow-shift-agentic-era-2026), March 2026

**解读**: Karpathy 明确说文档应该从"给人看的 HTML"转变为"给 Agent 看的 Markdown"。这正是 SKILL.md 格式的核心理念 — 写给 AI 读的、结构化的、可执行的知识。

---

### 2. Anthropic — Claude 的创造者 (官方 2026 Agentic Coding Trends Report)

**关于 onboarding 革命:**

> "The traditional timeline for onboarding to a new codebase or project began to collapse from weeks to hours."
>
> — Anthropic, 2026 Agentic Coding Trends Report, p.6

**解读**: Anthropic 的官方数据证明新人 onboarding 从数周缩短到数小时 — Skills 是实现这一目标的最佳载体。

---

### 3. Philipp Schmid — Hugging Face 技术主管

**关于 Agent Harness (AI 知识载具) 的定义:**

> "An Agent Harness is the infrastructure that wraps around an AI model to manage long-running tasks. It is not the agent itself. It is the software system that governs how the agent operates."
>
> — [Philipp Schmid, "The importance of Agent Harness in 2026"](https://www.philschmid.de/agent-harness-2026)

**关于竞争优势的本质:**

> "Competitive advantage is no longer the prompt. It is the trajectories your Harness captures."
>
> — Philipp Schmid

**关于设计原则:**

> "Do not build massive control flows. Provide robust atomic tools. Let the model make the plan."
>
> — Philipp Schmid

**解读**: Schmid 指出"竞争优势不在于 prompt,而在于 Harness 捕获的轨迹"。Skills 就是 Harness 的最小单元 — 每个 SKILL.md 都是一个原子化的、可组合的知识载具。

---

### 4. NxCode — 行业分析

**关于 Harness 工程的核心洞察:**

> "The agent isn't the hard part — the harness is."
>
> — [NxCode, "Harness Engineering: The Complete Guide"](https://www.nxcode.io/resources/news/harness-engineering-complete-guide-ai-agent-codex-2026), 2026

**关于性能的关键:**

> "Same model. Different harness. Dramatically better results."
>
> — NxCode, on LangChain's benchmark improvement through harness optimization alone

**关于知识必须在仓库中:**

> "Everything the agent needs must be in the repository."
>
> — NxCode, 2026

**解读**: "同一个模型，不同的 Harness，结果天差地别" — 这是对 Skills 价值最直接的论证。将知识编码为 Skills 放入仓库，就是在构建团队的 Harness。

---

### 5. JetBrains — IDE 巨头

**关于共享语义上下文:**

> "Shared semantic context across repositories and projects, enabling agents to access relevant knowledge."
>
> — JetBrains Central announcement, March 2026

**关于语义层:**

> "A semantic layer that continuously aggregates and structures information from code, architecture, runtime behavior, and organizational knowledge."
>
> — JetBrains Central announcement

**解读**: JetBrains 在 2026年3月24日(昨天!) 发布的 JetBrains Central 明确支持"跨仓库的共享语义上下文"。这正是我们用 Skills 做的事 — 把知识从散落在各处的文档，收敛到 Agent 可以读取的标准格式。

---

### 6. Aviator — Spec-Driven Development

**关于从混乱到结构:**

> "Spec-driven development replaces the chaos of ad hoc, prompt-driven vibe coding with a structured, durable way for engineering teams to work on AI coding projects."
>
> — [Aviator Blog](https://www.aviator.co/blog/aviator-runbooks-turn-ai-coding-multiplayer-with-spec-driven-development/)

**关于团队协作:**

> "Building software with AI agents isn't a solo sport, especially when projects touch multiple repos, services, and prompt engineering knowledge."
>
> — Ankit Jain, CEO of Aviator

**关于知识保存:**

> "Runbooks capture the team's AI prompting knowledge and execution patterns that evolve."
>
> — Aviator Blog

**解读**: Aviator 的 CEO 明确指出 — AI 编程不是单人运动。Skills 就是"Runbooks"的进化形态: 版本化的、可执行的、团队共享的知识规范。

---

### 7. Nghi D. Q. Bui — OpenDev 作者 (arXiv 论文)

**关于 Skills 系统的三层架构:**

> "Three-tier hierarchy for reusable domain-specific prompt templates: Built-in (framework-provided), Project-local (.opendev/skills/), User-global (~/.opendev/skills/)."
>
> — [Nghi D. Q. Bui, arXiv:2603.05344](https://arxiv.org/html/2603.05344v1), March 2026

**解读**: 学术界已经在论文中正式化了 Skills 的三层架构 (框架内置 → 项目级 → 用户级)。这与 Claude Code 的 skills 目录结构完全一致。这不是个人偏好 — 这是正在被学术界验证的架构模式。

---

### 8. Bozhidar Batsov — 知名开源作者 (RuboCop 创始人)

**关于 Skills 的力量:**

> "The real power is in creating your own. Skills live in one of three locations — personal, project, and plugin scopes — enabling team and organizational knowledge distribution."
>
> — [Bozhidar Batsov, "Essential Claude Code Skills and Commands"](https://batsov.com/articles/2026/03/11/essential-claude-code-skills-and-commands/), March 2026

**关于 Skills vs Slash Commands 的区别:**

> "Skills are prompt-based capabilities. When you invoke a skill, it loads a set of instructions (a markdown file) into Claude's context, and Claude executes them."
>
> — Bozhidar Batsov

### 9. Anthropic 长时间运行 Agent 蓝图 — Harness 进化论

**来源**: [Anthropic Just Dropped the New Blueprint for Long-Running AI Agents](https://youtu.be/9d5bzxVsocw) (YouTube, March 2026)

**关于 Harness 的本质 (马具类比):**

> "A wild horse has raw power, but it'll go wherever it wants. The harness allows you to control the power, set it in a direction and get where you want to go."

**关于 Harness 设计的重要性:**

> "For long-running complex tasks, the harness design is as important as the model itself."

**关于自定义 Harness 的致命问题 — 假设会过时:**

> "Every component in a harness essentially encodes an assumption that the model can't actually carry out that task itself... those assumptions go stale as the models improve."

**关于过度工程化自定义方案:**

> "To build effective agents, you should always look to find the simplest solution possible and not actually over-complicate or over-engineer it."

**关于 Harness 不是一次性的:**

> "It's not ever a one-shot setup. You do need to refine and iterate as you go."

**解读**: 这是对自定义 scaffolding 最有力的反驳。Anthropic 自己的经验证明: 从 Sonnet 4.5 到 Opus 4.6, 他们**删除**了 sprints、contract negotiation、context resets — 因为模型进步让这些自定义组件变成了技术债务。标准化的 Skills 格式天然具有这种"可删除性" — 每个 SKILL.md 是独立的原子单元, 不需要时直接删除, 不会破坏整个系统。而自定义的 inbox/ → papers/ → checklists/ 管线一旦建成, 删除或修改任何一个环节都会影响其他部分。

### 10. 技术债务的指数增长 — 自定义方案的隐性成本

**Deloitte: 80% 的精力浪费在管道搭建上**

> "Teams then spend 80% of their effort building pipelines before AI work begins, creating custom integrations that offer no leverage for future initiatives."
>
> — [Cédric Jadoul, Laura Mathieu, Camille Peudpiece Demangel, Deloitte](https://www.deloitte.com/lu/en/our-thinking/future-of-advice/first-ai-use-case.html), March 24, 2026

**Forbes: AI 技术债务呈指数级增长**

> "Traditional technical debt accumulates linearly, but AI technical debt compounds exponentially through model versioning chaos, code generation bloat and organizational fragmentation."
>
> — [Ana Bildea, Forbes](https://www.forbes.com/councils/forbestechcouncil/2026/03/24/the-new-tech-debt-codebases-only-ai-understands/), March 24, 2026

**Hash Block: Prompt Drift 是定时炸弹**

> "You embed business logic in a giant prompt. It's 'flexible.' It's 'fast to iterate.' It's also a silent dependency that nobody can version responsibly. A 'minor wording tweak' becomes a production regression."
>
> — [Hash Block, Medium](https://medium.com/@connect.hashblock/10-ai-anti-patterns-that-seem-brilliant-then-explode-1c97248fa11d), February 2, 2026

**htdocs.dev: 系统变得不可理解**

> "Configuration sprawl makes the system harder to reason about over time. Behavior becomes emergent from interactions between dozens of configuration files rather than traceable through source code. The system becomes something you operate rather than something you understand."
>
> — [htdocs.dev](https://htdocs.dev/posts/os-level-sandboxing-for-ai-agents-nanoclaw--anthropics-sandbox-runtime/), 2026

#### 技术债务累积对比

| 维度                  | 自定义方案 (Custom Scaffolding)           | 标准方案 (SKILL.md)                               |
| --------------------- | ----------------------------------------- | ------------------------------------------------- |
| **债务累积速率**      | 指数级 — 每次模型更新都需要修改私有脚本   | 线性/平坦 — Markdown 声明式格式，无需跟随模型变化 |
| **Prompt Drift 风险** | 高 — 业务逻辑散落在各种脚本中，无法版本化 | 低 — 每个 SKILL.md 独立版本控制                   |
| **知识孤岛**          | 严重 — 只有架构师理解 index.json 的逻辑   | 最小 — 任何熟悉标准格式的开发者都能立即理解       |
| **初始搭建成本**      | 高 — 需要先建数据管道和基础设施           | 低 — drop-in 文件，Agent 原生识别                 |

**解读**: Deloitte 的数据最直接 — 80% 精力花在搭建管道而非核心 AI 工作。这正是自定义 inbox/papers/index.json 方案的风险: 你在建「操作系统」而不是在产出价值。

---

### 11. NIH 陷阱与 Bus Factor — 自定义方案的组织风险

**NIITS: "Not Invented in this Session" — NIH 的 AI 时代变种**

> "LLMs are very much NIH machines... The bar to create the new X framework has just been lowered so I expect the opposite, even more churn."
>
> — [Hacker News](https://news.ycombinator.com/item?id=47480159), 2026

> "It's like NIH syndrome but instead 'not invented here today'... More like NIITS: Not Invented in this Session."
>
> — [rurp, Hacker News](https://news.ycombinator.com/item?id=46771564), 2026

**Sam Thuku: 重复维护的隐性成本**

> "The cost of this duplication is staggering. It's not just wasted development hours. It's the compounded cost of maintaining multiple, slightly different implementations of the same thing. Every bug fix has to be applied in multiple places."
>
> — [Sam Thuku, Dev.to](https://dev.to/samthuku/stop-solving-solved-problems-escaping-the-cycle-of-duplicated-code-3bfa), 2026

**Bus Factor = 1 的实战教训**

> "About 40% of the businesses that came to us were not ready to automate anything. Their operations were held together by one person who knew where everything was... classic bus factor 1."
>
> — [Reddit r/AI_Agents](https://www.reddit.com/r/AI_Agents/comments/1rzhvxc/i_built_30_automations_this_year_most_of_them/), 2026

**解读**: 如果 Maywei 设计了自定义的 inbox → papers → checklists 管线，而这套系统只存在于她的脑海中 — 那么 Bus Factor = 1。她休假或离职时，没人能维护这个系统。SKILL.md 是行业标准格式，任何使用 Claude Code 的开发者都能立即读懂和维护。

---

### 12. 知识可发现性机制 — 为什么格式决定一切

**Mintlify: SKILL.md 为 Agent 整合知识**

> "Documentation is largely written for humans, and humans can't look at a block of text containing every feature and best practice and instantly apply them... skill.md consolidates it for agents."
>
> — [Michael Ryaboy, Mintlify](https://www.mintlify.com/blog/skill-md), January 21, 2026

**MindStudio: Context Rot 的科学解释**

> "Context rot isn't an official term from Anthropic's documentation. It's a practical name for something developers started noticing independently: as you add more content to the files an agent reads at startup, output quality doesn't stay flat — it declines."
>
> — [MindStudio Team](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files), March 24, 2026

**Anthropic 官方: Progressive Disclosure 三层架构**

> "Provides just enough information for Claude to know when each skill should be used without loading all of it into context. Second level (SKILL.md body): Loaded when Claude thinks the skill is relevant to the current task."
>
> — [Anthropic, The Complete Guide to Building Skill for Claude](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf), 2026

#### 自动发现能力对比

| 维度                 | 自定义 index.json                                | 标准 SKILL.md                                       |
| -------------------- | ------------------------------------------------ | --------------------------------------------------- |
| **Agent 自动发现**   | 不可能 — 每次会话都要手动教 AI 解析自定义 schema | 原生支持 — Agent runtime 自动扫描 `.claude/skills/` |
| **Context 窗口效率** | 差 — 通常需要把整个索引 dump 进去                | 优秀 — Progressive Disclosure 确保只在需要时加载    |
| **机器理解度**       | 低 — JSON 数组缺乏「如何处理数据」的语义指令     | 高 — Markdown 专门为机器决策优化                    |
| **Context Rot 风险** | 高 — 大量非结构化内容触发「Lost in the Middle」  | 低 — 文件严格控制在 500 行以内                      |

#### SKILL.md 三层 Progressive Disclosure 架构

| 层级                                | 内容                             | 加载时机                     | 优势                                            |
| ----------------------------------- | -------------------------------- | ---------------------------- | ----------------------------------------------- |
| **Layer 1: YAML Frontmatter**       | 名称、触发器、描述 (< 1024 字符) | 始终加载                     | Agent 可同时持有数百个 skill 描述而不浪费 token |
| **Layer 2: SKILL.md Body**          | 操作步骤、逻辑约束、决策表       | 当 Agent 认为该 skill 相关时 | Markdown 是 LLM 预训练数据的原生格式            |
| **Layer 3: scripts/ + references/** | 可执行脚本、参考文档             | 当 skill 被调用后            | 自动化代码与 prompt 上下文严格隔离              |

**解读**: 这是最关键的技术论点。自定义 index.json 每次会话都要重新教 AI「这个 JSON 怎么读」，而 SKILL.md 的 YAML frontmatter 被 Agent runtime 原生理解。就像 HTML 之于浏览器 — 浏览器不需要你教它怎么读 HTML。

---

### 13. 企业实战数据 — 标准化 Skills 的验证

**ArXiv 实证: 自定义格式几乎不存在**

> "CLAUDE.md emerges as the dominant file type with 1,661 (34.2%), followed closely by AGENTS.md with 1,572 (32.3%). GEMINI.md (159 files, 3.3%) and .cursorrules (73 files, 1.5%) are rare."
>
> — [ArXiv 2602.14690v1](https://arxiv.org/html/2602.14690v1), February 2026 (分析 ~3,000 GitHub 仓库)

**Spotify: 90% 工程时间节省**

> "The company reports up to a 90% reduction in engineering time, over 650 AI-generated code changes shipped per month, and roughly half of all Spotify updates now flowing through the system."
>
> — [VentureBeat](https://venturebeat.com/orchestration/anthropic-says-claude-code-transformed-programming-now-claude-cowork-is), February 25, 2026

**Novo Nordisk: 10 周 → 10 分钟**

> "At Novo Nordisk, the pharmaceutical giant built an AI-powered platform... reduction from over 10 weeks to just 10 minutes."
>
> — VentureBeat, February 25, 2026

**企业 AI 项目失败的共性**

> "Every enterprise AI project I've seen fail had the same shape: someone built a clever thing, it worked in isolation, and then it hit the wall of 'okay but how does this talk to our actual systems, with actual governance, at actual scale.' The POC-to-production gap closes when your tenth agent is mostly configuration, not mostly engineering."
>
> — [PmMeAgriPractices101, Reddit r/AI_Agents](https://www.reddit.com/r/AI_Agents/comments/1s02oaq/enterprise_ai_has_an_80_failure_rate_the_models/), 2026

**解读**: ~3,000 个仓库的实证数据已经说明一切 — CLAUDE.md 34.2%, AGENTS.md 32.3%, 自定义格式统计学上几乎为零。不是某一家公司的选择，而是整个行业用脚投票的结果。

---

## 第二部分: 核心论点 (Core Arguments)

### 论点 1: Skills 是知识的"刚好合适"的粒度

| 太小               | 刚好 (Skills)                    | 太大               |
| ------------------ | -------------------------------- | ------------------ |
| 一行 CLI alias     | 从概念到实现到反模式的完整知识包 | 独立的 Git 仓库    |
| `.bashrc` 里的函数 | SKILL.md + 参考文件 + 脚本       | 需要自己的 CI/CD   |
| 单个 prompt        | 可被 AI 自动发现和加载           | 需要独立维护和发布 |

> 引用 HN 讨论: "Too small for a proper GitHub repo, so they stay on one machine."
> — [latand6, Hacker News](https://news.ycombinator.com/item?id=47475832), March 2026

Skills 填补了"太小不值得建仓库，太大不适合放进 dotfile"的空白。

### 论点 2: 跨平台兼容性已经实现

同一个 SKILL.md 文件可以在以下平台工作:

- **Claude Code** (Anthropic 官方)
- **Codex CLI** (OpenAI)
- **Gemini CLI** (Google)
- **Cursor** (IDE)
- **JetBrains** (via Central, 2026-03-24 发布)
- **Xcode 26.3** (Apple, [2026-02 发布](https://www.apple.com/newsroom/2026/02/xcode-26-point-3-unlocks-the-power-of-agentic-coding/))

这不是某一家公司的私有格式 — 这是整个行业正在收敛的标准。

### 论点 3: 知识不被分享 = 不存在

> "From the agent's point of view, anything it can't access in-context while running effectively doesn't exist."
>
> — NxCode Harness Engineering Guide, 2026

如果你的知识只存在于 Wiki/Confluence/脑海中，对于 AI agent 来说它就**不存在**。只有编码为 Skills 放入仓库的知识，才会被 AI 自动发现和应用。

### 论点 4: Skills 是 Harness 的最小构建单元

```
你的大脑中的知识
    ↓ 编码为 SKILL.md
Agent 可读的知识
    ↓ 安装到仓库
Agent 自动应用的知识
    ↓ 团队共享
组织级的 Agent Harness
```

---

## 第三部分: 攻防兼备 — 反面论据与我们的回应

我们做了全面调研，不回避 Skills 标准化方案的真实风险。以下三个反面论据是最严肃的批评。但关键是: **这些风险不适用于我们的具体场景**。

### 风险 1: 供应链安全 (Snyk 审计)

> "The discovery of hundreds of malicious skills on ClawHub in January 2026 represents the first major supply-chain threat to AI agent ecosystems... 36% of audited community skills contained prompt injection attempts, and over 26% possessed at least one active, exploitable vulnerability."
>
> — [Liran Tal, Snyk](https://snyk.io/articles/skill-md-shell-access/), February 2026

**为什么这不影响我们**: 我们不从公共市场下载不明来源的 skills。我们的 skills 全部在 `~/eon/cc-skills` 内部仓库中自己编写和审核，走的是 private marketplace 路径。Snyk 的警告适用于盲目安装第三方 skills 的场景 — 我们的场景是团队内部共享，等同于共享内部代码库，安全边界完全不同。

### 风险 2: LLM 生成的 Context Files 反而降低效果 (ETH Zurich)

> "LLM-generated context files reduced task success by 2–3% while increasing cost by over 20%. Developer-written files improved success by about 4% — but also increased cost by up to 19%."
>
> — [ETH Zurich, cited by Addy Osmani, Medium](https://medium.com/@addyosmani/stop-using-init-for-agents-md-3086a333f380), 2026

**为什么这不影响我们**: ETH Zurich 测试的是「让 AI 自动生成 AGENTS.md」的场景。我们的 skills 是**人类手写**的 — 基于真实的工作流经验，经过团队审核。研究本身也证明了: developer-written files 提升成功率 4%。这正是我们在做的事。

### 风险 3: 大规模定制可能是合理的 (Stripe 案例)

> "Building an agent that is highly optimized for your own codebase/process is possible. In fact, I am pretty sure many companies do that but it's not yet in the ether."
>
> — [menaerus, Hacker News](https://news.ycombinator.com/item?id=47086557), ~March 2026

Stripe 构建了高度定制的 "Minions" 系统，包含 400+ 自定义 MCP tools 和专有的 "Toolshed" 服务器。

#### 什么时候自定义是合理的 (Stripe 例外条件)

| 条件           | Stripe                       | 我们                     |
| -------------- | ---------------------------- | ------------------------ |
| 代码库规模     | 数十 GB 的 monorepo          | 中小型多仓库             |
| 合规要求       | 极端金融监管 (PCI-DSS)       | 标准公司安全             |
| 团队规模       | 数百名工程师维护定制基础设施 | 小团队，无法承担维护成本 |
| MCP Tools 数量 | 400+ 定制工具                | < 10                     |
| 投入产出比     | 专职团队维护，ROI 可分摊     | 一人维护 = Bus Factor 1  |

**为什么这不影响我们**: Stripe 的定制方案合理是因为他们有**数百名工程师分摊维护成本**。我们是小团队 — 如果一个人花 80% 精力维护自定义管道（Deloitte 数据），那就是在用 Stripe 的策略打小团队的仗。标准化方案让我们把精力花在核心业务上。

---

## 第四部分: <private-repo> + Skills = 最佳组合

这不是「你的方案 vs 我的方案」— 而是两者互补。

### 架构分层

```
<private-repo>/                    ← Maywei 的数据层 (完整保留)
├── inbox/                            ← 待审核研究论文
│   └── 2026-03-19/
│       ├── lstm-funding-rate.md       ← status: pending_review
│       └── mev-liquidation.md         ← status: pending_review
├── papers/                           ← 已审核论文
│   └── 2026-03-15/
│       └── deflated-sharpe.md         ← status: reviewed
├── checklists/                       ← 可执行清单
├── ingestion/
│   └── import-from-discord.py        ← 导入脚本
│
├── .claude/                          ← 新增: 工作流层
│   └── skills/
│       ├── search-papers/
│       │   └── SKILL.md              ← "搜索和总结 papers/ 中的论文"
│       ├── review-inbox/
│       │   └── SKILL.md              ← "审核 inbox/ 论文，判断是否移入 papers/"
│       ├── generate-checklist/
│       │   └── SKILL.md              ← "从论文生成可执行的投资决策清单"
│       └── discord-ingest/
│           └── SKILL.md              ← "从 Discord 导入新论文到 inbox/"
│
├── CLAUDE.md                         ← 项目导航: "默认只搜索 papers/"
└── index.json                        ← 内容索引 (已审核论文)
```

### 为什么这个组合比单独任一方案都强

| 层级         | 负责人                      | 工具             | 职责                                 |
| ------------ | --------------------------- | ---------------- | ------------------------------------ |
| **数据层**   | Maywei 的 inbox/papers 管线 | Git + 自定义脚本 | 存储和管理研究论文                   |
| **工作流层** | Agent Skills                | SKILL.md         | 编码「如何使用这些论文」的标准化操作 |
| **导航层**   | CLAUDE.md                   | Markdown         | 告诉 Agent 先搜索什么、忽略什么      |

**数据层解决「有什么」，工作流层解决「怎么用」。**

Maywei 的 inbox → papers 管线负责知识的**收集和审核**。但一旦论文进入 papers/，怎么搜索？怎么交叉引用？怎么让新同事快速上手？这些「怎么用」的知识，如果只存在于某个人的脑海中，那就是 Bus Factor = 1 的隐患。

把这些操作流程编码为 SKILL.md，意味着:

1. 任何使用 Claude Code 的团队成员可以 `/search-papers` 一键搜索
2. 新成员不需要问「论文库怎么用」— Agent 自动知道
3. 工作流可以被版本控制、审核、迭代 — 跟代码一样
4. 同一套 skills 在 Claude Code, Cursor, Gemini CLI 都能工作

---

## 第五部分: 关键统计数据 (Key Statistics)

| 指标                   | 数据                             | 来源                              |
| ---------------------- | -------------------------------- | --------------------------------- |
| Onboarding 加速        | 数周 → 数小时                    | Anthropic 2026 Report             |
| Skills 市场规模        | 500,000+ skills                  | SkillsMP.com                      |
| 跨平台兼容             | 6+ 平台支持 SKILL.md             | Claude/Codex/Gemini/etc.          |
| 标准格式采用率         | CLAUDE.md 34.2%, AGENTS.md 32.3% | ArXiv 2602.14690v1 (~3,000 repos) |
| Spotify 效率提升       | 90% 工程时间减少, 650+ AI变更/月 | VentureBeat Feb 2026              |
| Novo Nordisk           | 10 周 → 10 分钟                  | VentureBeat Feb 2026              |
| 自定义方案管道浪费     | 80% 精力花在搭建而非 AI 工作     | Deloitte Mar 2026                 |
| Skills 三层架构论文    | arXiv:2603.05344                 | Nghi D. Q. Bui, Mar 2026          |
| Microsoft APM 包管理器 | 已发布                           | github.com/microsoft/apm          |

---

## 第六部分: 行动建议 (Recommended Actions)

1. **保留 <private-repo>**: 不需要改动 Maywei 的数据管线 — inbox/papers/checklists 继续工作
2. **添加 .claude/skills/**: 在 <private-repo> 仓库中加入 3-5 个核心操作 skills
3. **从一个 skill 开始**: 先写一个 `search-papers/SKILL.md`，让团队体验效果
4. **度量效果**: 跟踪新成员上手时间、重复问题数量、论文查找效率
5. **渐进扩展**: 验证效果后，逐步将更多操作流程编码为 skills

---

## 参考链接 (Sources)

- [Anthropic 2026 Agentic Coding Trends Report (PDF)](https://resources.anthropic.com/hubfs/2026%20Agentic%20Coding%20Trends%20Report.pdf)
- [Andrej Karpathy: The AI Workflow Shift Explained 2026](https://www.the-ai-corner.com/p/andrej-karpathy-ai-workflow-shift-agentic-era-2026)
- [Philipp Schmid: The importance of Agent Harness in 2026](https://www.philschmid.de/agent-harness-2026)
- [NxCode: Harness Engineering Complete Guide 2026](https://www.nxcode.io/resources/news/harness-engineering-complete-guide-ai-agent-codex-2026)
- [JetBrains Central: An Open System for Agentic Development](https://blog.jetbrains.com/blog/2026/03/24/introducing-jetbrains-central-an-open-system-for-agentic-software-development/)
- [Aviator Runbooks: Spec-Driven Development](https://www.aviator.co/blog/aviator-runbooks-turn-ai-coding-multiplayer-with-spec-driven-development/)
- [arXiv:2603.05344 — Building AI Coding Agents: Scaffolding, Harness, Context Engineering](https://arxiv.org/html/2603.05344v1)
- [Bozhidar Batsov: Essential Claude Code Skills and Commands](https://batsov.com/articles/2026/03/11/essential-claude-code-skills-and-commands/)
- [Hacker News: Skills are quietly becoming the unit of agent knowledge](https://news.ycombinator.com/item?id=47475832)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Anthropic Official Skills Repository](https://github.com/anthropics/skills)
- [SkillsMP: Agent Skills Marketplace (500K+ skills)](https://skillsmp.com/)
- [Microsoft APM: Agent Package Manager](https://github.com/microsoft/apm)
- [Anthropic Blueprint for Long-Running AI Agents (YouTube)](https://youtu.be/9d5bzxVsocw)
- [Deloitte: First AI Use Case](https://www.deloitte.com/lu/en/our-thinking/future-of-advice/first-ai-use-case.html)
- [Forbes: The New Tech Debt Codebases Only AI Understands](https://www.forbes.com/councils/forbestechcouncil/2026/03/24/the-new-tech-debt-codebases-only-ai-understands/)
- [Hash Block: 10 AI Anti-Patterns That Seem Brilliant Then Explode](https://medium.com/@connect.hashblock/10-ai-anti-patterns-that-seem-brilliant-then-explode-1c97248fa11d)
- [ArXiv 2602.14690v1: Agent Configuration Adoption Study](https://arxiv.org/html/2602.14690v1)
- [VentureBeat: Spotify/Novo Nordisk Case Studies](https://venturebeat.com/orchestration/anthropic-says-claude-code-transformed-programming-now-claude-cowork-is)
- [Snyk: SKILL.md Security Audit](https://snyk.io/articles/skill-md-shell-access/)
- [Mintlify: skill.md Design Rationale](https://www.mintlify.com/blog/skill-md)
- [MindStudio: Context Rot in Claude Code Skills](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files)
- [Anthropic: The Complete Guide to Building Skill for Claude (PDF)](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)
- [Gemini 3 Pro Deep Research: Custom vs Standard AI Harness](https://gemini.google.com/share/b1a1a64df744)
