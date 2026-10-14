from pathlib import Path

import pytest

WORKFLOW_PATH = Path(__file__).parents[3] / ".github" / "workflows" / "ci.yml"
PYPROJECT_PATH = Path(__file__).parents[1] / "pyproject.toml"

REQUIRED_SNIPPETS = (
    "pull_request:",
    "branches: [main]",
    "contents: read",
    "pull-requests: read",
    "node-version: 24",
    "npm ci",
    "npm run lint",
    "npm run typecheck",
    "npm run test:run",
    "npm run build",
    "python-version: '3.12'",
    "ruff format --check .",
    "ruff check .",
    "pytest",
    "npm audit --audit-level=high",
    "./apps/api[dev]",
    "pip-audit --skip-editable",
    "gitleaks/gitleaks-action@v2",
    "fetch-depth: 0",
)


def assert_required_ci_gates(workflow: str) -> None:
    for required_snippet in REQUIRED_SNIPPETS:
        assert required_snippet in workflow, f"Missing CI gate: {required_snippet}"


def test_ci_workflow_enforces_all_required_gates() -> None:
    assert WORKFLOW_PATH.is_file(), "CI workflow is missing"

    assert_required_ci_gates(WORKFLOW_PATH.read_text(encoding="utf-8"))


def test_ci_workflow_contract_rejects_a_missing_gate() -> None:
    workflow = "\n".join(REQUIRED_SNIPPETS)

    with pytest.raises(AssertionError, match="npm run build"):
        assert_required_ci_gates(workflow.replace("npm run build", ""))


def test_api_test_dependency_uses_a_non_vulnerable_pytest_version() -> None:
    pyproject = PYPROJECT_PATH.read_text(encoding="utf-8")

    assert "pytest>=9.0.3,<10.0" in pyproject
