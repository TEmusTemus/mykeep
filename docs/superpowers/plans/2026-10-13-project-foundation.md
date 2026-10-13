# MyKeep Project Foundation Implementation Plan

> **For agentic workers:** Use a single-agent workflow by default for straightforward implementation, documentation, and configuration tasks. Use additional agents and repeated reviews only when higher-priority instructions permit and the work is complex architecture, authentication, security, or difficult debugging. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish the repository governance, architecture reference, delivery roadmap, GitHub templates, and issue plan required before MyKeep application feature work begins.

**Architecture:** Documentation at the repository root defines project-wide contribution and security rules; `docs/` contains the durable architecture, roadmap, checklist, and issue map. GitHub issues and milestones mirror the roadmap so every implementation change has an independently reviewable, dependency-aware work item.

**Tech Stack:** Markdown, YAML, GitHub Issues, GitHub Milestones, GitHub Actions conventions.

## Global Constraints

- Do not implement React, FastAPI, database, or Storage application features in this issue.
- Use GitHub Issues to track all work, one feature branch per issue, Conventional Commits, and issue-linked pull requests.
- Never commit credentials, tokens, private keys, connection strings, or deployed environment files.
- `main` is PR-only; merge and deployment require explicit user approval.
- The chosen architecture is server-mediated FastAPI authorization, server-side LINE ID-token verification, private Supabase Storage, and strict per-member isolation.

---

### Task 1: Create repository governance and security policies

**Files:**
- Create: `AGENTS.md`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `docs/development-checklist.md`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-10-13-mykeep-foundation-design.md`
- Produces: Persistent implementation rules, contributor workflow, security reporting procedure, and PR readiness checklist.

- [ ] **Step 1: Define agent operating rules in `AGENTS.md`**

Document the stack, security invariants, repository layout to be introduced by later issues, branch/commit/PR rules, required validation, secret handling, and the rule that dependent work waits for an approved-and-merged prerequisite PR.

- [ ] **Step 2: Define human contribution workflow in `CONTRIBUTING.md`**

Document issue selection, `main` synchronization, branch naming as `<type>/<issue>-<slug>`, Conventional Commit format, required test evidence, PR description expectations, review, and no-direct-main policy.

- [ ] **Step 3: Define vulnerability reporting and security policy in `SECURITY.md`**

Provide a private GitHub security-advisory reporting route, state that secrets and private member/file data must not be included in reports, list supported versions once releases exist, and state the remediation and disclosure expectations.

- [ ] **Step 4: Define the development checklist**

List required implementation, verification, diff/secret review, PR, CI, and approval gates in the execution order mandated by this repository.

- [ ] **Step 5: Validate documentation hygiene**

Run: `git diff --check`
Expected: exit code `0`.

Run: `rg -n -i 'to[d]o|tb[d]|placeholder|api[_-]?key\s*=|service[_-]?role' AGENTS.md CONTRIBUTING.md SECURITY.md docs/development-checklist.md`
Expected: no incomplete-task markers or credential assignments; policy prose may mention a secret by name only when explaining that it must not be committed.

### Task 2: Create GitHub issue and pull-request templates

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

**Interfaces:**
- Consumes: `AGENTS.md`, `CONTRIBUTING.md`, and `docs/development-checklist.md`
- Produces: Structured issue forms and a PR template that require scope, acceptance criteria, security consideration, validation evidence, issue-closing reference, and UI screenshots where applicable.

- [ ] **Step 1: Create the bug-report form**

Require reproducible steps, expected and actual behavior, environment, severity, security impact warning, and an optional attachment field that forbids credentials and private files.

- [ ] **Step 2: Create the feature-request form**

Require user outcome, in-scope and out-of-scope boundaries, acceptance criteria, privacy/security considerations, dependencies, and UI reference material when applicable.

- [ ] **Step 3: Create issue-template configuration**

Disable blank issues and direct security reports to the repository security policy.

- [ ] **Step 4: Create the pull-request template**

Require `Closes #<issue-number>`, a summary, scope exclusions, verification commands with observed results, screenshots for UI changes, security notes, migration/deployment notes, and a pre-merge checklist.

- [ ] **Step 5: Validate YAML and Markdown structure**

Run: `python -c "import pathlib, yaml; [yaml.safe_load(path.read_text(encoding='utf-8')) for path in pathlib.Path('.github/ISSUE_TEMPLATE').glob('*.yml')]; print('YAML OK')"`
Expected: `YAML OK`.

Run: `git diff --check`
Expected: exit code `0`.

### Task 3: Publish durable architecture and delivery roadmap documents

**Files:**
- Create: `docs/architecture.md`
- Create: `docs/roadmap.md`
- Create: `docs/issue-map.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: `docs/superpowers/specs/2026-10-13-mykeep-foundation-design.md`
- Produces: A concise, stable architecture reference; phased delivery order; and a cross-reference from implementation phases to GitHub issues, milestones, and dependencies.

- [ ] **Step 1: Write `docs/architecture.md`**

Summarize the approved trust boundaries, token verification sequence, session model, member and file ownership model, private-object path model, error handling, deployment topology, secrets policy, and testing layers. Link to the detailed foundation design for rationale.

- [ ] **Step 2: Write `docs/roadmap.md`**

Define eight delivery phases: foundation, tooling, persistence, authentication, file API, LIFF UI, reliability/security, and staging acceptance. For each phase, specify its outcome, prerequisites, and completion gate.

- [ ] **Step 3: Write `docs/issue-map.md`**

List every planned implementation issue with its future title, milestone, dependency issue number, deliverable, and completion evidence. State that issue numbers are assigned by GitHub during creation and update the map with the actual numbers in this issue.

- [ ] **Step 4: Update `README.md`**

Describe MyKeep in one paragraph, state that it is private family storage accessed through LIFF, and link to architecture, roadmap, contribution, security, and issue-map documents.

- [ ] **Step 5: Validate documentation links**

Run: `rg -n '\]\([^)]*\)' README.md docs/*.md`
Expected: every local Markdown link resolves to an existing file.

### Task 4: Establish GitHub taxonomy, milestones, and dependency-aware implementation issues

**Files:**
- Modify: `docs/issue-map.md`

**Interfaces:**
- Consumes: `docs/roadmap.md` and `docs/issue-map.md`
- Produces: GitHub labels, delivery milestones, and implementation issues with explicit acceptance criteria and dependencies represented in issue bodies and the issue map.

- [ ] **Step 1: Create repository labels**

Create `type:chore`, `type:feature`, `type:security`, `type:infra`, `area:frontend`, `area:backend`, `area:database`, `area:auth`, `area:storage`, `area:devops`, `priority:critical`, `priority:high`, and `status:blocked` while retaining GitHub's default labels.

- [ ] **Step 2: Create delivery milestones**

Create milestones for tooling baseline, persistence, authentication, file lifecycle, LIFF UI, reliability and security, and staging acceptance. Retain the existing project-foundation milestone.

- [ ] **Step 3: Create independent implementation issues in dependency order**

Create issues for monorepo/tooling, CI quality gates, Supabase schema and migrations, private bucket and policies, member provisioning CLI, LINE verification, sessions and authorization, file metadata API, private object lifecycle, LIFF shell, file management interface, recovery and audit jobs, security hardening, observability, container deployment, Vercel deployment, and staging acceptance.

- [ ] **Step 4: Record dependencies explicitly**

For every issue after tooling, include a `Depends on: #<number>` section and a `Blocked by: #<number>` label when an unmet prerequisite prevents work. Keep the same dependency edges in `docs/issue-map.md`.

- [ ] **Step 5: Verify GitHub planning state**

Run: `gh issue list --repo TEmusTemus/mykeep --state open --limit 100 --json number,title,milestone,labels,url`
Expected: Issue #1 and the planned implementation issues are present with milestones and appropriate labels.

Run: `gh api repos/TEmusTemus/mykeep/milestones?state=open`
Expected: project-foundation and all planned delivery milestones are present.

### Task 5: Review, commit, push, and open the Issue #1 pull request

**Files:**
- Modify: all files created by Tasks 1–4

**Interfaces:**
- Consumes: Issue #1 acceptance criteria and all prior task outputs.
- Produces: A conventional commit and PR that closes Issue #1 without merging it.

- [ ] **Step 1: Run the complete documentation validation suite**

Run: `git diff --check origin/main...HEAD`
Expected: exit code `0`.

Run: `rg -n -i 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{20,}|service_role\s*=|supabase.*secret' --glob '!docs/superpowers/specs/*' --glob '!docs/superpowers/plans/*' .`
Expected: no credential-like values.

Run: `python -c "import pathlib, yaml; [yaml.safe_load(path.read_text(encoding='utf-8')) for path in pathlib.Path('.github/ISSUE_TEMPLATE').glob('*.yml')]; print('YAML OK')"`
Expected: `YAML OK`.

- [ ] **Step 2: Review the change scope**

Run: `git diff --stat origin/main...HEAD` and `git diff --check origin/main...HEAD`.

Confirm only Issue #1 architecture, governance, roadmap, templates, checklist, and GitHub-planning artifacts changed.

- [ ] **Step 3: Commit documentation and planning changes**

Run: `git add AGENTS.md CONTRIBUTING.md SECURITY.md README.md docs .github`.

Run: `git commit -m "docs: establish project governance and roadmap"`.

- [ ] **Step 4: Push the feature branch and open the PR**

Run: `git push --set-upstream origin docs/1-project-foundation`.

Create a PR targeting `main` with `Closes #1`, a concise summary, all validation results, no UI screenshots because no UI changed, and a statement that no application features were implemented.

- [ ] **Step 5: Wait for CI and report status**

Run: `gh pr checks <pr-number> --repo TEmusTemus/mykeep --watch`.

If a check fails, inspect its log, correct only the relevant defect, recommit, push, and repeat validation. Do not merge.
