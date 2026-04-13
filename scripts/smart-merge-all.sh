#!/usr/bin/env bash
# smart-merge-all.sh: orquestador de merges automáticos con Claude
#
# Uso:
#   bash scripts/smart-merge-all.sh
#   bash scripts/smart-merge-all.sh main
#   bash scripts/smart-merge-all.sh main --dry-run
#   bash scripts/smart-merge-all.sh main --task-file scripts/backlog-task.md --require-checks
#   bash scripts/smart-merge-all.sh main feature/a feature/b

set -euo pipefail

usage() {
  echo "Uso: bash scripts/smart-merge-all.sh [rama-base] [--dry-run] [--task-file <ruta>|--task-file=<ruta>] [--require-checks] [--check-cmd <cmd>] [rama1 rama2 ...]"
}

BASE_BRANCH="main"
BASE_SET=false
DRY_RUN=false
TASK_FILE=""
REQUIRE_CHECKS=false
CHECK_CMD=""
declare -a BRANCHES=()
declare -a EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      EXTRA_ARGS+=("--dry-run")
      shift
      ;;
    --require-checks)
      REQUIRE_CHECKS=true
      EXTRA_ARGS+=("--require-checks")
      shift
      ;;
    --check-cmd)
      [[ $# -lt 2 ]] && echo "❌  Falta valor para --check-cmd" && exit 1
      CHECK_CMD="$2"
      EXTRA_ARGS+=("--check-cmd" "$2")
      shift 2
      ;;
    --task-file)
      [[ $# -lt 2 ]] && echo "❌  Falta ruta para --task-file" && exit 1
      TASK_FILE="$2"
      EXTRA_ARGS+=("--task-file" "$2")
      shift 2
      ;;
    --task-file=*)
      TASK_FILE="${1#*=}"
      EXTRA_ARGS+=("--task-file=$TASK_FILE")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "❌  Opción no reconocida: $1"
      usage
      exit 1
      ;;
    *)
      if [[ "$BASE_SET" == false ]]; then
        BASE_BRANCH="$1"
        BASE_SET=true
      else
        BRANCHES+=("$1")
      fi
      shift
      ;;
  esac
done

if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  echo "❌  Rama base '$BASE_BRANCH' no existe."
  exit 1
fi

if [[ -n "$TASK_FILE" && ! -f "$TASK_FILE" ]]; then
  echo "❌  --task-file no existe: $TASK_FILE"
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌  Tienes cambios sin commitear. Haz commit o stash antes de ejecutar smart-merge-all."
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "$BASE_BRANCH" ]]; then
  echo "🔀  Cambiando a rama base '$BASE_BRANCH'..."
  git checkout "$BASE_BRANCH"
fi

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
  mapfile -t BRANCHES < <(
    git for-each-ref --sort=committerdate --format='%(refname:short)' refs/heads | while read -r branch; do
      [[ "$branch" == "$BASE_BRANCH" ]] && continue
      ahead_count=$(git rev-list --count "$BASE_BRANCH..$branch" 2>/dev/null || echo 0)
      [[ "$ahead_count" -gt 0 ]] || continue
      echo "$branch"
    done
  )
fi

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
  echo "ℹ️  No hay ramas candidatas para mergear sobre '$BASE_BRANCH'."
  exit 0
fi

echo ""
echo "📋  Rama base: $BASE_BRANCH"
echo "📋  Ramas candidatas:"
for branch in "${BRANCHES[@]}"; do
  echo "   • $branch"
done
[[ -n "$TASK_FILE" ]] && echo "📋  Contexto backlog: $TASK_FILE"
[[ "$REQUIRE_CHECKS" == true ]] && echo "📋  Checks obligatorios: ${CHECK_CMD:-SMART_MERGE_CHECK_CMD o default}"
echo ""

merged=0
review=0
blocked=0
check_fail=0
failed=0

for branch in "${BRANCHES[@]}"; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🚀  Procesando rama: $branch"

  if ! git rev-parse --verify "$branch" >/dev/null 2>&1; then
    echo "❌  Rama '$branch' no existe."
    failed=$((failed + 1))
    echo ""
    continue
  fi

  set +e
  bash scripts/smart-merge.sh "$branch" --auto "${EXTRA_ARGS[@]}"
  code=$?
  set -e

  case "$code" in
    0)
      if [[ "$DRY_RUN" == true ]]; then
        echo "✅  APROBADO (dry-run): '$branch' es mergeable."
      else
        echo "✅  Merge completado: '$branch'."
      fi
      merged=$((merged + 1))
      ;;
    2)
      echo "⚠️  REVISAR: '$branch' se omite en modo automático."
      review=$((review + 1))
      ;;
    3)
      echo "❌  BLOQUEADO: '$branch' no se mergea."
      blocked=$((blocked + 1))
      ;;
    5)
      echo "❌  Checks técnicos fallidos: '$branch' no se mergea."
      check_fail=$((check_fail + 1))
      ;;
    *)
      echo "❌  Error/resultado no claro al procesar '$branch' (exit $code)."
      failed=$((failed + 1))
      ;;
  esac

  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊  Resumen"
echo "   • Aprobadas y procesadas: $merged"
echo "   • En revisión (omitidas): $review"
echo "   • Bloqueadas: $blocked"
echo "   • Checks fallidos: $check_fail"
echo "   • Fallos técnicos: $failed"
echo ""

if [[ "$DRY_RUN" == false ]]; then
  echo "Rama actual al finalizar: $(git rev-parse --abbrev-ref HEAD)"
fi

if [[ "$failed" -gt 0 || "$check_fail" -gt 0 ]]; then
  exit 1
fi

exit 0
