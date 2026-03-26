---
source_url: https://gemini.google.com/share/6242730defcb
source_type: gemini-3-pro
scraped_at: 2026-03-26T17:32:42Z
purpose: Deep research on structuring alpha-forge-brain as a Claude Code Plugin Marketplace — hybrid data+skills repo pattern, cherry-picking from cc-skills, marketplace.json architecture
tags:
  [
    marketplace,
    plugin-architecture,
    cherry-pick,
    hybrid-repo,
    skills-distribution,
    progressive-disclosure,
  ]
model_name: Gemini 3 Pro
model_version: Deep Research mode
tools: []
claude_code_uuid: fd3529fa-dc43-4d95-95d2-5764970c447b
claude_code_project_path: "~/.claude/projects/-Users-terryli-eon-cc-skills/fd3529fa-dc43-4d95-95d2-5764970c447b"
github_issue_url: https://github.com/terrylica/cc-skills/issues/68
---

[About Gemini Opens in a new window](https://gemini.google/about/?utm_source=gemini&utm_medium=web&utm_campaign=gemini_zero_state_link_to_marketing_microsite)
[Gemini App Opens in a new window](https://gemini.google.com/app/download)
[Subscriptions Opens in a new window](https://one.google.com/ai)
[For Business Opens in a new window](https://workspace.google.com/solutions/ai/?utm_source=geminiforbusiness&utm_medium=et&utm_campaign=gemini-page-crosslink&utm_term=-&utm_content=forbusiness-2025Q3)

# Structuring a Hybrid GitHub Repository as a Claude Code Plugin Marketplace: Architectural Analysis and Implementation Patterns

The evolution of agentic coding tools in the first quarter of 2026 has fundamentally shifted how software development and research teams manage, distribute, and execute context. The transition from monolithic, repository-bound instruction sets to modular, distributable plugins represents a maturation in Large Language Model (LLM) context management. This comprehensive research report provides an exhaustive architectural analysis of how to structure a GitHub repository as a Claude Code Plugin Marketplace. Specifically, this analysis addresses the hybrid repository pattern, wherein domain-specific data layers—such as curated financial research papers in an `alpha-forge-brain` repository—coexist seamlessly with executable workflow layers derived from an upstream repository like `cc-skills`.

By analyzing standardized frameworks, official schema specifications, and community implementations published between January and March 2026, this report demonstrates how an existing knowledge repository can be transformed into a federated skill marketplace. This transformation enables organizational teams to cherry-pick, distribute, and execute modular workflows across organizational boundaries without duplicating underlying codebase assets.

## Thread 1: Claude Code Plugin Marketplace Architecture

The architecture of a Claude Code Plugin Marketplace is fundamentally a Git-based distribution mechanism. It packages LLM context, deterministic scripts, and external integrations—such as Model Context Protocol (MCP) servers—into consumable artifacts. The marketplace design deliberately avoids complex backend infrastructure; instead, it relies entirely on repository filesystem structure and strict JSON schemas to define discoverability, dependencies, and installation paths.

### The Plugin Registry: `marketplace.json`

The `.claude-plugin/marketplace.json` file serves as the definitive registry and entry point for any repository acting as a marketplace. It operates purely as a catalog or index, informing the Claude Code Command Line Interface (CLI) where to locate specific plugin manifests within the host repository or across external URLs and Git submodules.  

Writing for Just Be Dev on January 19, 2026, Dean Blank provides the following verbatim observation regarding the foundational structure:

> "To build a Claude Code (CC) Plugin Marketplace, you must create a GitHub repository that organizes and exposes 'plugins'—consumable artifacts that wrap capabilities like custom slash commands, skills, hooks, subagents, and MCP servers. A marketplace repository is primarily composed of the following components: A `.claude-plugin/marketplace.json` file that contains the marketplace's basic metadata and a comprehensive list of the plugins it provides... \[and\] a collection of individual plugins stored at the paths specified."  

When a user executes the command `claude plugin marketplace add Eon-Labs/alpha-forge-brain`, the CLI initiates a specific execution lifecycle. It first resolves the GitHub repository, locates the `.claude-plugin/marketplace.json` file on the default branch, and parses the metadata. It then reads the `plugins` array to index all available capabilities. Finally, it caches these available endpoints locally in the user's `~/.claude/plugins/cache/` directory, allowing for rapid autocomplete and discovery via the `claude plugin search` command. The installation of a specific skill bundle via `claude plugin install <plugin-name>@<marketplace-name>` resolves the alias defined in the `name` field of the `marketplace.json` top-level object, completely abstracting the underlying repository path from the end user.  

### Canonical Directory Structure and Component Bundling

A production-ready marketplace repository adheres to a strict filesystem hierarchy. This hierarchy is not merely organizational; it is a technical requirement for the CLI's parsing engine to ensure progressive disclosure and valid manifest resolution. Official documentation from the Anthropic Knowledge Work Plugins repository in early 2026 details this structural mandate verbatim:  

> "Every plugin follows the same structure: `plugin-name/` containing `.claude-plugin/plugin.json` (Manifest), `.mcp.json` (Tool connections), `commands/` (Slash commands), and `skills/` (Domain knowledge)."  

Plugins are designed to bundle diverse capabilities into a single, cohesive installable unit. A well-architected plugin combines natural language instructions representing domain expertise (via `SKILL.md` files), deterministic lifecycle scripts known as hooks (such as `PreToolUse` events that validate data before the LLM processes it), and MCP server definitions (`.mcp.json`) that connect the agent to external databases or APIs.  

The following code block illustrates the canonical directory structure required to convert the `alpha-forge-brain` knowledge repository into a fully compliant Claude Code marketplace, housing both the `inbox/papers` data pipeline and the installable plugin artifacts.

alpha-forge-brain/ ├──.claude-plugin/ │ └── marketplace.json # Global catalog registry for the repository ├── plugins/ │ ├── financial-analysis/ # Plugin bundle encompassing analytical workflows │ │ ├──.claude-plugin/ │ │ │ └── plugin.json # Plugin-specific manifest (version, tags, dependencies) │ │ ├──.mcp.json # Tool integrations (e.g., PostgreSQL vector DB for papers) │ │ ├── hooks/ │ │ │ └── hooks.json # Deterministic event handlers for data validation │ │ └── skills/ │ │ ├── extract-wacc-inputs/ # Specific analytical skill directory │ │ │ ├── SKILL.md # Core YAML frontmatter and LLM instructions │ │ │ └── scripts/ │ │ │ └── parse.py # Sandboxed executable code for data extraction │ │ └── review-equities/ │ │ └── SKILL.md │ └── document-processing/ # Secondary plugin bundle for raw data ingestion │ ├──.claude-plugin/ │ │ └── plugin.json │ └── skills/ │ └── pdf-extraction/ │ └── SKILL.md └── inbox/ └── papers/ # Domain data layer (Hybrid structure) ├── Q1-2026-earnings.pdf └── tech-sector-analysis.md

### Architectural Deployment Patterns for Skills

Understanding the distinction between global, project-level, and plugin-based skills is critical for proper architectural design. The marketplace architecture specifically leverages the plugin pattern to ensure portability and managed versioning.

| Characteristic             | Global Skills (`~/.claude/skills/`)                                       | Project Skills (`.claude/skills/`)                                                     | Plugin Skills (Installed via Marketplace)                                                                                               |
| -------------------------- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Operational Scope**      | Available universally across all local projects for a specific developer. | Confined strictly to the specific repository where the `.claude` folder resides.       | Cached globally (`~/.claude/plugins/cache/`), explicitly invoked or auto-loaded based on task context across any authorized repository. |
| **Distribution Mechanism** | Manual copying or local filesystem symlinks.                              | Git cloned alongside the codebase, requiring developers to pull the entire repository. | Managed dynamically via `claude plugin install` with explicit semantic version tracking.                                                |
| **Update Lifecycle**       | Unmanaged and manual; highly susceptible to configuration drift.          | Standard Git pull operations tied to broader codebase changes.                         | Handled autonomously via `claude plugin update`, which checks the remote source `plugin.json` version field.                            |
| **Primary Use Case**       | Personal developer preferences (e.g., preferred terminal commands).       | Repository-specific workflows (e.g., specific build pipelines for a microservice).     | Standardized team workflows, shared organizational capabilities, and cross-repo toolchains (e.g., shared ML workflows).                 |

Export to Sheets

This structural design ensures that the `alpha-forge-brain` repository can serve both as a static data host and as a dynamic capability provider for remote agents operating in separate organizational contexts.

## Thread 2: Multi-Marketplace and Cross-Repo Skill Sharing Patterns

For organizations managing multiple repositories—such as maintaining a foundational `cc-skills` repository alongside a specialized `alpha-forge-brain` repository—cross-repository skill sharing requires robust federation and dependency management. The Claude Code marketplace architecture natively supports simultaneous installations from disparate sources, enabling complex capability matrices across organizational boundaries.

### Simultaneous Installations and Federation Gateways

The Claude Code environment is engineered to support the registration of multiple marketplaces simultaneously. By executing multiple `marketplace add` commands, an agent's context is augmented by federated sources without causing namespace collisions, provided the marketplace names are unique.  

For enterprise environments managing dozens of internal repositories, intermediate registries serve as organizational aggregators. The LiteLLM AI Gateway documentation from 2026 explicitly describes this federated management pattern verbatim:

> "Admins use the LiteLLM Admin UI or API to manage the collection of plugins available to the organization... To manage multiple marketplaces, you would repeat this command \[`claude plugin marketplace add <url>`\] for each unique registry URL provided by your organization or providers."  

When bridging the `cc-skills` repository with the `alpha-forge-brain` repository, team members can register both marketplaces within their local CLI environments. This prevents the need to duplicate core foundational skills into the data-heavy `alpha-forge-brain` repository. If a developer requires both general DevOps tools and specialized financial research capabilities, they simply federate their local agent.

Furthermore, advanced concurrent workflows leverage Git worktrees to allow multiple agent sessions to operate on the same repository simultaneously using different skill sets. A 2026 MindStudio blog post provides the following verbatim explanation of this pattern:

> "It \[claude-team orchestration\] lets you run parallel feature branches in separate working directories, each with its own Claude Code session, all pointing at the same repository... If you need to move code between branches, use git cherry-pick or a proper merge — don't try to copy-paste context between Claude sessions."  

### Cherry-Picking Capabilities via Git Subdirectories

To explicitly share or "fork" skills from one marketplace to another without duplicating filesystem artifacts, the `marketplace.json` schema supports remote dependency declarations. Instead of relying solely on local relative paths, a marketplace can source a plugin directly from an external Git repository. This effectively allows the `alpha-forge-brain` marketplace to "cherry-pick" a specific commit hash, branch, or subdirectory from the `cc-skills` repository.  

The following JSON configuration demonstrates how the `alpha-forge-brain` registry can seamlessly embed a machine learning workflow originally developed in the `cc-skills` repository.

JSON

    {
      "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
      "name": "alpha-forge-brain",
      "description": "Financial research data pipelines and analytical agent skills.",
      "plugins": [\
        {\
          "name": "ml-data-pipeline",\
          "description": "Cherry-picked ML workflow from the central cc-skills repository.",\
          "category": "machine-learning",\
          "source": {\
            "source": "git-subdir",\
            "url": "https://github.com/team-org/cc-skills.git",\
            "sha": "a1b2c3d4e5f6g7h8i9j0",\
            "path": "plugins/ml-workflows"\
          },\
          "tags": ["ml", "pipeline", "shared-capability"]\
        },\
        {\
          "name": "financial-analysis",\
          "description": "Native financial paper parsing tools.",\
          "category": "analysis",\
          "source": "./plugins/financial-analysis"\
        }\
      ]
    }

This configuration ensures that `alpha-forge-brain` acts as the single point of entry for the financial team. When a team member runs `claude plugin install ml-data-pipeline@alpha-forge-brain`, the CLI resolves the `git-subdir` object, reaches out to the `cc-skills` repository, and downloads only the specified `plugins/ml-workflows` directory at the exact Git SHA provided. This guarantees version stability while preventing code duplication.

### Dependency Management Analogies

Advanced skill federation borrows architectural patterns from Apollo GraphQL Federation, where explicit directives manage cross-domain data dependencies. Within Claude Code plugins, undeclared dependencies are widely recognized as a severe anti-pattern. While the `marketplace.json` structure in early 2026 lacks a fully automated dependency resolution tree akin to NPM, it relies heavily on explicit metadata to signal required environmental configurations. Plugin manifests must declare required MCP servers or external CLI tools, ensuring that an agent attempting to execute a financial modeling skill has the necessary database connections pre-configured.  

## Thread 3: Hybrid Repo Pattern — Data Repository Plus Skill Marketplace

The hybrid repository pattern solves a critical friction point in agentic workflows: the traditional separation of domain data from the agents trained to process that data. By structuring `alpha-forge-brain` as both a knowledge repository hosting the `inbox/papers` pipeline and a plugin marketplace, the data layer and the skills workflow layer are tightly coupled in version control. This ensures that any structural changes to the financial papers or database schemas are immediately reflected in the skills designed to parse them.

### Industry Adoption of Colocation

The colocation of knowledge and execution logic is highly advantageous despite minor token overhead. Niels Kristian Schjødt, writing in 2026, provides the following verbatim rationale for this architectural decision:

> "A hybrid repo will consume more tokens, but the \[benefit of colocation is significant\]... I'd expect the teams building Cursor, Claude Code \[to increasingly adopt this\]."  

In a hybrid setup, the repository serves two distinct audiences simultaneously. First, it serves internal contributors, such as data scientists and analysts directly pushing PDF papers and markdown analyses to the repository. Second, it serves external consumers—agents operating in entirely different repositories that need to query the financial papers or utilize the analytical methodologies developed by the `alpha-forge-brain` team.

### The Dichotomy of `CLAUDE.md` and `marketplace.json`

To support this dual mandate, the hybrid repository utilizes a strict separation of concerns between two configuration files: `CLAUDE.md` and `marketplace.json`. Dean Blank, writing for GitConnected on March 4, 2026, provides a verbatim mental model for this separation:

> "CLAUDE.md and Skills (Knowledge): Use these when you're tired of repeating yourself. CLAUDE.md is for rules that should always be active. It loads at the start of every session and stays in context the entire time. Skills are for instructions Claude should only reach for when the situation calls for it."  

When placed at the root of a hybrid repository, `CLAUDE.md` acts as the "always-on" systemic context governing how the host repository itself is maintained. It instructs the local agent on formatting rules for new financial papers entering the pipeline, naming conventions for directories, and Git commit standards.  

Conversely, the `.claude-plugin/marketplace.json` file completely ignores local repository operations. Its sole purpose is to package the `plugins/` directory into consumable bundles for export to remote environments.  

The operational vectors of these two files contrast sharply:

| Operational Vector            | `CLAUDE.md` (Always-On Context)                                                                      | `marketplace.json` (Exported Capabilities)                                                                             |
| ----------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| **Primary Audience**          | Agents actively operating within and modifying the host repository.                                  | Remote agents in separate repositories installing new capabilities.                                                    |
| **Context Loading Mechanism** | Always-on; parsed and loaded into the system prompt at the start of every session.                   | Progressive disclosure; metadata loaded initially, full bodies loaded only when explicitly triggered by a user prompt. |
| **Token Cost Profile**        | High continuous cost (e.g., 500-1000 tokens persistently occupying the context window).              | Near-zero ambient cost (~100 tokens for metadata); dynamic cost incurred only upon active execution.                   |
| **Data Interaction Paradigm** | Internal governance: "Format all new PDF papers in this specific directory according to standard X." | External utility: "Install this skill in your remote project to query and analyze papers located at URL Y."            |

Export to Sheets

By utilizing this hybrid structure, the `alpha-forge-brain` repository can contain a `CLAUDE.md` that strictly enforces schema validation on uploaded financial papers, while simultaneously offering a marketplace of skills (such as `review-equities` or `extract-wacc-inputs`) that other teams across the organization can install to process that very data.

## Thread 4: `marketplace.json` Specification and Validation Pipelines

The stability of a Claude Code Plugin Marketplace relies heavily on strict adherence to the Anthropic JSON schema and robust Continuous Integration/Continuous Deployment (CI/CD) validation pipelines. Malformed manifests result in immediate resolution failures during the installation phase, breaking downstream agent workflows.

### Schema Specification and Required Metadata Fields

The official schema endpoint, validating the structure of the registry, is defined at `https://anthropic.com/claude-code/marketplace.schema.json`. A compliant `marketplace.json` requires specific hierarchical metadata to ensure discoverability and functional mapping. The following JSON code block illustrates a fully compliant registry for the `alpha-forge-brain` repository.  

JSON

    {
      "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
      "name": "alpha-forge-brain-market",
      "description": "Eon-Labs financial research data pipelines and analytical agent skills.",
      "owner": {
        "name": "Eon-Labs Engineering",
        "email": "engineering@eon-labs.com"
      },
      "plugins":
        },
        {
          "name": "clangd-lsp",
          "description": "Provides C++ code intelligence for proprietary algorithmic trading models.",
          "category": "development",
          "source": "./plugins/cpp-intelligence",
          "strict": false,
          "lspServers": {
            "clangd": {
              "command": "clangd",
              "extensionToLanguage": {
                ".cpp": "cpp",
                ".hpp": "cpp"
              }
            }
          }
        }
      ]
    }

Key fields dictate the discoverability and operational parameters of the plugin ecosystem:

- **`name`**: This string serves as the strict identifier for the marketplace or plugin. It is heavily validated; an issue reported in the Anthropic GitHub repository in 2026 notes verbatim: "The marketplace name validation checks all JSON fields for reserved words ('anthropic', 'claude', 'official') instead of just the name field. This causes a false positive when using the official `$schema` URL". Avoidance of these reserved keywords is mandatory.  

- **`category`** and **`tags`**: These arrays are critical for the searchability of the plugin. When developers execute `claude plugin search @alpha-forge-brain-market`, the CLI indexes these fields to surface relevant capabilities.  

- **`version`**: Semantic versioning strings (e.g., "1.2.0") are mandatory in the target `plugin.json`. The CLI cache utilizes this string to detect drift and execute updates. The local infrastructure tracks updates via `~/.claude/plugins/cache/` by checking this specific string against the remote source.  

- **`lspServers`**: Advanced plugins, particularly those dealing with complex parsing or quantitative modeling, can bundle Language Server Protocol configurations directly within the manifest, mapping file extensions to execution binaries.  

### Validation Scripts and CI/CD Automation

In a production environment, manual validation of `marketplace.json` is highly prone to human error. Engineering teams utilize the native `claude plugin validate <path>` command integrated into task runners (like `Taskfile.yml`) or GitHub Actions to enforce structural integrity prior to merging pull requests.  

Writing for the Just Be Dev blog in 2026, Dean Blank provides a verbatim explanation of this automated validation process:

> "The `validate-manifests` script runs the `claude plugin validate` script I mentioned previously on the `marketplace.json` file and all the `plugin.json` files... A plugin's version field is required and is what CC uses to determine if a plugin needs updates."  

Advanced community implementations deploy a suite of TypeScript validation scripts during the CI/CD pipeline to ensure robustness :  

1. **`validate-manifests.ts`**: Verifies schema compliance of the marketplace and plugin files against the official Anthropic schema endpoint.

2. **`verify-version-updates.ts`**: Compares Git diffs in the `skills/` directory against the `version` field in `plugin.json` to ensure code modifications trigger a required version bump.

3. **`bump-plugin-version.ts`**: Automatically increments the semantic versioning prior to the merge, ensuring remote agents accurately pull the latest changes.  

Implementing these validation patterns in the `alpha-forge-brain` repository ensures that modifications to the financial paper parsing logic do not silently break downstream agents utilizing the marketplace.

## Thread 5: Real-World Marketplace Implementations Beyond Anthropic

An analysis of community-driven marketplaces emerging between January and March 2026 reveals critical architectural patterns for managing scale, security, and developer experience. Studying repositories such as `daymade/claude-code-skills`, `sgaunet/claude-plugins`, and `affaan-m/everything-claude-code` highlights the operational realities of maintaining highly dense skill ecosystems ranging from 50 to nearly 200 components.  

### Meta-Tooling and Scaffolding for Scale

When a marketplace scales beyond 50 skills, maintaining flat directory structures and manual manifests becomes an unsustainable administrative burden. Real-world implementations utilize deep categorization and meta-tooling to sustain growth.

The `daymade/claude-code-skills` repository, which houses 43 production-ready skills, resolves scaling friction by shipping a meta-tool. An architectural review of this repository in 2026 notes the following verbatim:

> "The daymade/claude-code-skills marketplace repository is organized as a professional collection of 43 production-ready skills... It includes `skill-creator`, a meta-skill that enables users to build, validate, and package their own custom Claude Code skills."  

The `skill-creator` plugin uses Claude's own agentic capabilities to scaffold new `SKILL.md` files, automatically generate valid YAML frontmatter, and execute validation scripts. By turning the agent into a self-documenting maintenance tool, maintainers drastically reduce the overhead of expanding the marketplace. For the `alpha-forge-brain` repository, importing or replicating this meta-skill is highly recommended to accelerate the migration of the 190+ skills currently residing in `cc-skills`.  

### Deterministic Security Hooks: A Required Paradigm

A significant anti-pattern observed in early agent development was the reliance on natural language instructions within `SKILL.md` to enforce security boundaries (e.g., instructing the agent to "never read the.env file"). The `sgaunet/claude-plugins` marketplace demonstrates the modern correction to this vulnerability. An analysis of the repository details this verbatim:

> "The repository uses a structured approach to validate plugin integrity and metadata... `configure-no-leak.sh` installs a `PreToolUse` hook that serves as a deterministic security barrier. It prevents Claude Code from reading or modifying sensitive files such as `.env` files, credentials... ensuring they cannot be bypassed by the LLM."  

This implementation operates entirely outside the LLM's context window. By intercepting system calls before execution, the deterministic script physically blocks unauthorized access. For the `alpha-forge-brain` repository, embedding similar `PreToolUse` hooks is a mandatory production pattern to restrict remote agents from accidentally exposing sensitive financial data or proprietary trading algorithms.

### Manifest-Driven Selective Architecture

The `affaan-m/everything-claude-code` repository represents the upper limits of scale, housing over 190 components including agents, skills, and rules. To prevent catastrophic context bloat during installation, the repository utilizes a v1.9.0 release architecture (launched in March 2026) that implements a manifest-driven selective installation pipeline.  

Rather than forcing users to clone the entire monolith, the `marketplace.json` acts purely as an index for highly granular, decoupled subagents. Users utilize a state store (`manifests/install-plan.js`) to cherry-pick exact capabilities—such as pulling only the `code-reviewer` agent or the `typescript-patterns` skill—leaving the remaining 180 components untouched.  

### Comparative Analysis of Community Architectures

| Repository Implementation             | Scale           | Core Architectural Differentiator                                                               | Identified Anti-Pattern Avoided                                         |
| ------------------------------------- | --------------- | ----------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| **`daymade/claude-code-skills`**      | 43+ Skills      | Employs meta-tooling (`skill-creator`) and automated cross-platform installation scripts.       | Avoids manual manifest generation overhead and syntax errors.           |
| **`sgaunet/claude-plugins`**          | Mid-scale       | Enforces strict CI validation via `Taskfile.yml` and deterministic `PreToolUse` security hooks. | Eliminates reliance on probabilistic natural language security prompts. |
| **`affaan-m/everything-claude-code`** | 190+ Components | Utilizes manifest-driven selective installation pipelines via state stores.                     | Prevents monolithic context bloat during the installation phase.        |

Export to Sheets

## Thread 6: The Economics of Skill Portability — Marketplace vs. Monolith

The fundamental argument for migrating `alpha-forge-brain` from a monolithic structure to a plugin marketplace lies in the computational economics of LLM context management. The transition to distributed plugins is driven by a mechanism known as "progressive disclosure," which actively protects the agent's context window, reduces latency, and minimizes inference costs.  

### The Token Economics of Progressive Disclosure

A monolithic `CLAUDE.md` file loaded at the root of a repository injects its entire textual content into the system prompt at the initiation of every single session. If the file contains 5,000 tokens of instruction regarding financial document parsing, API endpoints, WACC calculations, and data validation rules, those 5,000 tokens are processed continuously. This results in massive computational overhead and severe context degradation, confusing the agent during complex reasoning tasks.  

Hajime Takeda, writing for Towards Data Science on March 16, 2026, explains the alternative mechanism verbatim:

> "Skills are built around progressive disclosure. Claude fetches information in three stages: Metadata (name + description): Always in Claude's context. About 100 tokens. Claude decides whether to load a Skill based on this alone. SKILL.md body: Loaded only when triggered. Bundled resources... Loaded on demand when needed. With this structure, you can install many Skills without blowing up the context window."  

The plugin marketplace utilizes this precise three-stage progressive disclosure architecture:

1. **Level 1 (Ambient Metadata Visibility):** When a plugin is installed from the marketplace, only the YAML frontmatter of the `SKILL.md`—comprising the `name` and a highly optimized `description`—enters the ambient context. This costs approximately 100 tokens, rendering the baseline footprint almost negligible.  

2. **Level 2 (Triggered Context Activation):** The agent continuously evaluates incoming user prompts against the ambient 100-token descriptions. If a semantic match occurs (e.g., the user explicitly requests a "WACC analysis on Q1 earnings"), the system dynamically fetches the full Markdown body of the specific `SKILL.md` into the active context window.  

3. **Level 3 (On-Demand Resource Loading):** If the skill requires heavy datasets or complex executable scripts, those artifacts are housed in the `assets/` or `scripts/` subdirectories. They are loaded via native file-read tools precisely when the step-by-step logic dictates it, completely protecting the context window from raw code bloat.  

Atal Upadhyay, writing on March 16, 2026, emphasizes the necessity of this routing pattern verbatim:

> "Keep skill.md as a router, not a monolith. If your skill.md is approaching 500 lines, it's time to refactor. Move detailed instructions into reference files and have skill.md route to them... Just as VS Code has an Extensions Marketplace, we're heading toward a Skills Marketplace."  

### Structural Comparison: Monolith vs. Marketplace

| Evaluation Vector          | Monolithic Architecture (`CLAUDE.md` routing)                                               | Marketplace Architecture (Installable Plugins)                                               |
| -------------------------- | ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| **Initial Context Load**   | Exceedingly heavy upfront load; all instructions occupy context simultaneously.             | Ultra-light upfront load; approximately 100 tokens per skill metadata footprint.             |
| **System Scalability**     | Hard operational ceiling; typically breaks down past 500 lines due to logic conflicts.      | Theoretically infinite; capabilities remain completely dormant until semantically triggered. |
| **Capability Portability** | Locked entirely to the host repository filesystem.                                          | Instantly installable across organizational boundaries via remote aliases.                   |
| **Maintenance Profile**    | High risk of unintended regression; modifying one rule may break unrelated agent behaviors. | Isolated testing and discrete semantic versioning per specific workflow.                     |

Export to Sheets

By structuring `alpha-forge-brain` as a marketplace, the complex financial logic and the 190+ workflows ported from `cc-skills` can be heavily isolated. Rather than forcing agents to parse a massive monolithic directive covering both ML pipelines and financial data formatting, they are provided an elegant router. The YAML frontmatter acts as a precise API endpoint for the agent's internal reasoning engine, allowing it to navigate deep organizational knowledge with maximum token efficiency.

## Architectural Synthesis

The imperative to structure the `alpha-forge-brain` repository as a Claude Code Plugin Marketplace is heavily supported by the technical evolution of agentic ecosystems in early 2026. The convergence of native data repositories and distributed skill marketplaces represents a mature, highly scalable approach to LLM context orchestration.

To effectively merge the expansive `cc-skills` capabilities with the `alpha-forge-brain` knowledge repository, organizations must abandon monolithic context ingestion. Instead, they must implement a hybrid pattern where domain data pipelines remain unencumbered, while a strict `.claude-plugin/marketplace.json` index exports targeted analytical capabilities. By utilizing remote dependency resolution via `git-subdir` source objects, enforcing progressive disclosure through lean YAML frontmatter, and integrating deterministic CI/CD validation scripts, engineering teams can dissolve traditional repository boundaries. This federated marketplace architecture ensures that disparate teams can seamlessly discover, install, and execute complex workflows directly atop curated financial data without sacrificing security or token efficiency.

Learn more
