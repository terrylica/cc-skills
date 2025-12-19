# Prompt Templates

Battle-tested PROMPT.md templates for common use cases. Copy and customize for your projects.

## Template Index

1. [REST API Development](#1-rest-api-development)
2. [CLI Tool Creation](#2-cli-tool-creation)
3. [Test Suite Generation](#3-test-suite-generation)
4. [Documentation Generation](#4-documentation-generation)
5. [Database Schema and Migrations](#5-database-schema-and-migrations)
6. [Refactoring Campaign](#6-refactoring-campaign)
7. [Bug Investigation and Fix](#7-bug-investigation-and-fix)
8. [Data Pipeline](#8-data-pipeline)
9. [Web Scraper](#9-web-scraper)
10. [Library/Package Creation](#10-librarypackage-creation)
11. [Greenfield Application](#11-greenfield-application)
12. [Integration Layer](#12-integration-layer)

---

## 1. REST API Development

```markdown
# Task: Build User Management REST API

## Objective

Create a production-ready REST API for user management with authentication, validation, and comprehensive tests.

## Technical Stack

- Framework: FastAPI (Python 3.11+)
- Database: PostgreSQL with SQLAlchemy ORM
- Authentication: JWT tokens
- Validation: Pydantic models
- Testing: pytest with >90% coverage

## API Endpoints

| Method | Endpoint       | Description                  |
| ------ | -------------- | ---------------------------- |
| POST   | /auth/register | Create new user account      |
| POST   | /auth/login    | Authenticate and receive JWT |
| POST   | /auth/refresh  | Refresh expired token        |
| GET    | /users         | List all users (paginated)   |
| GET    | /users/{id}    | Get single user              |
| PUT    | /users/{id}    | Update user                  |
| DELETE | /users/{id}    | Soft delete user             |

## Data Models

### User

- id: UUID (primary key)
- email: string (unique, validated)
- password_hash: string
- full_name: string
- is_active: boolean (default: true)
- created_at: datetime
- updated_at: datetime

## Requirements

1. Input validation on all endpoints
2. Proper HTTP status codes (200, 201, 400, 401, 404, 422)
3. Error responses in consistent JSON format
4. Password hashing using bcrypt
5. Rate limiting on auth endpoints
6. Request/response logging
7. OpenAPI documentation auto-generated
8. Database migrations with Alembic

## Project Structure
```

user-api/
├── app/
│ ├── **init**.py
│ ├── main.py
│ ├── config.py
│ ├── models/
│ ├── schemas/
│ ├── routers/
│ ├── services/
│ └── utils/
├── tests/
├── alembic/
├── requirements.txt
└── README.md

```

## Success Criteria

The task is complete when:
- [ ] All endpoints implemented and functional
- [ ] JWT authentication working
- [ ] Database migrations set up
- [ ] Tests passing with >90% coverage
- [ ] README with setup instructions
- [ ] OpenAPI docs accessible at /docs

## Progress Tracking

- Status: Not Started
- Iteration: 0
- Completed: None

---
The orchestrator will continue iterations until limits are reached.
```

---

## 2. CLI Tool Creation

````markdown
# Task: Build File Organization CLI Tool

## Objective

Create a Python CLI tool for organizing files with multiple organization strategies and safety features.

## Commands

```bash
organize photos <directory>      # By date taken (EXIF)
organize documents <directory>   # By file type
organize downloads <directory>   # By age and type
organize custom <directory> --config <file>
```
````

## Features

1. **Core Operations**
   - Dry-run mode (--dry-run)
   - Verbose output (--verbose)
   - Progress bar for large operations
   - Undo functionality (--undo)

2. **Organization Strategies**
   - Photos: Year/Month folders from EXIF data
   - Documents: Extension-based folders (pdf/, docx/, txt/)
   - Downloads: Archive old files, group by type
   - Custom: User-defined rules in YAML config

3. **Safety Features**
   - Never delete files (move only)
   - Create backups before moving
   - Handle duplicate filenames
   - Preserve file permissions and timestamps
   - Skip system/hidden files by default

## Technical Requirements

- Python 3.11+
- Click for CLI framework
- Rich for terminal output
- Pillow for EXIF extraction
- PyYAML for config files

## Project Structure

```
file-organizer/
├── file_organizer/
│   ├── __init__.py
│   ├── cli.py
│   ├── organizers/
│   │   ├── photo.py
│   │   ├── document.py
│   │   └── custom.py
│   └── utils/
│       ├── backup.py
│       └── config.py
├── tests/
├── pyproject.toml
└── README.md
```

## Success Criteria

- [ ] All commands functional
- [ ] Dry-run mode works correctly
- [ ] Undo restores original state
- [ ] Tests cover all organizers
- [ ] README with usage examples

---

The orchestrator will continue iterations until limits are reached.

````

---

## 3. Test Suite Generation {#3-test-suite-generation}

```markdown
# Task: Generate Comprehensive Test Suite

## Objective

Create a thorough test suite for existing codebase with unit, integration, and edge case tests.

## Target Coverage

- Overall: >90%
- Critical paths: 100%
- Edge cases: Comprehensive

## Test Categories

### Unit Tests
- All public functions/methods
- Input validation
- Error handling paths
- Return value verification

### Integration Tests
- Database operations
- API endpoint flows
- External service interactions (mocked)

### Edge Cases
- Empty inputs
- Maximum values
- Invalid types
- Concurrent access
- Network failures

## Testing Framework

- pytest with plugins:
  - pytest-cov (coverage)
  - pytest-asyncio (async tests)
  - pytest-mock (mocking)
  - pytest-xdist (parallel execution)

## Test Structure

````

tests/
├── conftest.py # Shared fixtures
├── unit/
│ ├── test_models.py
│ ├── test_services.py
│ └── test_utils.py
├── integration/
│ ├── test_api.py
│ └── test_database.py
└── edge_cases/
└── test_boundaries.py

```

## Requirements

1. Each test function tests ONE behavior
2. Descriptive test names (test_<function>_<scenario>_<expected>)
3. Arrange-Act-Assert pattern
4. No test interdependencies
5. Fast execution (<30 seconds total)
6. Clear failure messages

## Success Criteria

- [ ] Coverage report shows >90%
- [ ] All tests pass
- [ ] Tests run in <30 seconds
- [ ] No flaky tests
- [ ] conftest.py with reusable fixtures

## Current Codebase

[Describe the codebase to test or let Ralph discover it]

---
The orchestrator will continue iterations until limits are reached.
```

---

## 4. Documentation Generation

```markdown
# Task: Create Comprehensive Documentation

## Objective

Generate complete user and developer documentation for the project.

## Documentation Types

### User Documentation

- Getting Started guide
- Installation instructions
- Configuration reference
- Usage examples
- FAQ
- Troubleshooting guide

### Developer Documentation

- Architecture overview
- API reference
- Contributing guide
- Code style guide
- Testing guide

## Structure
```

docs/
├── index.md # Overview and navigation
├── getting-started.md # Quick start guide
├── installation.md # Detailed installation
├── configuration.md # All config options
├── usage/
│ ├── basic.md # Basic usage
│ └── advanced.md # Advanced features
├── api/
│ ├── overview.md # API concepts
│ └── reference.md # Full API reference
├── development/
│ ├── architecture.md # System design
│ └── contributing.md # How to contribute
├── troubleshooting.md # Common issues
└── faq.md # Frequently asked questions

```

## Requirements

1. Clear, concise language
2. Code examples for every feature
3. Screenshots/diagrams where helpful
4. Cross-references between sections
5. Version compatibility notes
6. Search-friendly headings

## Style Guide

- Use second person ("you")
- Active voice
- One concept per section
- Progressive disclosure (simple to complex)
- Tested code examples

## Success Criteria

- [ ] All sections complete
- [ ] Code examples tested
- [ ] No broken links
- [ ] Spell-checked
- [ ] README updated with doc links

---
The orchestrator will continue iterations until limits are reached.
```

---

## 5. Database Schema and Migrations

```markdown
# Task: Design and Implement Database Schema

## Objective

Create a robust database schema with migrations for a multi-tenant SaaS application.

## Domain Model

### Core Entities

- Organization (tenant)
- User (belongs to organization)
- Project (belongs to organization)
- Task (belongs to project)
- Comment (belongs to task)

### Relationships

- Organization has many Users
- Organization has many Projects
- User has many assigned Tasks
- Project has many Tasks
- Task has many Comments
- Comment belongs to User

## Technical Requirements

- PostgreSQL 15+
- SQLAlchemy 2.0 ORM
- Alembic migrations
- Multi-tenant isolation via organization_id

## Schema Features

1. **Soft deletes** on all entities
2. **Audit columns** (created_at, updated_at, created_by)
3. **Indexes** on foreign keys and common queries
4. **Constraints** for data integrity
5. **Enums** for status fields

## Migration Strategy

1. Initial schema creation
2. Seed data for development
3. Rollback capability for all migrations
4. Data migration helpers

## Success Criteria

- [ ] All models defined with relationships
- [ ] Migrations run cleanly
- [ ] Rollback works
- [ ] Seed data populates test data
- [ ] Query performance tested

## Constraints

- No circular foreign keys
- All deletes cascade appropriately
- Timestamps use UTC
- UUIDs for primary keys

---

The orchestrator will continue iterations until limits are reached.
```

---

## 6. Refactoring Campaign

```markdown
# Task: Refactor Legacy Module

## Objective

Refactor the [module_name] module to improve maintainability, testability, and performance.

## Current Issues

1. Large functions (>50 lines)
2. Deep nesting (>3 levels)
3. Duplicated code patterns
4. Missing type hints
5. No unit tests
6. Tight coupling to external services

## Refactoring Goals

### Code Quality

- Functions <20 lines
- Maximum 2 levels of nesting
- Extract duplicated code to utilities
- Add type hints everywhere
- Follow single responsibility principle

### Architecture

- Dependency injection for external services
- Interface abstractions for testability
- Configuration externalized
- Clear module boundaries

### Testing

- Unit tests for all functions
- Mock external dependencies
- > 90% coverage

## Constraints

- Maintain backward compatibility
- No behavior changes (pure refactor)
- Keep existing public API
- One commit per logical change

## Process

1. Add tests for existing behavior
2. Refactor with tests as safety net
3. Verify tests still pass
4. Document architectural decisions

## Success Criteria

- [ ] All existing tests pass
- [ ] New tests added (>90% coverage)
- [ ] No function >20 lines
- [ ] Type hints on all functions
- [ ] Linting passes (ruff check)

---

The orchestrator will continue iterations until limits are reached.
```

---

## 7. Bug Investigation and Fix

```markdown
# Task: Investigate and Fix Memory Leak

## Problem Description

Users report the application memory grows continuously and eventually crashes after ~24 hours of operation.

## Symptoms

- Memory starts at 200MB
- Grows ~50MB per hour under normal load
- OOM kill after ~24 hours
- No improvement after restart

## Investigation Steps

1. **Profile memory usage**
   - Add memory tracking instrumentation
   - Log memory at regular intervals
   - Identify growth patterns

2. **Analyze suspects**
   - Connection pools
   - Caching mechanisms
   - Event listeners
   - File handles
   - Long-lived objects

3. **Reproduce locally**
   - Create minimal reproduction
   - Confirm leak with tracemalloc

4. **Identify root cause**
   - Document the leaking component
   - Explain why it leaks

5. **Implement fix**
   - Minimal change to fix issue
   - Add regression test

## Required Output

- Memory profile before/after
- Root cause analysis document
- Fix with explanation
- Regression test

## Success Criteria

- [ ] Root cause identified
- [ ] Fix implemented
- [ ] Memory stable over 4-hour test
- [ ] Regression test added
- [ ] Documentation updated

---

The orchestrator will continue iterations until limits are reached.
```

---

## 8. Data Pipeline

```markdown
# Task: Build ETL Data Pipeline

## Objective

Create a data pipeline to extract, transform, and load sales data for analytics.

## Data Flow
```

Source (CSV/API) → Extract → Transform → Load → Target (PostgreSQL)

```

## Source Data

- Daily CSV files from SFTP
- REST API for real-time updates
- Schema: order_id, customer_id, product_id, quantity, price, timestamp

## Transformations

1. **Cleaning**
   - Remove duplicates
   - Handle missing values
   - Validate data types

2. **Enrichment**
   - Join customer demographics
   - Add product categories
   - Calculate derived metrics

3. **Aggregation**
   - Daily totals by product
   - Weekly trends by region
   - Monthly customer cohorts

## Target Schema

- fact_orders (transactional)
- dim_customers (slowly changing)
- dim_products (versioned)
- agg_daily_sales (pre-computed)

## Technical Requirements

- Python 3.11+
- pandas for transformations
- SQLAlchemy for database
- Schedule or Airflow for orchestration
- Logging and monitoring
- Error recovery and retries

## Success Criteria

- [ ] Full pipeline implemented
- [ ] Handles 1M+ records
- [ ] Idempotent runs
- [ ] Error notifications
- [ ] Documentation

---
The orchestrator will continue iterations until limits are reached.
```

---

## 9. Web Scraper

````markdown
# Task: Build Product Price Scraper

## Objective

Create a web scraper to monitor competitor prices across multiple e-commerce sites.

## Target Sites

- Site A: example-store.com
- Site B: another-shop.com
- Site C: third-retailer.com

## Data to Extract

- Product name
- Current price
- Original price (if on sale)
- Availability status
- Last updated timestamp

## Technical Requirements

- Python 3.11+
- httpx for requests
- BeautifulSoup for parsing
- Respect robots.txt
- Rate limiting (1 req/sec per site)
- User-agent rotation
- Proxy support (optional)

## Features

1. **Resilience**
   - Retry on failure
   - Handle site changes gracefully
   - Alert on parsing errors

2. **Storage**
   - SQLite for local storage
   - Price history tracking
   - Export to CSV/JSON

3. **Scheduling**
   - Run every 4 hours
   - Configurable per site
   - Prevent overlapping runs

## Output Format

```json
{
  "site": "example-store.com",
  "product_id": "SKU123",
  "name": "Product Name",
  "price": 29.99,
  "original_price": 39.99,
  "in_stock": true,
  "scraped_at": "2025-01-15T10:30:00Z"
}
```
````

## Success Criteria

- [ ] Scrapes all target sites
- [ ] Stores price history
- [ ] Handles errors gracefully
- [ ] Respects rate limits
- [ ] Tests with mocked responses

---

The orchestrator will continue iterations until limits are reached.

````

---

## 10. Library/Package Creation {#10-librarypackage-creation}

```markdown
# Task: Create Python Utility Library

## Objective

Build a reusable Python library for common data validation and transformation operations.

## Package Name

`datavalidator`

## Core Features

### Validators
- Email format
- Phone numbers (international)
- URLs (with scheme validation)
- Credit card numbers (Luhn check)
- UUIDs
- Dates (multiple formats)

### Transformers
- String normalization
- Phone number formatting
- Currency formatting
- Date parsing and conversion
- Slug generation

### Decorators
- @validate_args
- @transform_output
- @retry
- @cache_result

## API Design

```python
from datavalidator import validate, transform

# Validation
validate.email("user@example.com")  # True
validate.phone("+1-555-1234")       # True

# Transformation
transform.phone("+15551234")        # "+1 (555) 123-4"
transform.slug("Hello World!")      # "hello-world"

# Decorators
@validate_args(email=validate.email)
def send_email(email: str, message: str):
    ...
````

## Technical Requirements

- Python 3.11+
- Zero external dependencies for core
- Type hints throughout
- 100% test coverage
- Sphinx documentation

## Project Structure

```
datavalidator/
├── src/
│   └── datavalidator/
│       ├── __init__.py
│       ├── validators/
│       ├── transformers/
│       └── decorators/
├── tests/
├── docs/
├── pyproject.toml
└── README.md
```

## Success Criteria

- [ ] All validators implemented
- [ ] All transformers implemented
- [ ] 100% test coverage
- [ ] Type hints complete
- [ ] Published to TestPyPI

---

The orchestrator will continue iterations until limits are reached.

````

---

## 11. Greenfield Application {#11-greenfield-application}

```markdown
# Task: Build Task Management Application

## Objective

Create a complete task management web application from scratch.

## Features

### User Management
- Registration/login
- Password reset
- Profile management

### Task Management
- Create, edit, delete tasks
- Due dates and reminders
- Priority levels
- Tags and categories
- Task assignment

### Project Organization
- Projects contain tasks
- Project members
- Project templates

### Dashboard
- Today's tasks
- Overdue items
- Weekly overview
- Progress charts

## Technical Stack

### Backend
- FastAPI (Python 3.11+)
- PostgreSQL + SQLAlchemy
- Redis for caching
- Celery for background tasks

### Frontend
- React 18 + TypeScript
- TailwindCSS
- React Query

### Infrastructure
- Docker Compose for local dev
- GitHub Actions CI/CD

## Project Structure

````

taskmanager/
├── backend/
│ ├── app/
│ ├── tests/
│ └── Dockerfile
├── frontend/
│ ├── src/
│ └── Dockerfile
├── docker-compose.yml
└── README.md

```

## Success Criteria

- [ ] User auth working
- [ ] CRUD for tasks/projects
- [ ] Dashboard functional
- [ ] Docker Compose runs cleanly
- [ ] Basic tests passing

## Phase 1 Focus (This Run)

Focus on backend API only:
- [ ] Database models
- [ ] Auth endpoints
- [ ] Task CRUD endpoints
- [ ] Tests

---
The orchestrator will continue iterations until limits are reached.
```

---

## 12. Integration Layer

```markdown
# Task: Build Third-Party Integration Layer

## Objective

Create an integration layer to connect with multiple external services via a unified interface.

## Services to Integrate

| Service  | Purpose       | Auth Type |
| -------- | ------------- | --------- |
| Stripe   | Payments      | API Key   |
| SendGrid | Email         | API Key   |
| Twilio   | SMS           | Token     |
| AWS S3   | Storage       | IAM       |
| Slack    | Notifications | OAuth     |

## Architecture
```

Application → Integration Layer → External Services
↓
Unified Interface

````

## Interface Design

```python
# Unified interface
from integrations import PaymentProvider, EmailProvider

# All providers follow same pattern
payment = PaymentProvider.get("stripe")
payment.charge(amount=1000, currency="USD", customer_id="cust_123")

email = EmailProvider.get("sendgrid")
email.send(to="user@example.com", template="welcome", data={...})
````

## Features

1. **Provider Abstraction**
   - Swap providers without code changes
   - Consistent error handling
   - Unified logging

2. **Resilience**
   - Retry with exponential backoff
   - Circuit breaker pattern
   - Fallback providers

3. **Observability**
   - Request/response logging
   - Metrics collection
   - Health checks

## Technical Requirements

- Python 3.11+
- httpx for HTTP clients
- pydantic for data validation
- tenacity for retries
- Environment-based configuration

## Success Criteria

- [ ] All providers implemented
- [ ] Unified interface working
- [ ] Retry logic functional
- [ ] Tests with mocked responses
- [ ] Documentation complete

---

The orchestrator will continue iterations until limits are reached.

```

---

## Template Tips

### Effective Prompts Have

1. **Clear objective** - One sentence summary
2. **Specific requirements** - Numbered, measurable
3. **Technical constraints** - Stack, versions, limits
4. **Success criteria** - Checkboxes for verification
5. **Progress tracking** - For Ralph to update

### Common Pitfalls

- Vague goals ("make it better")
- Missing context (assumed knowledge)
- Too many requirements (scope creep)
- No success criteria (never-ending loop)
- Contradictory constraints

### Iteration Optimization

For faster convergence:
- Start with MVP, add features later
- Provide examples of desired output
- Specify file structure upfront
- Include error handling requirements early
```
