# Preset Command Details

## 1. /research-business

**Purpose**: Comprehensive business and market research

**Arguments**: `$ARGUMENTS` (company or market to research)

**YAML**:

```yaml
---
description: Comprehensive business and market research with competitor analysis
argument-hint: [company/market] [industry]
allowed-tools: Read, Bash, Grep
---
```

**What it does**:

- Market size and trends analysis
- Competitor SWOT analysis
- Opportunity identification
- Industry landscape overview
- Strategic recommendations

---

## 2. /research-content

**Purpose**: Multi-platform content trend analysis

**Arguments**: `$ARGUMENTS` (topic to research)

**YAML**:

```yaml
---
description: Multi-platform content trend analysis for data-driven content strategy
argument-hint: [topic] [platforms]
allowed-tools: Read, Bash
---
```

**What it does**:

- Analyze trends across Google, Reddit, YouTube, Medium, LinkedIn, X
- User intent analysis (informational, commercial, transactional)
- Content gap identification
- SEO-optimized outline generation
- Platform-specific publishing strategies

---

## 3. /medical-translate

**Purpose**: Translate medical terminology to patient-friendly language

**Arguments**: `$ARGUMENTS` (medical term and language)

**YAML**:

```yaml
---
description: Translate medical terminology to 8th-10th grade reading level (German/English)
argument-hint: [medical-term] [de|en]
allowed-tools: Read
---
```

**What it does**:

- Translate complex medical terms
- Simplify to 8th-10th grade reading level
- Validate with Flesch-Kincaid (EN) or Wiener Sachtextformel (DE)
- Preserve clinical accuracy
- Provide patient-friendly explanations

---

## 4. /compliance-audit

**Purpose**: Check code for regulatory compliance

**Arguments**: `$ARGUMENTS` (path and compliance standard)

**YAML**:

```yaml
---
description: Audit code for HIPAA/GDPR/DSGVO compliance requirements
argument-hint: [code-path] [hipaa|gdpr|dsgvo|all]
allowed-tools: Read, Grep, Task
---
```

**What it does**:

- Scan for PHI/PII handling
- Check encryption requirements
- Verify audit logging
- Validate data subject rights
- Generate compliance report

---

## 5. /api-build

**Purpose**: Generate complete API integration code

**Arguments**: `$ARGUMENTS` (API name and endpoints)

**YAML**:

```yaml
---
description: Generate complete API client with error handling and tests
argument-hint: [api-name] [endpoints]
allowed-tools: Read, Write, Edit, Bash, Task
---
```

**What it does**:

- Generate API client classes
- Add error handling and retries
- Create authentication logic
- Generate unit and integration tests
- Add usage documentation

---

## 6. /test-auto

**Purpose**: Auto-generate comprehensive test suites

**Arguments**: `$ARGUMENTS` (file path and test type)

**YAML**:

```yaml
---
description: Auto-generate comprehensive test suite with coverage analysis
argument-hint: [file-path] [unit|integration|e2e]
allowed-tools: Read, Write, Bash
---
```

**What it does**:

- Analyze code to test
- Generate test cases (happy path, edge cases, errors)
- Add test fixtures and mocks
- Calculate coverage
- Provide testing documentation

---

## 7. /docs-generate

**Purpose**: Automated documentation generation

**Arguments**: `$ARGUMENTS` (code path and doc type)

**YAML**:

```yaml
---
description: Auto-generate documentation from code (API docs, README, architecture)
argument-hint: [code-path] [api|readme|architecture|all]
allowed-tools: Read, Write, Grep
---
```

**What it does**:

- Extract code structure and functions
- Generate API documentation
- Create README with usage examples
- Build architecture diagrams (Mermaid)
- Add code examples

---

## 8. /knowledge-mine

**Purpose**: Extract structured insights from documents

**Arguments**: `$ARGUMENTS` (document path and output format)

**YAML**:

```yaml
---
description: Extract and structure knowledge from documents into actionable insights
argument-hint: [doc-path] [faq|summary|kb|all]
allowed-tools: Read, Grep
---
```

**What it does**:

- Read and analyze documents
- Extract key insights
- Generate FAQs
- Create knowledge base articles
- Summarize findings

---

## 9. /workflow-analyze

**Purpose**: Analyze and optimize business workflows

**Arguments**: `$ARGUMENTS` (workflow description)

**YAML**:

```yaml
---
description: Analyze workflows and provide optimization recommendations
argument-hint: [workflow-description]
allowed-tools: Read, Task
---
```

**What it does**:

- Map current workflow
- Identify bottlenecks
- Suggest automation opportunities
- Calculate efficiency gains
- Create implementation roadmap

---

## 10. /batch-agents

**Purpose**: Launch multiple coordinated agents

**Arguments**: `$ARGUMENTS` (agent names and task)

**YAML**:

```yaml
---
description: Launch and coordinate multiple agents for complex tasks
argument-hint: [agent-names] [task-description]
allowed-tools: Task
---
```

**What it does**:

- Parse agent list
- Launch agents in parallel (if safe) or sequential
- Coordinate outputs
- Integrate results
- Provide comprehensive summary
