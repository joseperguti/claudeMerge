#!/usr/bin/env bash
# smart-merge.sh: merge asistido por Claude + Codex
#
# Uso:
#   bash scripts/smart-merge.sh <rama>
#   bash scripts/smart-merge.sh <rama> --dry-run
#   bash scripts/smart-merge.sh <rama> --auto
#   bash scripts/smart-merge.sh <rama> --require-checks
#
# Notas:
#   - En --auto solo mergea con veredicto APROBADO.
#   - --require-checks ejecuta verificaciones técnicas antes de confirmar merge.

set -euo pipefail

capture() { { eval "$1" || true; } 2>/dev/null | head -c "${2:-12000}"; }
extract_verdict() { { echo "$1" | grep -oE 'APROBADO|REVISAR|BLOQUEADO' | tail -1; } || true; }

usage() {
  echo "Uso: bash scripts/smart-merge.sh <rama> [--dry-run] [--auto] [--require-checks] [--check-cmd <cmd>]"
}

run_checks() {
  if [[ "$REQUIRE_CHECKS" != true ]]; then
    return 0
  fi

  echo ""
  echo "🧪  Ejecutando checks técnicos obligatorios..."
  echo "   Comando: $CHECK_CMD"

  if bash -lc "$CHECK_CMD"; then
    echo "✅  Checks técnicos OK."
    return 0
  fi

  echo "❌  Checks técnicos fallaron."
  return 1
}

run_claude() {
  local prompt="$1"
  [[ -x "$CLAUDE_BIN" ]] || return 1
  "$CLAUDE_BIN" --print "$prompt" 2>/dev/null || true
}

run_codex() {
  local prompt="$1"
  [[ -n "$CODEX_BIN" ]] || return 1

  local out_file
  out_file=$(mktemp)
  if ! printf "%s" "$prompt" | "$CODEX_BIN" exec --sandbox read-only --output-last-message "$out_file" - >/dev/null 2>&1; then
    rm -f "$out_file"
    return 1
  fi
  cat "$out_file"
  rm -f "$out_file"
}

REVIEW_CLAUDE_REPORT=""
REVIEW_CLAUDE_VERDICT=""
REVIEW_CODEX_REPORT=""
REVIEW_CODEX_VERDICT=""
REVIEW_FINAL_VERDICT=""

run_dual_review() {
  local base_prompt="$1"

  REVIEW_CLAUDE_REPORT=""
  REVIEW_CLAUDE_VERDICT=""
  REVIEW_CODEX_REPORT=""
  REVIEW_CODEX_VERDICT=""
  REVIEW_FINAL_VERDICT=""

  echo "🤖  Claude revisando..."
  REVIEW_CLAUDE_REPORT=$(run_claude "$base_prompt" || true)
  REVIEW_CLAUDE_VERDICT=$(extract_verdict "$REVIEW_CLAUDE_REPORT")

  if [[ -z "$REVIEW_CLAUDE_REPORT" ]]; then
    echo "⚠️  No se pudo obtener informe de Claude."
  else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "### Claude"
    echo "$REVIEW_CLAUDE_REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi

  local codex_prompt
  codex_prompt="Eres un segundo revisor técnico. Audita el análisis previo de Claude y valida si omitió algo.

$base_prompt

## Informe previo de Claude
$REVIEW_CLAUDE_REPORT

Valida expresamente el informe de Claude.
Responde con el mismo formato y cierra con APROBADO, REVISAR o BLOQUEADO en la última línea."

  echo ""
  echo "🤖  Codex auditando..."
  REVIEW_CODEX_REPORT=$(run_codex "$codex_prompt" || true)
  REVIEW_CODEX_VERDICT=$(extract_verdict "$REVIEW_CODEX_REPORT")

  if [[ -z "$REVIEW_CODEX_REPORT" ]]; then
    echo "⚠️  No se pudo obtener informe de Codex."
  else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "### Codex"
    echo "$REVIEW_CODEX_REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  fi

  if [[ "$REVIEW_CLAUDE_VERDICT" == "BLOQUEADO" || "$REVIEW_CODEX_VERDICT" == "BLOQUEADO" ]]; then
    REVIEW_FINAL_VERDICT="BLOQUEADO"
    return 0
  fi

  if [[ "$REVIEW_CLAUDE_VERDICT" == "REVISAR" || "$REVIEW_CODEX_VERDICT" == "REVISAR" ]]; then
    REVIEW_FINAL_VERDICT="REVISAR"
    return 0
  fi

  if [[ "$REVIEW_CLAUDE_VERDICT" == "APROBADO" && "$REVIEW_CODEX_VERDICT" == "APROBADO" ]]; then
    REVIEW_FINAL_VERDICT="APROBADO"
    return 0
  fi

  REVIEW_FINAL_VERDICT=""
  return 0
}

confirm_or_abort() {
  local message="$1"
  echo "$message"
  read -r answer < /dev/tty
  [[ "$answer" =~ ^[sS]$ ]]
}

handle_review_verdict_for_merge() {
  case "$REVIEW_FINAL_VERDICT" in
    APROBADO)
      if ! run_checks; then
        git merge --abort
        exit 5
      fi
      git commit --no-edit
      echo "✅  Merge confirmado."
      return 0
      ;;
    REVISAR)
      if [[ "$AUTO_MODE" == true ]]; then
        git merge --abort
        echo "⚠️  REVISAR detectado en modo --auto. Merge cancelado."
        exit 2
      fi
      if confirm_or_abort "⚠️  Hay observaciones. ¿Confirmar el merge? [s/N]"; then
        if ! run_checks; then
          git merge --abort
          exit 5
        fi
        git commit --no-edit
        echo "✅  Merge confirmado."
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      return 0
      ;;
    BLOQUEADO)
      git merge --abort
      echo "❌  BLOQUEADO — Merge cancelado. Revisa los cambios fuera de scope."
      exit 3
      ;;
    *)
      if [[ "$AUTO_MODE" == true ]]; then
        git merge --abort
        echo "⚠️  Veredicto no claro en modo --auto. Merge cancelado."
        exit 4
      fi
      if confirm_or_abort "⚠️  Veredicto no claro. ¿Confirmar el merge? [s/N]"; then
        if ! run_checks; then
          git merge --abort
          exit 5
        fi
        git commit --no-edit
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      return 0
      ;;
  esac
}

CLAUDE_BIN="${CLAUDE_BIN:-/Users/josemaria/.local/bin/claude}"
CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"
BRANCH=""
DRY_RUN=false
AUTO_MODE=false
REQUIRE_CHECKS=false
CHECK_CMD="${SMART_MERGE_CHECK_CMD:-python manage.py check && python manage.py test}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --auto)
      AUTO_MODE=true
      shift
      ;;
    --require-checks)
      REQUIRE_CHECKS=true
      shift
      ;;
    --check-cmd)
      [[ $# -lt 2 ]] && echo "❌  Falta valor para --check-cmd" && exit 1
      CHECK_CMD="$2"
      shift 2
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
      if [[ -z "$BRANCH" ]]; then
        BRANCH="$1"
      else
        echo "❌  Solo se admite una rama. Recibido extra: $1"
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$BRANCH" ]]; then
  usage
  exit 1
fi

if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
  echo "❌  Rama '$BRANCH' no existe."
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "❌  Tienes cambios sin commitear. Haz commit o stash antes de mergear."
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo ""
echo "📋  Leyendo contexto de la tarea desde '$BRANCH'..."

TASK_COMMITS=$(git log "$CURRENT_BRANCH".."$BRANCH" --pretty=format:"- %h %s%n  %b" --no-merges 2>/dev/null)
TASK_DESCRIPTION=$(git log "$CURRENT_BRANCH".."$BRANCH" --reverse --pretty=format:"%s%n%n%b" --no-merges 2>/dev/null | head -20)
FILES_IN_BRANCH=$(git diff --name-only "$CURRENT_BRANCH"..."$BRANCH" 2>/dev/null)
DIFF_BRANCH=$(capture "git diff '$CURRENT_BRANCH'...'$BRANCH' -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'")

if [[ -z "$TASK_DESCRIPTION" ]]; then
  echo "⚠️  No se encontraron commits nuevos en '$BRANCH' respecto a '$CURRENT_BRANCH'."
  exit 0
fi

echo "   Tarea base: $TASK_DESCRIPTION" | head -2
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "🔍  Modo dry-run: analizando sin mergear..."
  echo ""

  BASE_PROMPT="Eres un revisor de código. Analiza si este merge es seguro ANTES de ejecutarlo.

## Rama a mergear: $BRANCH → $CURRENT_BRANCH

## Fuente de verdad
commit

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Commits incluidos
$TASK_COMMITS

## Archivos que cambiarán
$FILES_IN_BRANCH

## Diff completo
\`\`\`diff
$DIFF_BRANCH
\`\`\`

Responde:
### ✅ Cambios que corresponden a la tarea
### ⚠️ Cambios no declarados o fuera de scope
### ❌ Riesgos o efectos secundarios detectados
### 📋 Veredicto
APROBADO, REVISAR o BLOQUEADO (una sola palabra al final)"

  run_dual_review "$BASE_PROMPT"

  if [[ "$AUTO_MODE" == true ]]; then
    case "$REVIEW_FINAL_VERDICT" in
      APROBADO) exit 0 ;;
      REVISAR) exit 2 ;;
      BLOQUEADO) exit 3 ;;
      *) exit 4 ;;
    esac
  fi
  exit 0
fi

echo "🔀  Intentando merge de '$BRANCH'..."
set +e
git merge --no-commit --no-ff "$BRANCH" 2>&1
MERGE_EXIT=$?
set -e

CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)

if [[ $MERGE_EXIT -eq 0 && -z "$CONFLICTS" ]]; then
  echo "✅  Merge sin conflictos. Verificando scope con doble revisión..."
  echo ""

  STAGED_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  BASE_PROMPT="El merge se aplicó sin conflictos. Verifica que los cambios son exactamente lo declarado.

## Fuente de verdad
commit

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Diff resultante del merge
\`\`\`diff
$STAGED_DIFF
\`\`\`

Responde:
### ✅ Cambios que corresponden
### ⚠️ Cambios no declarados
### ❌ Riesgos
### 📋 Veredicto (APROBADO / REVISAR / BLOQUEADO)"

  run_dual_review "$BASE_PROMPT"
  echo ""
  handle_review_verdict_for_merge
  exit 0
fi

if [[ -n "$CONFLICTS" ]]; then
  echo ""
  echo "⚡  Conflictos detectados en:"
  echo "$CONFLICTS" | sed 's/^/   • /'
  echo ""
  echo "🤖  Claude resolviendo conflictos según la tarea..."
  echo ""

  resolved_all=true

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue

    echo "   Resolviendo: $file"

    conflict_content=$(cat "$file")

    PROMPT="Eres un experto en resolución de conflictos git. Tu trabajo es resolver este conflicto manteniendo SOLAMENTE los cambios que corresponden a la tarea declarada.

## Fuente de verdad
commit

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Archivo con conflictos: $file
\`\`\`
$conflict_content
\`\`\`

## Reglas estrictas:
1. Donde hay <<<<<<< HEAD ... ======= ... >>>>>>> $BRANCH:
   - Si el cambio de $BRANCH corresponde a la tarea → usa la versión de $BRANCH
   - Si el cambio de $BRANCH NO corresponde a la tarea → usa la versión de HEAD (main)
   - Si ambas versiones son correctas y compatibles → combínalas
2. Elimina TODOS los marcadores de conflicto (<<<<<<<, =======, >>>>>>>)
3. Devuelve ÚNICAMENTE el contenido resuelto del archivo, sin explicaciones, sin markdown, sin bloques de código, sin nada más — solo el contenido exacto del archivo."

    resolved=$(run_claude "$PROMPT" || true)

    if [[ -z "$resolved" ]]; then
      echo "   ⚠️  No se pudo resolver '$file' automáticamente."
      resolved_all=false
      continue
    fi

    if echo "$resolved" | grep -qE '^(<<<<<<<|=======|>>>>>>>)'; then
      echo "   ⚠️  Claude dejó marcadores en '$file'. Requiere revisión manual."
      resolved_all=false
      continue
    fi

    echo "$resolved" > "$file"
    git add "$file"
    echo "   ✅  $file resuelto."

  done <<< "$CONFLICTS"

  echo ""

  if [[ "$resolved_all" == false ]]; then
    echo "⚠️  Algunos archivos requieren resolución manual."
    echo "   Archivos pendientes:"
    git diff --name-only --diff-filter=U | sed 's/^/   • /'
    echo ""
    echo "   Resuélvelos, haz 'git add <archivo>' y luego 'git commit'."
    exit 1
  fi

  echo "🔍  Verificación final del merge resuelto (doble revisión)..."
  FINAL_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  BASE_PROMPT="Verificación final post-resolución de conflictos.

## Fuente de verdad
commit

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Resultado final del merge (lo que se va a commitear)
\`\`\`diff
$FINAL_DIFF
\`\`\`

¿El resultado final contiene SOLO los cambios de la tarea? ¿Se excluyó correctamente lo que no correspondía?

Responde:
### ✅ Cambios incluidos correctamente
### ⚠️ Posibles residuos fuera de scope
### 📋 Veredicto (APROBADO / REVISAR / BLOQUEADO)"

  run_dual_review "$BASE_PROMPT"
  echo ""
  handle_review_verdict_for_merge
fi
