# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Environment

Uses the `django` conda environment (Python 3.11, Django 5.2).

```bash
conda activate django
```

Always run `manage.py` commands from within this environment.

## Commands

```bash
# Run dev server
python manage.py runserver

# Apply migrations
python manage.py migrate

# Create new migrations after model changes
python manage.py makemigrations

# Run tests
python manage.py test

# Run a single test
python manage.py test accounts.tests.TestClassName.test_method_name

# Create superuser
python manage.py createsuperuser

# Django system check
python manage.py check
```

## Architecture

Single Django app (`accounts`) handling all auth and dashboard functionality. No external dependencies beyond Django itself — uses Django's built-in `auth` system (`UserCreationForm`, `AuthenticationForm`, `@login_required`).

**URL routing:** `mysite/urls.py` delegates everything to `accounts/urls.py` via `include()`.

**Auth flow:**
- `/` → redirects to `/login/` (or `/dashboard/` if already authenticated)
- `/register/` and `/login/` redirect to `/dashboard/` on success
- `/dashboard/` is protected by `@login_required` (redirects to `/login/` if not authenticated)
- Tab state is managed via `?tab=oferta1` or `?tab=oferta2` query param (default: `oferta1`)

**Templates:** Live in `templates/` at the project root (configured in `settings.py` `DIRS`). All templates extend `templates/base.html`. Styles are inline `<style>` blocks inside each template's `{% block extra_styles %}` — there is no separate CSS file or static asset pipeline in use.

**Database:** SQLite (`db.sqlite3`). Only Django's built-in tables are used — the `accounts` app has no custom models.

**Settings redirects:**
```python
LOGIN_URL = '/login/'
LOGIN_REDIRECT_URL = '/dashboard/'
LOGOUT_REDIRECT_URL = '/login/'
```

## Merge Guardrails (Claude + Codex)

This repo uses local guardrails to verify merge scope before integrating branches with double AI review.

### Components

- `scripts/pre-push`: git hook that runs Claude first and Codex second over the same push diff.
- `scripts/smart-merge.sh`: merge assistant for one branch (`--dry-run`, `--auto`, conflict resolution, scope validation with Claude + Codex).
- `scripts/smart-merge-all.sh`: orchestrates multiple branch merges against a base branch (`main` by default).

Install hook:

```bash
bash scripts/install-hooks.sh
```

### Recommended merge flow

Quick one-command flow (2 branches -> `main`):

```bash
bash scripts/merge-with-main.sh feature/landing-templates-redesign feature/landing-js-animations-funcionalidades
```

If you want local validation with Claude only (without local Codex second pass):

```bash
bash scripts/merge-with-main.sh feature/landing-templates-redesign feature/landing-js-animations-funcionalidades --claude-only
```

1. Pre-analyze candidate branches:

```bash
bash scripts/smart-merge-all.sh main --dry-run feature/redesign-landing-templates feature/redesign-landing-v2
```

2. Execute automatic merges (strict mode):

```bash
bash scripts/smart-merge-all.sh main feature/redesign-landing-templates feature/redesign-landing-v2
```

3. Optional technical checks before merge commit:

```bash
bash scripts/smart-merge-all.sh main --require-checks
```

Behavior in `--auto`:
- `APROBADO` => merge continues.
- `REVISAR` / `BLOQUEADO` / unclear verdict => merge is aborted.

### Operational limits

- Requires Claude CLI login and available credits.
- Requires Codex CLI available in PATH (or `CODEX_BIN`) for second-pass validation.
- If either reviewer is unavailable, scripts ask for explicit confirmation to continue (or abort automatically in strict `--auto` paths).
- `--require-checks` runs technical checks before final merge commit (default command in `smart-merge.sh`).
