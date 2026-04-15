#!/usr/bin/env bash
# clean-branches.sh: borrar ramas locales y remotas ya mergeadas en la rama base
#
# Uso:
#   bash scripts/clean-branches.sh
#   bash scripts/clean-branches.sh --base main
#   bash scripts/clean-branches.sh --dry-run
#   bash scripts/clean-branches.sh --auto
#   bash scripts/clean-branches.sh --remote-only
#   bash scripts/clean-branches.sh --local-only
#
# Notas:
#   - Por defecto trabaja sobre la rama base 'main'.
#   - Sin --auto pide confirmación antes de borrar.
#   - --dry-run muestra qué se borraría sin hacer nada.
#   - Nunca borra las ramas protegidas: main, master, develop, staging, production.

set -euo pipefail

PROTECTED_BRANCHES=("main" "master" "develop" "staging" "production")

usage() {
  echo "Uso: bash scripts/clean-branches.sh [--base <rama>] [--dry-run] [--auto] [--remote-only] [--local-only]"
  echo ""
  echo "  --base <rama>   Rama base contra la que comparar (default: main)"
  echo "  --dry-run       Mostrar qué se borraría sin borrar nada"
  echo "  --auto          Borrar sin pedir confirmación"
  echo "  --remote-only   Solo borrar ramas remotas"
  echo "  --local-only    Solo borrar ramas locales"
  echo "  -h, --help      Mostrar esta ayuda"
}

is_protected() {
  local branch="$1"
  for protected in "${PROTECTED_BRANCHES[@]}"; do
    [[ "$branch" == "$protected" ]] && return 0
  done
  return 1
}

confirm_or_abort() {
  local message="$1"
  printf "%s [s/N] " "$message"
  read -r answer < /dev/tty
  [[ "$answer" =~ ^[sS]$ ]]
}

BASE_BRANCH="main"
DRY_RUN=false
AUTO_MODE=false
REMOTE_ONLY=false
LOCAL_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -lt 2 ]] && echo "Falta valor para --base" && exit 1
      BASE_BRANCH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --auto)
      AUTO_MODE=true
      shift
      ;;
    --remote-only)
      REMOTE_ONLY=true
      shift
      ;;
    --local-only)
      LOCAL_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Opcion no reconocida: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$REMOTE_ONLY" == true && "$LOCAL_ONLY" == true ]]; then
  echo "No puedes usar --remote-only y --local-only al mismo tiempo."
  exit 1
fi

# Verificar que la rama base existe
if ! git rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
  echo "La rama base '$BASE_BRANCH' no existe."
  exit 1
fi

echo ""
echo "Rama base: $BASE_BRANCH"
[[ "$DRY_RUN" == true ]] && echo "Modo: dry-run (no se borrara nada)"
[[ "$AUTO_MODE" == true ]] && echo "Modo: automatico (sin confirmacion)"
echo ""

# Sincronizar referencias remotas
echo "Sincronizando referencias remotas..."
git fetch --prune origin 2>/dev/null || true
echo ""

# ─── Ramas locales mergeadas ──────────────────────────────────────────────────
declare -a LOCAL_TO_DELETE=()

if [[ "$REMOTE_ONLY" == false ]]; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    branch="${branch#"${branch%%[! ]*}"}"  # trim leading spaces/asterisk
    branch="${branch#\* }"                 # remove "* " prefix for current branch

    is_protected "$branch" && continue
    [[ "$branch" == "$CURRENT_BRANCH" ]] && continue
    [[ "$branch" == "$BASE_BRANCH" ]] && continue

    LOCAL_TO_DELETE+=("$branch")
  done < <(git branch --merged "$BASE_BRANCH" 2>/dev/null)
fi

# ─── Ramas remotas mergeadas ─────────────────────────────────────────────────
declare -a REMOTE_TO_DELETE=()

if [[ "$LOCAL_ONLY" == false ]]; then
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    branch="${branch#"${branch%%[! ]*}"}"  # trim leading spaces
    branch="${branch#remotes/origin/}"

    is_protected "$branch" && continue
    [[ "$branch" == "HEAD" ]] && continue
    [[ "$branch" == "$BASE_BRANCH" ]] && continue

    REMOTE_TO_DELETE+=("$branch")
  done < <(git branch -r --merged "origin/$BASE_BRANCH" 2>/dev/null | grep "origin/" | grep -v "HEAD")
fi

# ─── Resumen ──────────────────────────────────────────────────────────────────
if [[ ${#LOCAL_TO_DELETE[@]} -eq 0 && ${#REMOTE_TO_DELETE[@]} -eq 0 ]]; then
  echo "No se encontraron ramas mergeadas para borrar."
  exit 0
fi

if [[ ${#LOCAL_TO_DELETE[@]} -gt 0 ]]; then
  echo "Ramas locales ya mergeadas en '$BASE_BRANCH':"
  for branch in "${LOCAL_TO_DELETE[@]}"; do
    echo "  - $branch"
  done
  echo ""
fi

if [[ ${#REMOTE_TO_DELETE[@]} -gt 0 ]]; then
  echo "Ramas remotas ya mergeadas en '$BASE_BRANCH':"
  for branch in "${REMOTE_TO_DELETE[@]}"; do
    echo "  - origin/$branch"
  done
  echo ""
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry-run completado. Usa sin --dry-run para borrar."
  exit 0
fi

# ─── Confirmacion ─────────────────────────────────────────────────────────────
if [[ "$AUTO_MODE" == false ]]; then
  total=$((${#LOCAL_TO_DELETE[@]} + ${#REMOTE_TO_DELETE[@]}))
  if ! confirm_or_abort "Borrar $total rama(s)?"; then
    echo "Operacion cancelada."
    exit 0
  fi
  echo ""
fi

# ─── Borrado ──────────────────────────────────────────────────────────────────
deleted_local=0
failed_local=0
deleted_remote=0
failed_remote=0

for branch in "${LOCAL_TO_DELETE[@]}"; do
  if git branch -d "$branch" 2>/dev/null; then
    echo "Borrada local: $branch"
    deleted_local=$((deleted_local + 1))
  else
    echo "Error borrando local: $branch"
    failed_local=$((failed_local + 1))
  fi
done

for branch in "${REMOTE_TO_DELETE[@]}"; do
  if git push origin --delete "$branch" 2>/dev/null; then
    echo "Borrada remota: origin/$branch"
    deleted_remote=$((deleted_remote + 1))
  else
    echo "Error borrando remota: origin/$branch"
    failed_remote=$((failed_remote + 1))
  fi
done

# ─── Resultado ────────────────────────────────────────────────────────────────
echo ""
echo "Resultado:"
echo "  Locales borradas:  $deleted_local  (errores: $failed_local)"
echo "  Remotas borradas:  $deleted_remote  (errores: $failed_remote)"

if [[ $((failed_local + failed_remote)) -gt 0 ]]; then
  exit 1
fi

exit 0
