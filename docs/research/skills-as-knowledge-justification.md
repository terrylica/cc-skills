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

### 论点 3: 什么知识值得编码为 Skills — 精确分类

不是所有知识都应该写成 SKILL.md。关键问题是: **哪些知识是 LLM 无论如何学不会的？**

> "Unlike conventional software errors, LLM failures in the tail are stochastic and context-dependent. A model may retrieve a rare fact correctly in one context but hallucinate in another following minor prompt perturbations."
>
> — [Sanket Badhe, Deep Shah, Nehal Kathrotia, arXiv](https://arxiv.org/), February 2026

> "Context Engineering has gone from a niche concern to the core discipline of AI Engineering in under a year... LLMs have a finite attention budget. Every token in the context window competes for attention. Context engineering means finding the smallest possible set of high-signal tokens that maximise the likelihood of desired outcomes."
>
> — [Towards AI, "State of Context Engineering in 2026"](https://towardsai.net/), March 2026

#### 应该编码为 Skills 的知识 (模型扩展无法解决)

| 知识类型                                          | 为什么 LLM 学不会                                           | Skills 中的体现                                         |
| ------------------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------- |
| **部署顺序依赖**                                  | 通过反复试错在 Claude Code 会话中发现的、未文档化的操作顺序 | SKILL.md 中精确的步骤序列 + "不要跳过步骤 X" 的负面约束 |
| **平台特异性** (macOS launchd, systemd MemoryMax) | 训练数据中出现频率极低，模型会用通用 Linux 知识填充         | 精确的环境模板和平台特定参数                            |
| **跨工具集成边界** (如 sherpa-onnx C API + Swift) | 两个冷门技术的交叉点，训练数据几乎为零                      | 经过验证的互操作代码和已知陷阱                          |
| **时间敏感知识** (API 弃用、版本特定 bug)         | 变化速度快于模型训练周期                                    | 版本化的 Skills，随 API 变化更新                        |
| **反模式 / "不要做什么"**                         | 训练数据偏向成功案例，模型缺乏失败经验                      | YAML frontmatter 中的负面触发器 ("Do NOT use for...")   |
| **认证编排** (内部零信任流程、MFA 序列)           | 组织私有，按定义不在训练数据中                              | 精确的 CLI 命令序列 + token 轮换脚本                    |

#### 不应该编码为 Skills 的知识 (反模式)

| 反模式                                             | 为什么不应该编码                                               |
| -------------------------------------------------- | -------------------------------------------------------------- |
| **标准编程模式** (React 组件, pandas 管道)         | 训练数据中极高密度，写 Skill 反而干扰模型的内置最优解          |
| **临时性 workaround** (因 DNS 临时宕机而硬编码 IP) | 短暂的本地异常，编码后变成危险的过时指令                       |
| **过多 "不要做X" 约束**                            | 负面约束过载导致 prompt 瘫痪，模型无法在剩余空间中生成可行方案 |
| **可由模型在新版本中自然改进的领域**               | 编码的假设会随模型升级而过时，成为技术债务                     |

#### 会话经验主义 (Conversational Empiricism) — Skills 知识的诞生过程

> "The simplest way to gain insights into how an agent is performing is to ask it directly during the session... Users can develop insights into 'undertriggering' or 'overtriggering' by running a checklist of natural language requests."
>
> — [A B Vijay Kumar, "Deep Dive SKILL.md (Part 1/2)"](https://abvijaykumar.medium.com/deep-dive-skill-md-part-1-2-09fc9a536996), Medium, March 16, 2026

Skills 中最有价值的知识不是从文档复制来的 — 而是从反复的 AI 编程会话中**经验性地发现**的:

| 阶段              | 工程师-Agent 交互                                           | 转化为 SKILL.md 的内容                            |
| ----------------- | ----------------------------------------------------------- | ------------------------------------------------- |
| **1. 探索性激发** | 布置新任务，预期初始失败，观察模型的默认假设和幻觉模式      | 定义核心问题 + 识别该 skill 需要防范的"幻觉区域"  |
| **2. 交互式校准** | 用外部文档、错误日志、环境约束纠正模型输出                  | 形成 SKILL.md 正文: 经过验证的精确步骤序列        |
| **3. 边界调优**   | 测试边缘情况，发现"触发不足"或"过度触发"                    | 调整 YAML frontmatter 的 description 和负面边界   |
| **4. 自动提取**   | Meta-agent (skill-creator) 观察成功的会话并自动提取通用逻辑 | 生成完整的 SKILL.md 目录 + scripts/ + references/ |

**关键洞察**: 如果一个工程师在 Claude Code 会话中花了 2 小时调试一个部署问题，最终发现了正确的操作序列 — 这个知识在会话结束后就**永久丢失**了。除非它被编码为 SKILL.md，否则下一个人会花同样的 2 小时重复发现同一个问题。

### 论点 4: Token 经济学 — 为什么 Skills 比无限 Context 更高效

> "Token economics favor skills. Anthropic's own engineering team discovered that one GitHub MCP server can expose ninety-plus tools, consuming over 50,000 tokens of JSON schemas before the model starts reasoning."
>
> — [Arcade Dev Blog, "What are Agent Skills and Tools?"](https://arcade.dev/), 2026

即使未来模型拥有 1000 万 token 的 context 窗口，Skills 仍然比"把所有知识塞进 context"更优:

- **一个 MCP server 就消耗 50,000 tokens** — 无限 context 不等于无限注意力
- **Progressive Disclosure 每个 skill 仅 ~100 tokens** — 只在需要时加载完整内容
- **注意力稀释是物理限制** — context 越长，中间信息被忽略的概率越高 ("Lost in the Middle")

### 论点 5: Skills 不是静态文档 — 它们可以自我进化

传统文档的致命弱点是**知识半衰期**:

> "The knowledge half-life in AI has shrunk to months from years. And it's why one chief information officer (CIO) told me, 'The time it takes us to study a new technology now exceeds that technology's relevance window.'"
>
> — [Deloitte, Tech Trends 2026](https://www.deloitte.com/us/en/insights/topics/technology-management/tech-trends.html), 2026

Wiki 页面、Confluence 文档、自定义 README — 写完那一刻就开始腐烂。但 SKILL.md 可以包含**自我进化协议**: 当执行失败时，skill 自动检测自身指令是否过时，并提出有针对性的修正。

#### 自我修正的触发机制

> "The Skill Evolver only acts when scores drop. It doesn't optimize what's already working — it fixes what's failing."
>
> — [Vadim, vadim.blog](https://vadim.blog/skill-evolver-research-to-practice), 2026

Skill 不会无故修改自己。它只在**执行失败且失败可归因于自身指令**时才触发修正。这通过 `## Self-Evolution` 区域中的条件-动作规则实现:

```markdown
## Self-Evolution

**触发条件:** 执行错误返回的 stack trace 指向本 SKILL.md 中标记为
[Evolvable] 的指令行。

**修正协议:**

1. 隔离: 判断失败是环境问题还是指令过时
2. 自我提问: 这个修改是否会导致其他维度的回退？
3. 靶向编辑: 只修改 [Evolvable] 标记的行，不重写整个文件
4. 验证: 用 eval.json 中的二元断言验证修改后的效果
```

#### Eval 驱动的验证循环

> "A useful binary assertion has three properties: Unambiguous — it can be evaluated by a script or a secondary LLM judge with a clear yes/no answer. Directly tied to the skill — it measures the actual capability, not a proxy. Failure-informative — when it fails, the failure tells you something useful about what went wrong."
>
> — [MindStudio Team](https://www.mindstudio.ai/blog/karpathy-autoresearch-applied-to-claude-code-skills), March 14, 2026

每个 skill 可以配备 `eval.json` 文件，定义二元 pass/fail 断言。修改后的 skill 必须通过所有断言才能被接受。失败则自动回滚。这是**机械性的**验证，不依赖模型的主观判断。

#### 为什么这比静态文档更优

| 维度         | 静态文档 (Wiki/README)                            | 自我进化的 SKILL.md                                           |
| ------------ | ------------------------------------------------- | ------------------------------------------------------------- |
| **知识保鲜** | 写完即腐烂，依赖人工定期审查                      | 执行失败自动触发更新                                          |
| **修正方式** | 有人发现问题 → 记得更新 → 找到正确页面 → 手动编辑 | Agent 检测失败 → 归因分析 → 靶向修改 → eval 验证 → git commit |
| **验证机制** | 无 — 文档可能已经过时但没人知道                   | 二元断言: pass 或 fail, 无灰色地带                            |
| **回滚能力** | 手动 git revert (如果有人记得)                    | 自动: 验证失败 → 立即回滚到上一版本                           |

**关键结论**: 自定义的 inbox/papers 管线如果写成静态脚本，API 变化时没人会发现直到有人用了它。SKILL.md 配合 eval.json 可以在下一次执行时**自动发现并修复**问题。这是自定义方案做不到的。

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

## 第四部分: <private-repo> 作为 Plugin Marketplace — 数据 + Skills 的混合架构

核心思路: 把 <private-repo> **升级**为 Claude Code Plugin Marketplace，让数据层和工作流层在同一个仓库中共存，同时允许从任何团队成员的上游 skills 仓库直接 cherry-pick 已有的 skills。

### 为什么要 Marketplace 而不只是加几个 SKILL.md 文件

> "Skills are built around progressive disclosure. Claude fetches information in three stages: Metadata (name + description): Always in Claude's context. About 100 tokens. Claude decides whether to load a Skill based on this alone. SKILL.md body: Loaded only when triggered. Bundled resources... Loaded on demand when needed. With this structure, you can install many Skills without blowing up the context window."
>
> — [Hajime Takeda, Towards Data Science](https://towardsdatascience.com/), March 16, 2026

> "Keep skill.md as a router, not a monolith. If your skill.md is approaching 500 lines, it's time to refactor. Move detailed instructions into reference files and have skill.md route to them... Just as VS Code has an Extensions Marketplace, we're heading toward a Skills Marketplace."
>
> — Atal Upadhyay, March 16, 2026

Plugin Marketplace 的核心优势: **每个 skill 只占用 ~100 tokens 的环境成本**，只在被触发时才加载完整指令。这意味着 <private-repo> 可以承载几十个 skills 而不浪费 Agent 的 context 窗口。

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
<private-repo>/
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
  "name": "<private-repo>",
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
        "url": "https://github.com/example-org/shared-skills.git",
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
claude plugin marketplace add example-org/<private-repo>
claude plugin install financial-analysis@<private-repo>
claude plugin install quant-research@<private-repo>
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

把 <private-repo> 升级为 Marketplace 意味着:

1. 团队成员一条命令安装所有金融分析 skills: `claude plugin install financial-analysis@<private-repo>`
2. 团队成员可以从各自的 skills 仓库中 cherry-pick 相关工具到 <private-repo>，不需要复制代码
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

1. **保留 <private-repo>**: 不需要改动 Maywei 的数据管线 — inbox/papers/checklists 继续工作
2. **添加 .claude/skills/**: 在 <private-repo> 仓库中加入 3-5 个核心操作 skills
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
- [Gemini 3 Pro Deep Research: Skill-Worthy Knowledge Taxonomy](https://gemini.google.com/share/274d0b18ba66)
- [ArXiv: Long-Tail Knowledge in LLMs — Taxonomy (Badhe et al., Feb 2026)](https://arxiv.org/)
- [Towards AI: State of Context Engineering in 2026](https://towardsai.net/)
- [A B Vijay Kumar: Deep Dive SKILL.md (Part 1/2)](https://abvijaykumar.medium.com/deep-dive-skill-md-part-1-2-09fc9a536996)
- [Arcade Dev Blog: What are Agent Skills and Tools?](https://arcade.dev/)
- [Gemini 3 Pro Deep Research: Self-Evolving Agent Skills](https://gemini.google.com/share/0f22b47e028d)
- [Vadim: Skill Evolver — Research to Practice](https://vadim.blog/skill-evolver-research-to-practice)
- [MindStudio: AutoResearch Applied to Claude Code Skills](https://www.mindstudio.ai/blog/karpathy-autoresearch-applied-to-claude-code-skills)
- [Deloitte: Tech Trends 2026 — Knowledge Half-Life](https://www.deloitte.com/us/en/insights/topics/technology-management/tech-trends.html)
