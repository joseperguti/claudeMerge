#!/usr/bin/env bash
# Instala los git hooks del proyecto en .git/hooks/
set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_DIR="$REPO_ROOT/.git/hooks"
SCRIPTS_DIR="$REPO_ROOT/scripts"

echo "Instalando hooks en $HOOKS_DIR ..."

cp "$SCRIPTS_DIR/pre-push" "$HOOKS_DIR/pre-push"
chmod +x "$HOOKS_DIR/pre-push"

echo "✅  pre-push instalado."
echo ""
echo "Scripts disponibles:"
echo "  bash scripts/smart-merge.sh <rama>           — merge con resolución inteligente"
echo "  bash scripts/smart-merge.sh <rama> --dry-run — analiza el merge sin ejecutarlo"
echo "  bash scripts/smart-merge.sh <rama> --require-checks — exige checks técnicos"
echo "  bash scripts/smart-merge-all.sh main         — procesa todas las ramas candidatas"
echo "  bash scripts/smart-merge-all.sh main --dry-run — pre-analiza sin mergear"
echo "  bash scripts/merge-with-main.sh <rama1> <rama2> [--claude-only] — flujo completo de merge a main"
echo ""
echo "Requisitos:"
echo "  - Claude CLI (default: /Users/josemaria/.local/bin/claude)"
echo "  - Codex CLI accesible en PATH (o export CODEX_BIN=/ruta/codex)"
echo "Para saltar la revisión puntualmente: git push --no-verify"
