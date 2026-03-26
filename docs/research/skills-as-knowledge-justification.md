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

## 第三部分: 已知的反模式与批评 (Anti-Patterns & Criticisms)

### 批评 1: "缺乏严格的性能验证"

> "Where is the evidence that skills improve performance over any other methodology outside of the fact of its nascent popularity?"
>
> — SirensOfTitan, [Hacker News](https://news.ycombinator.com/item?id=47475832)

**回应**: 这个批评是合理的。但 Anthropic 的数据显示 onboarding 从数周缩短到数小时，Rakuten 在 1250 万行代码库上用 Claude Code 7 小时完成了 99.9% 准确度的任务。实践已经在验证这个方法。

### 批评 2: "简单的 Markdown + TODO 也能达到同样效果"

> "I have an architecture md... and todos for every single ticket the AI goes through and does it. I have like 90% plus success."
>
> — moomoo11, Hacker News

**回应**: 对于个人使用确实如此。但 Skills 的价值在于**可共享性**和**可组合性** — 你的个人 markdown 别人用不了，但 Skills 可以 `claude plugin marketplace add` 一键安装。

### 批评 3: "依赖管理和组合问题"

> "Skills that depend on other skills, or a skill that assumes specific instructions are already loaded, conflicting skills, versioning and supply chain issues — and suddenly you need dependency resolution."
>
> — dmppch, Hacker News

**回应**: 这是真实的技术挑战。但这恰恰说明 Skills 已经成熟到需要包管理器了 — Microsoft 已经在构建 [APM](https://github.com/microsoft/apm)。

### 批评 4: "过度工程化风险"

> "If you over-engineer the control flow, the next model update will break your system."
>
> — NxCode Harness Engineering Guide

**回应**: Skills 的设计原则就是"原子化 + 可替换"。每个 SKILL.md 是独立的，不需要复杂的控制流。模型升级时，Skills 本身就是 Markdown — 天然兼容。

---

## 第四部分: 关键统计数据 (Key Statistics)

| 指标                    | 数据                    | 来源                      |
| ----------------------- | ----------------------- | ------------------------- |
| Onboarding 加速         | 数周 → 数小时           | Anthropic 2026 Report     |
| Skills 市场规模         | 500,000+ skills         | SkillsMP.com              |
| 跨平台兼容              | 6+ 平台支持 SKILL.md    | Claude/Codex/Gemini/etc.  |
| 官方 Anthropic Skills   | 277,000+ installs (top) | Anthropic Skills Registry |
| Skills 三层架构正式论文 | arXiv:2603.05344        | Nghi D. Q. Bui, Mar 2026  |
| Microsoft APM 包管理器  | 已发布                  | github.com/microsoft/apm  |

---

## 第五部分: 行动建议 (Recommended Actions)

1. **立即开始**: 把现有的 runbook、部署指南、最佳实践编码为 SKILL.md
2. **共享仓库**: 在 `~/eon` 下建立团队 Skills 仓库，用 `claude plugin marketplace add` 分发
3. **渐进采用**: 从最常用的 3-5 个工作流开始，不需要一次性迁移所有知识
4. **度量效果**: 跟踪 onboarding 时间、重复问题数量、知识查找时间

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
