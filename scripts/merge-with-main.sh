#!/usr/bin/env bash
# merge-with-main.sh: flujo único para mergear dos ramas sobre main.
#
# Uso:
#   bash scripts/merge-with-main.sh <rama-1> <rama-2> [--claude-only]
#
# Flujo:
#   1) checkout/pull main
#   2) dry-run de cada rama (smart-merge --dry-run --auto)
#   3) merge real de cada rama (smart-merge --auto --require-checks)
#   4) push origin main

set -euo pipefail

usage() {
  echo "Uso: bash scripts/merge-with-main.sh <rama-1> <rama-2> [--claude-only]"
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage
  exit 1
fi

BRANCH_1="$1"
BRANCH_2="$2"
CLAUDE_ONLY=false

if [[ $# -eq 3 ]]; then
  if [[ "$3" != "--claude-only" ]]; then
    usage
    exit 1
  fi
  CLAUDE_ONLY=true
fi

if [[ "$CLAUDE_ONLY" == true ]]; then
  export CODEX_BIN=""
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌  Hay cambios sin commitear. Limpia el árbol antes de mergear."
  exit 1
fi

run_dry() {
  local branch="$1"
  echo ""
  echo "🔎  Dry-run para '$branch'..."
  if bash scripts/smart-merge.sh "$branch" --dry-run --auto; then
    echo "✅  Dry-run APROBADO para '$branch'."
    return 0
  fi

  local code=$?
  case "$code" in
    2) echo "⚠️  Dry-run REVISAR para '$branch'. Se detiene el flujo." ;;
    3) echo "❌  Dry-run BLOQUEADO para '$branch'. Se detiene el flujo." ;;
    *) echo "❌  Dry-run con error para '$branch' (exit $code)." ;;
  esac
  return "$code"
}

run_merge() {
  local branch="$1"
  echo ""
  echo "🔀  Merge real para '$branch'..."
  bash scripts/smart-merge.sh "$branch" --auto --require-checks
}

echo "🔀  Cambiando a main..."
git checkout main

echo "⬇️  Actualizando main desde origin..."
git pull origin main

run_dry "$BRANCH_1"
run_dry "$BRANCH_2"

run_merge "$BRANCH_1"
run_merge "$BRANCH_2"

echo ""
echo "⬆️  Push de main..."
git push origin main

echo ""
echo "✅  Flujo completado."
echo "   Ramas mergeadas en orden:"
echo "   1) $BRANCH_1"
echo "   2) $BRANCH_2"
