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

### 2. Nghi D. Q. Bui — OpenDev 作者 (arXiv 论文)

**关于 Skills 系统的三层架构:**

> "Three-tier hierarchy for reusable domain-specific prompt templates: Built-in (framework-provided), Project-local (.opendev/skills/), User-global (~/.opendev/skills/)."
>
> — [Nghi D. Q. Bui, arXiv:2603.05344](https://arxiv.org/html/2603.05344v1), March 2026

**解读**: 学术界已经在论文中正式化了 Skills 的三层架构 (框架内置 → 项目级 → 用户级)。这与 Claude Code 的 skills 目录结构完全一致。这不是个人偏好 — 这是正在被学术界验证的架构模式。

---

### 3. Bozhidar Batsov — 知名开源作者 (RuboCop 创始人)

**关于 Skills 的力量:**

> "The real power is in creating your own. Skills live in one of three locations — personal, project, and plugin scopes — enabling team and organizational knowledge distribution."
>
> — [Bozhidar Batsov, "Essential Claude Code Skills and Commands"](https://batsov.com/articles/2026/03/11/essential-claude-code-skills-and-commands/), March 2026

**关于 Skills vs Slash Commands 的区别:**

> "Skills are prompt-based capabilities. When you invoke a skill, it loads a set of instructions (a markdown file) into Claude's context, and Claude executes them."
>
> — Bozhidar Batsov

### 4. 知识可发现性机制 — 为什么格式决定一切

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

### 5. 实证数据 — 标准化 Agent Skills 的采用率

**ArXiv 实证: ~3,000 仓库中自定义格式几乎不存在**

> "CLAUDE.md emerges as the dominant file type with 1,661 (34.2%), followed closely by AGENTS.md with 1,572 (32.3%). GEMINI.md (159 files, 3.3%) and .cursorrules (73 files, 1.5%) are rare."
>
> — [ArXiv 2602.14690v1](https://arxiv.org/html/2602.14690v1), February 2026 (分析 ~3,000 GitHub 仓库)

**Unicodeveloper: 没有 Skills 的 Agent 就像第一天上班的高级工程师**

> "A raw Claude, Amp, Cline, Cursor, OpenCode or Copilot without skills is like a senior engineer on day one: brilliant, but missing all the project-specific context that makes them dangerous."
>
> — [Unicodeveloper, Medium](https://medium.com/@unicodeveloper/10-must-have-skills-for-claude-and-any-coding-agent-in-2026-b5451b013051), March 9, 2026

**Verdent.ai: Skills 已实现真正的跨平台**

> "The Agent Skills open standard at agentskills.io was originated by Anthropic and published as an open specification in December 2025. Skills written for Claude Code can now work with OpenAI's Codex, Cursor, or any other platform that adopts the standard. This means Skills are now genuinely cross-platform."
>
> — [Verdent.ai](https://www.verdent.ai/guides/ai-coding-tools-predictions-2026), 2026

**解读**: ~3,000 个仓库的实证数据说明一切 — CLAUDE.md 34.2%, AGENTS.md 32.3%, 自定义格式统计学上几乎为零。不是某家公司的选择，而是整个行业用脚投票的结果。

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

**为什么这不影响我们**: 我们不从公共市场下载不明来源的 skills。团队的 skills 全部在内部仓库中自己编写和审核，走的是 private marketplace 路径。Snyk 的警告适用于盲目安装第三方 skills 的场景 — 我们的场景是团队内部共享，等同于共享内部代码库，安全边界完全不同。

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

## 第四部分: alpha-forge-brain 作为 Plugin Marketplace — 数据 + Skills 的混合架构

核心思路: 把 alpha-forge-brain **升级**为 Claude Code Plugin Marketplace，让数据层和工作流层在同一个仓库中共存，同时允许从任何团队成员的上游 skills 仓库直接 cherry-pick 已有的 skills。

### 为什么要 Marketplace 而不只是加几个 SKILL.md 文件

> "Skills are built around progressive disclosure. Claude fetches information in three stages: Metadata (name + description): Always in Claude's context. About 100 tokens. Claude decides whether to load a Skill based on this alone. SKILL.md body: Loaded only when triggered. Bundled resources... Loaded on demand when needed. With this structure, you can install many Skills without blowing up the context window."
>
> — [Hajime Takeda, Towards Data Science](https://towardsdatascience.com/), March 16, 2026

> "Keep skill.md as a router, not a monolith. If your skill.md is approaching 500 lines, it's time to refactor. Move detailed instructions into reference files and have skill.md route to them... Just as VS Code has an Extensions Marketplace, we're heading toward a Skills Marketplace."
>
> — Atal Upadhyay, March 16, 2026

Plugin Marketplace 的核心优势: **每个 skill 只占用 ~100 tokens 的环境成本**，只在被触发时才加载完整指令。这意味着 alpha-forge-brain 可以承载几十个 skills 而不浪费 Agent 的 context 窗口。

### CLAUDE.md vs marketplace.json — 各司其职

> "CLAUDE.md and Skills (Knowledge): Use these when you're tired of repeating yourself. CLAUDE.md is for rules that should always be active. It loads at the start of every session and stays in context the entire time. Skills are for instructions Claude should only reach for when the situation calls for it."
>
> — [Dean Blank, GitConnected](https://gitconnected.com/), March 4, 2026

| 维度           | `CLAUDE.md` (始终加载)                      | `marketplace.json` (导出能力)                            |
| -------------- | ------------------------------------------- | -------------------------------------------------------- |
| **主要受众**   | 在仓库内操作的 Agent                        | 在其他仓库中安装能力的远程 Agent                         |
| **加载机制**   | 始终加载到 system prompt (~500-1000 tokens) | Progressive disclosure: 元数据 ~100 tokens, 正文按需加载 |
| **Token 成本** | 持续占用                                    | 接近零环境成本，仅在执行时产生动态成本                   |
| **数据交互**   | 内部治理: "按标准 X 格式化新论文"           | 外部能力: "安装此 skill 来分析位于 URL Y 的论文"         |

### 完整架构: 数据层 + Marketplace 层

```
alpha-forge-brain/
├── .claude-plugin/
│   └── marketplace.json              ← 插件注册表 (SSoT)
│
├── plugins/                          ← 可安装的 Plugin 包
│   ├── financial-analysis/           ← 金融分析 plugin
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json           ← 版本、标签、依赖
│   │   ├── hooks/
│   │   │   └── hooks.json            ← PreToolUse 安全钩子
│   │   └── skills/
│   │       ├── search-papers/
│   │       │   └── SKILL.md          ← "搜索和总结 papers/ 中的论文"
│   │       ├── review-inbox/
│   │       │   └── SKILL.md          ← "审核论文，判断是否移入 papers/"
│   │       └── generate-checklist/
│   │           └── SKILL.md          ← "从论文生成投资决策清单"
│   │
│   └── quant-research/               ← 从上游 skills 仓库 cherry-pick 的 plugin
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/
│           ├── sharpe-ratio/
│           │   └── SKILL.md          ← cherry-picked from upstream
│           └── exchange-sessions/
│               └── SKILL.md          ← cherry-picked from upstream
│
├── inbox/                            ← Maywei 的数据层 (完整保留)
│   └── 2026-03-19/
│       ├── lstm-funding-rate.md       ← status: pending_review
│       └── mev-liquidation.md         ← status: pending_review
├── papers/                           ← 已审核论文 (完整保留)
│   └── 2026-03-15/
│       └── deflated-sharpe.md         ← status: reviewed
├── checklists/                       ← 可执行清单 (完整保留)
│
├── CLAUDE.md                         ← 本地治理: "默认只搜索 papers/"
└── index.json                        ← 内容索引 (已审核论文)
```

### Cherry-Pick: 从上游仓库直接引入已有 Skills

> "A marketplace can source a plugin directly from an external Git repository... effectively allowing a marketplace to 'cherry-pick' a specific commit hash, branch, or subdirectory from an upstream repository."
>
> — [Gemini 3 Pro Deep Research](https://gemini.google.com/share/6242730defcb), March 2026

`marketplace.json` 支持 `git-subdir` 远程依赖，不需要复制代码:

```json
{
  "name": "alpha-forge-brain",
  "description": "金融研究数据管线 + 分析型 Agent Skills",
  "plugins": [
    {
      "name": "financial-analysis",
      "description": "论文搜索、审核、清单生成",
      "source": "./plugins/financial-analysis"
    },
    {
      "name": "quant-research",
      "description": "从上游仓库 cherry-pick 的量化研究工具",
      "source": {
        "source": "git-subdir",
        "url": "https://github.com/Eon-Labs/shared-skills.git",
        "sha": "a1b2c3d4",
        "path": "plugins/quant-research"
      },
      "tags": ["sharpe-ratio", "exchange-sessions", "cherry-picked"]
    }
  ]
}
```

团队成员只需要一条命令:

```bash
claude plugin marketplace add Eon-Labs/alpha-forge-brain
claude plugin install financial-analysis@alpha-forge-brain
claude plugin install quant-research@alpha-forge-brain
```

### Skills 分发方式对比

> "Every plugin follows the same structure: `plugin-name/` containing `.claude-plugin/plugin.json` (Manifest), `.mcp.json` (Tool connections), `commands/` (Slash commands), and `skills/` (Domain knowledge)."
>
> — Anthropic Knowledge Work Plugins, 2026

| 维度         | 全局 Skills (`~/.claude/skills/`) | 项目 Skills (`.claude/skills/`) | Marketplace Plugins                |
| ------------ | --------------------------------- | ------------------------------- | ---------------------------------- |
| **作用范围** | 单人全局可用                      | 仅限本仓库                      | 全局缓存，跨仓库按需加载           |
| **分发方式** | 手动复制                          | git clone 整个仓库              | `claude plugin install` 版本化管理 |
| **更新机制** | 手动，易漂移                      | 跟随 git pull                   | `claude plugin update` 自动检测    |
| **主要场景** | 个人偏好                          | 单仓库工作流                    | **团队共享、跨仓库工具链**         |

### 为什么 Marketplace 比单体 CLAUDE.md 更优

| 维度         | 单体架构 (一个大 CLAUDE.md)     | Marketplace 架构 (可安装 Plugins)       |
| ------------ | ------------------------------- | --------------------------------------- |
| **初始加载** | 极重 — 所有指令同时占用 context | 极轻 — 每个 skill 仅 ~100 tokens 元数据 |
| **可扩展性** | ~500 行后逻辑冲突崩溃           | 理论上无限 — 能力在被触发前完全休眠     |
| **可移植性** | 锁定在本仓库                    | 跨组织边界一键安装                      |
| **维护风险** | 改一条规则可能破坏无关行为      | 独立测试 + 每个工作流单独语义版本       |

### 三层架构的分工

| 层级       | 负责人                      | 工具                        | 职责                                            |
| ---------- | --------------------------- | --------------------------- | ----------------------------------------------- |
| **数据层** | Maywei 的 inbox/papers 管线 | Git + 自定义脚本            | 存储和管理研究论文                              |
| **能力层** | Plugin Marketplace          | marketplace.json + SKILL.md | 可安装、可版本化、可 cherry-pick 的标准化工作流 |
| **导航层** | CLAUDE.md                   | Markdown                    | 本地治理: 告诉 Agent 先搜索什么、忽略什么       |

**数据层解决「有什么」，能力层解决「怎么用」，导航层解决「从哪开始」。**

把 alpha-forge-brain 升级为 Marketplace 意味着:

1. 团队成员一条命令安装所有金融分析 skills: `claude plugin install financial-analysis@alpha-forge-brain`
2. 团队成员可以从各自的 skills 仓库中 cherry-pick 相关工具到 alpha-forge-brain，不需要复制代码
3. 每个 plugin 有独立的 `plugin.json` 版本号，`claude plugin update` 自动检测更新
4. `PreToolUse` 安全钩子确保 Agent 不会意外暴露敏感金融数据
5. 同一套 marketplace 在 Claude Code, Cursor, Gemini CLI 都能工作

---

## 第五部分: 关键统计数据 (Key Statistics)

| 指标                  | 数据                             | 来源                                       |
| --------------------- | -------------------------------- | ------------------------------------------ |
| 标准格式采用率        | CLAUDE.md 34.2%, AGENTS.md 32.3% | ArXiv 2602.14690v1 (~3,000 repos)          |
| Skills 市场规模       | 500,000+ skills                  | SkillsMP.com                               |
| 跨平台兼容            | 6+ 平台支持 SKILL.md             | Claude/Codex/Gemini/Cursor/JetBrains/Xcode |
| 官方 Anthropic Skills | 277,000+ installs (top skill)    | Anthropic Skills Registry                  |
| Skills 三层架构论文   | arXiv:2603.05344                 | Nghi D. Q. Bui, Mar 2026                   |
| Skills 包管理器       | Microsoft APM 已发布             | github.com/microsoft/apm                   |
| Snyk Skills 安全审计  | 36% 社区 skills 含注入风险       | Snyk, Feb 2026                             |

---

## 第六部分: 行动建议 (Recommended Actions)

1. **保留 alpha-forge-brain**: 不需要改动 Maywei 的数据管线 — inbox/papers/checklists 继续工作
2. **添加 .claude/skills/**: 在 alpha-forge-brain 仓库中加入 3-5 个核心操作 skills
3. **从一个 skill 开始**: 先写一个 `search-papers/SKILL.md`，让团队体验效果
4. **度量效果**: 跟踪新成员上手时间、重复问题数量、论文查找效率
5. **渐进扩展**: 验证效果后，逐步将更多操作流程编码为 skills

---

## 参考链接 (Sources)

- [Andrej Karpathy: The AI Workflow Shift Explained 2026](https://www.the-ai-corner.com/p/andrej-karpathy-ai-workflow-shift-agentic-era-2026)
- [arXiv:2603.05344 — Building AI Coding Agents: Skills Three-Tier Hierarchy](https://arxiv.org/html/2603.05344v1)
- [ArXiv 2602.14690v1: Agent Config Adoption (~3,000 repos)](https://arxiv.org/html/2602.14690v1)
- [Bozhidar Batsov: Essential Claude Code Skills and Commands](https://batsov.com/articles/2026/03/11/essential-claude-code-skills-and-commands/)
- [Mintlify: skill.md Design Rationale](https://www.mintlify.com/blog/skill-md)
- [MindStudio: Context Rot in Claude Code Skills](https://www.mindstudio.ai/blog/context-rot-claude-code-skills-bloated-files)
- [Anthropic: The Complete Guide to Building Skill for Claude (PDF)](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)
- [Unicodeveloper: 10 Must-Have Skills for Claude](https://medium.com/@unicodeveloper/10-must-have-skills-for-claude-and-any-coding-agent-in-2026-b5451b013051)
- [Verdent.ai: AI Coding Tools Predictions 2026](https://www.verdent.ai/guides/ai-coding-tools-predictions-2026)
- [Snyk: SKILL.md Security Audit](https://snyk.io/articles/skill-md-shell-access/)
- [Addy Osmani: Stop Using Init for AGENTS.md (ETH Zurich study)](https://medium.com/@addyosmani/stop-using-init-for-agents-md-3086a333f380)
- [Hacker News: Skills are quietly becoming the unit of agent knowledge](https://news.ycombinator.com/item?id=47475832)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)
- [Anthropic Official Skills Repository](https://github.com/anthropics/skills)
- [SkillsMP: Agent Skills Marketplace (500K+ skills)](https://skillsmp.com/)
- [Microsoft APM: Agent Package Manager](https://github.com/microsoft/apm)
- [Gemini 3 Pro Deep Research: Custom vs Standard AI Harness](https://gemini.google.com/share/b1a1a64df744)
- [Gemini 3 Pro Deep Research: Marketplace Skills Architecture](https://gemini.google.com/share/6242730defcb)
- [Dean Blank: Building Claude Code Plugins (GitConnected)](https://gitconnected.com/)
- [Hajime Takeda: Skills Progressive Disclosure (Towards Data Science)](https://towardsdatascience.com/)
- [Anthropic: Create and distribute a plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces)
