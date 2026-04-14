# CLAUDE.md

This file provides guidance for automated PR reviews in this Django repository.

## Environment

Uses the `django` conda environment (Python 3.11, Django 5.2).

```bash
conda activate django
```

## Commands

```bash
python manage.py runserver
python manage.py migrate
python manage.py makemigrations
python manage.py test
python manage.py check
```

## Architecture

- Django project with app `accounts`.
- URL routing: `mysite/urls.py` -> `accounts/urls.py`.
- Templates in `templates/` (inline styles/scripts in template blocks).
- Main protected view: `/dashboard/`.

## PR Review Guide

### Objective

Verify that the PR description and commits match the actual diff.

### Detect

- Functional changes not described in PR/commits.
- Collateral changes not explained.
- Clear risks before merge.

### Sensitive Areas

- `templates/**`
- `templates/accounts/dashboard.html`
- `accounts/**`
- `mysite/**`
- `scripts/` related to merge/push

### Risks To Check

- `innerHTML` with dynamic content.
- `querySelector`/selectors built from unvalidated input.
- Poorly resolved merge conflicts.
- Visual refactors that break functionality.
- Mixed HTML/CSS/JS changes not described in the PR.

### Expected Review Output

- Real summary of what changed.
- PR/commit vs diff alignment.
- Detected risks.
- Suggested adjustments.
- Verdict: `OK` / `AJUSTAR` / `BLOQUEAR`.

## Local Scripts (Utilities Only)

Scripts under `scripts/` are local utilities. They do not define final merge governance.
Final merge decisions should be enforced through PR checks and branch protection in GitHub.

## CI Review Mode (Current)

- `Codex · PR review`: blocking check in GitHub branch protection.
- `Claude · PR review`: non-blocking fallback in CI when `ANTHROPIC_API_KEY` is missing or Claude app is not installed.
- Recommended: run Claude in local terminal before merge when CI Claude is unavailable.
