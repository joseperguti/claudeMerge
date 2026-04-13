#!/usr/bin/env bash
# smart-merge-all.sh: orquestador de merges automáticos con Claude
#
# Uso:
#   bash scripts/smart-merge-all.sh
#   bash scripts/smart-merge-all.sh main
#   bash scripts/smart-merge-all.sh main feature/a feature/b
#   bash scripts/smart-merge-all.sh main --dry-run
#
# Comportamiento:
#   - Si no se indican ramas, descubre ramas locales con commits pendientes
#     respecto a la rama base.
#   - Ejecuta smart-merge.sh en modo --auto para cada rama.
#   - Solo mergea automáticamente cuando el veredicto es APROBADO.

set -euo pipefail

usage() {
  echo "Uso: bash scripts/smart-merge-all.sh [rama-base] [--dry-run] [rama1 rama2 ...]"
}

BASE_BRANCH="main"
BASE_SET=false
DRY_RUN=false
declare -a BRANCHES=()

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "❌  Opción no reconocida: $arg"
      usage
      exit 1
      ;;
    *)
      if [[ "$BASE_SET" == false ]]; then
        BASE_BRANCH="$arg"
        BASE_SET=true
      else
        BRANCHES+=("$arg")
      fi
      ;;
  esac
done

if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  echo "❌  Rama base '$BASE_BRANCH' no existe."
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
echo ""

merged=0
review=0
blocked=0
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
  if [[ "$DRY_RUN" == true ]]; then
    bash scripts/smart-merge.sh "$branch" --dry-run --auto
  else
    bash scripts/smart-merge.sh "$branch" --auto
  fi
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
echo "   • Fallos técnicos: $failed"
echo ""

if [[ "$DRY_RUN" == false ]]; then
  echo "Rama actual al finalizar: $(git rev-parse --abbrev-ref HEAD)"
fi

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi

exit 0
