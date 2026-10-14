# GitHub Actions CI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (\`- [ ]\`) syntax for tracking.

**Goal:** Add pull-request CI that enforces the repository's quality and security gates.

**Architecture:** A single, read-only GitHub Actions workflow uses separate frontend, backend, and security jobs. A small backend pytest module checks that the workflow retains every required gate and rejects an incomplete command set.

**Tech Stack:** GitHub Actions, Node 24/npm, Python 3.12/pytest/Ruff, pip-audit, Gitleaks.

## Global Constraints

- Trigger only for pull requests targeting \`main\`.
- Set workflow permissions to read-only \`contents\` and \`pull-requests\`; do not introduce secrets.
- Use existing npm workspace scripts and the API's Python project configuration.
- Fail on high-or-critical npm audit findings and on every auditable pip-audit finding.
- Scan pull-request changes with Gitleaks and fetch full history needed for the comparison.
- Keep unrelated \`pr19.diff\` and \`pr20.diff\` untracked and unmodified.

---

### Task 1: Add executable workflow contract tests

**Files:**
- Create: \`apps/api/tests/test_ci_workflow.py\`

**Interfaces:**
- Consumes: repository-root \`.github/workflows/ci.yml\` text.
- Produces: \`assert_required_ci_gates(workflow_text: str) -> None\` used by pytest tests.

- [ ] **Step 1: Write the failing test**

\`\`\`python
def test_ci_workflow_enforces_all_required_gates() -> None:
    assert_required_ci_gates(WORKFLOW_PATH.read_text(encoding="utf-8"))
\`\`\`

- [ ] **Step 2: Run test to verify it fails**

Run: \`python -m pytest apps/api/tests/test_ci_workflow.py -q\`

Expected: FAIL because \`.github/workflows/ci.yml\` does not exist.

- [ ] **Step 3: Add the contract helper and failure-path test**

\`\`\`python
def test_ci_workflow_contract_rejects_a_missing_gate() -> None:
    workflow = "\n".join(REQUIRED_SNIPPETS)
    with pytest.raises(AssertionError, match="npm run build"):
        assert_required_ci_gates(workflow.replace("npm run build", ""))
\`\`\`

- [ ] **Step 4: Run test to verify it still fails for the absent workflow**

Run: \`python -m pytest apps/api/tests/test_ci_workflow.py -q\`

Expected: FAIL only because the workflow file is absent.

### Task 2: Implement PR quality and security workflow

**Files:**
- Create: \`.github/workflows/ci.yml\`

**Interfaces:**
- Consumes: root npm scripts, \`apps/api/pyproject.toml\`, and Task 1's required snippets.
- Produces: \`CI\` check with frontend, backend, and security jobs on pull requests to \`main\`.

- [ ] **Step 1: Write the minimal workflow**

\`\`\`yaml
name: CI
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
\`\`\`

Add a Node 24 frontend job running \`npm ci\`, \`npm run lint\`, \`npm run typecheck\`, \`npm run test:run\`, and \`npm run build\`; a Python 3.12 backend job running \`ruff format --check .\`, \`ruff check .\`, and \`pytest\`; and a security job running \`npm audit --audit-level=high\`, \`pip-audit --skip-editable\`, and \`gitleaks/gitleaks-action@v2\` with full checkout history. Install the local API package editable so the audit excludes only that non-PyPI package while auditing its resolved third-party dependencies.

- [ ] **Step 2: Run the workflow contract test**

Run: \`python -m pytest apps/api/tests/test_ci_workflow.py -q\`

Expected: PASS (2 tests).

### Task 3: Validate local equivalents and inspect delivery diff

**Files:**
- Modify: \`.github/workflows/ci.yml\`
- Modify: \`apps/api/tests/test_ci_workflow.py\`

- [ ] **Step 1: Run formatting, linting, type check, tests, and build**

Run: \`npm run lint; npm run typecheck; npm run test:run; npm run build; python -m ruff format --check apps/api; python -m ruff check apps/api; python -m pytest apps/api/tests -q\`

Expected: every command exits 0.

- [ ] **Step 2: Run dependency and secret checks available locally**

Run: \`npm audit --audit-level=high; python -m pip_audit --skip-editable; gitleaks detect --no-git --redact .\`

Expected: every installed available scanner exits 0; record unavailable tools precisely.

- [ ] **Step 3: Inspect the exact diff for unintended content and secrets**

Run: \`git diff --check main...HEAD; git status --short; git diff main...HEAD\`

Expected: only Issue #3 workflow, workflow-contract test, and approved planning documents are tracked; \`pr19.diff\` and \`pr20.diff\` remain untracked.

- [ ] **Step 4: Commit and publish**

\`\`\`bash
git add .github/workflows/ci.yml apps/api/tests/test_ci_workflow.py docs/superpowers/plans/2026-10-14-github-actions-ci.md
git commit -m "ci: add quality and security gates"
git push -u origin ci/3-github-actions
\`\`\`

- [ ] **Step 5: Create the issue-linked pull request**

Run: \`gh pr create --base main --head ci/3-github-actions --title "ci: add quality and security gates" --body "Closes #3 ..."\`

Expected: open PR targeting \`main\`, with validation evidence and no merge.
