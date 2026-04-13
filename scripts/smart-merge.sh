#!/usr/bin/env bash
# smart-merge.sh: merge asistido por Claude
#
# Uso:
#   bash scripts/smart-merge.sh <rama>
#   bash scripts/smart-merge.sh <rama> --dry-run
#   bash scripts/smart-merge.sh <rama> --auto
#   bash scripts/smart-merge.sh <rama> --task-file scripts/backlog-task.md
#   bash scripts/smart-merge.sh <rama> --require-checks
#
# Notas:
#   - --task-file es opcional. Si se indica, se usa como fuente primaria
#     de alcance funcional (backlog).
#   - --require-checks ejecuta verificaciones técnicas antes de confirmar merge.
#   - En --auto solo mergea con veredicto APROBADO.

set -euo pipefail

capture() { { eval "$1" || true; } 2>/dev/null | head -c "${2:-12000}"; }
extract_verdict() { { echo "$1" | grep -oE 'APROBADO|REVISAR|BLOQUEADO' | tail -1; } || true; }

usage() {
  echo "Uso: bash scripts/smart-merge.sh <rama> [--dry-run] [--auto] [--task-file <ruta>|--task-file=<ruta>] [--require-checks] [--check-cmd <cmd>]"
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

CLAUDE=/Users/josemaria/.local/bin/claude
BRANCH=""
DRY_RUN=false
AUTO_MODE=false
TASK_FILE="${SMART_MERGE_TASK_FILE:-}"
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
    --task-file)
      [[ $# -lt 2 ]] && echo "❌  Falta ruta para --task-file" && exit 1
      TASK_FILE="$2"
      shift 2
      ;;
    --task-file=*)
      TASK_FILE="${1#*=}"
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

if [[ -n "$TASK_FILE" && ! -f "$TASK_FILE" ]]; then
  echo "❌  --task-file no existe: $TASK_FILE"
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

TASK_CONTEXT="No disponible"
TASK_SOURCE="commit"
if [[ -n "$TASK_FILE" ]]; then
  TASK_CONTEXT=$(head -c 6000 "$TASK_FILE" || true)
  if [[ -n "${TASK_CONTEXT//[[:space:]]/}" ]]; then
    TASK_SOURCE="backlog+commit"
  else
    TASK_CONTEXT="No disponible"
  fi
fi

echo "   Tarea base: $TASK_DESCRIPTION" | head -2
[[ "$TASK_SOURCE" == "backlog+commit" ]] && echo "   Backlog externo: $TASK_FILE"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "🔍  Modo dry-run: analizando sin mergear..."
  echo ""

  PROMPT="Eres un revisor de código. Analiza si este merge es seguro ANTES de ejecutarlo.

## Rama a mergear: $BRANCH → $CURRENT_BRANCH

## Fuente de verdad
$TASK_SOURCE

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Contexto de backlog (opcional)
$TASK_CONTEXT

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

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null || true)
  verdict=$(extract_verdict "$report")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$AUTO_MODE" == true ]]; then
    case "$verdict" in
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
  echo "✅  Merge sin conflictos. Verificando scope con Claude..."
  echo ""

  STAGED_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  PROMPT="El merge se aplicó sin conflictos. Verifica que los cambios son exactamente lo declarado.

## Fuente de verdad
$TASK_SOURCE

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Contexto de backlog (opcional)
$TASK_CONTEXT

## Diff resultante del merge
\`\`\`diff
$STAGED_DIFF
\`\`\`

Responde:
### ✅ Cambios que corresponden
### ⚠️ Cambios no declarados
### ❌ Riesgos
### 📋 Veredicto (APROBADO / REVISAR / BLOQUEADO)"

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null || true)
  verdict=$(extract_verdict "$report")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$verdict" in
    APROBADO)
      if ! run_checks; then
        git merge --abort
        exit 5
      fi
      git commit --no-edit
      echo "✅  Merge confirmado."
      ;;
    REVISAR)
      if [[ "$AUTO_MODE" == true ]]; then
        git merge --abort
        echo "⚠️  REVISAR detectado en modo --auto. Merge cancelado."
        exit 2
      fi
      echo "⚠️  Hay cambios menores no declarados. ¿Confirmar el merge? [s/N]"
      read -r answer < /dev/tty
      if [[ "$answer" =~ ^[sS]$ ]]; then
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
      echo "⚠️  Veredicto no claro. ¿Confirmar el merge? [s/N]"
      read -r answer < /dev/tty
      if [[ "$answer" =~ ^[sS]$ ]]; then
        if ! run_checks; then
          git merge --abort
          exit 5
        fi
        git commit --no-edit
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      ;;
  esac
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
$TASK_SOURCE

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Contexto de backlog (opcional)
$TASK_CONTEXT

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

    resolved=$("$CLAUDE" --print "$PROMPT" 2>/dev/null || true)

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

  echo "🔍  Verificación final del merge resuelto..."
  FINAL_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  PROMPT="Verificación final post-resolución de conflictos.

## Fuente de verdad
$TASK_SOURCE

## Tarea declarada (commit)
$TASK_DESCRIPTION

## Contexto de backlog (opcional)
$TASK_CONTEXT

## Resultado final del merge (lo que se va a commitear)
\`\`\`diff
$FINAL_DIFF
\`\`\`

¿El resultado final contiene SOLO los cambios de la tarea? ¿Se excluyó correctamente lo que no correspondía?

Responde:
### ✅ Cambios incluidos correctamente
### ⚠️ Posibles residuos fuera de scope
### 📋 Veredicto (APROBADO / REVISAR / BLOQUEADO)"

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null || true)
  verdict=$(extract_verdict "$report")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$verdict" in
    APROBADO|REVISAR)
      if [[ "$verdict" == "REVISAR" && "$AUTO_MODE" == true ]]; then
        git merge --abort
        echo "⚠️  REVISAR detectado en verificación final (modo --auto). Merge cancelado."
        exit 2
      fi
      if [[ "$verdict" == "REVISAR" ]]; then
        echo "⚠️  Hay observaciones. ¿Confirmar igualmente? [s/N]"
        read -r answer < /dev/tty
        if [[ ! "$answer" =~ ^[sS]$ ]]; then
          git merge --abort
          echo "↩️   Merge cancelado."
          exit 1
        fi
      fi
      if ! run_checks; then
        git merge --abort
        exit 5
      fi
      git commit --no-edit
      echo "✅  Merge con resolución inteligente confirmado."
      ;;
    BLOQUEADO)
      git merge --abort
      echo "❌  BLOQUEADO — La resolución introdujo cambios fuera de scope. Merge cancelado."
      exit 3
      ;;
    *)
      if [[ "$AUTO_MODE" == true ]]; then
        git merge --abort
        echo "⚠️  Veredicto no claro en verificación final (modo --auto). Merge cancelado."
        exit 4
      fi
      echo "⚠️  Veredicto no claro. ¿Confirmar el merge? [s/N]"
      read -r answer < /dev/tty
      if [[ "$answer" =~ ^[sS]$ ]]; then
        if ! run_checks; then
          git merge --abort
          exit 5
        fi
        git commit --no-edit
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      ;;
  esac
fi
