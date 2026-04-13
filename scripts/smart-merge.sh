#!/usr/bin/env bash
# smart-merge.sh: merge asistido por Claude
#
# Uso:
#   bash scripts/smart-merge.sh <rama>                      # merge normal con resolución inteligente
#   bash scripts/smart-merge.sh <rama> --dry-run           # analiza sin tocar nada
#   bash scripts/smart-merge.sh <rama> --auto              # sin prompts; bloquea en REVISAR/BLOQUEADO
#   bash scripts/smart-merge.sh <rama> --dry-run --auto    # devuelve código según veredicto
#
# Qué hace:
#   1. Lee la descripción de la tarea del primer commit de <rama> (intención original)
#   2. Intenta el merge (--no-commit para poder inspeccionar)
#   3. Si hay conflictos, Claude resuelve cada archivo usando SOLO
#      los cambios que corresponden a la tarea declarada
#   4. Si no hay conflictos, Claude verifica igualmente que el merge
#      no introdujo cambios fuera de scope antes de confirmarlo

set -euo pipefail
# Desactivar pipefail puntualmente en capturas con head/tail para evitar SIGPIPE
capture() { { eval "$1" || true; } 2>/dev/null | head -c "${2:-12000}"; }
usage() {
  echo "Uso: bash scripts/smart-merge.sh <rama> [--dry-run] [--auto]"
}

CLAUDE=/Users/josemaria/.local/bin/claude
BRANCH=""
DRY_RUN=false
AUTO_MODE=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    --auto)
      AUTO_MODE=true
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
      if [[ -z "$BRANCH" ]]; then
        BRANCH="$arg"
      else
        echo "❌  Solo se admite una rama. Recibido extra: $arg"
        usage
        exit 1
      fi
      ;;
  esac
done

# ── Validaciones ──────────────────────────────────────────────────────────────
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

# ── Leer contexto de la tarea desde la rama a mergear ─────────────────────────
echo ""
echo "📋  Leyendo contexto de la tarea desde '$BRANCH'..."

# Commits de la rama que no están en la rama actual
TASK_COMMITS=$(git log "$CURRENT_BRANCH".."$BRANCH" --pretty=format:"- %h %s%n  %b" --no-merges 2>/dev/null)
# Tarea = primer commit de la rama (el que describe la intención original)
# Los commits posteriores son refinamientos/fixes de esa misma tarea
TASK_DESCRIPTION=$(git log "$CURRENT_BRANCH".."$BRANCH" --reverse --pretty=format:"%s%n%n%b" --no-merges 2>/dev/null | head -20)
FILES_IN_BRANCH=$(git diff --name-only "$CURRENT_BRANCH"..."$BRANCH" 2>/dev/null)
DIFF_BRANCH=$(capture "git diff '$CURRENT_BRANCH'...'$BRANCH' -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'")

if [[ -z "$TASK_DESCRIPTION" ]]; then
  echo "⚠️  No se encontraron commits nuevos en '$BRANCH' respecto a '$CURRENT_BRANCH'."
  exit 0
fi

echo "   Tarea: $TASK_DESCRIPTION" | head -2
echo ""

# ── Modo dry-run: solo analiza, no toca nada ──────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  echo "🔍  Modo dry-run: analizando sin mergear..."
  echo ""

  PROMPT="Eres un revisor de código. Analiza si este merge es seguro ANTES de ejecutarlo.

## Rama a mergear: $BRANCH → $CURRENT_BRANCH

## Tarea declarada (commit message)
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

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null || true)
  verdict=$({ echo "$report" | grep -oE 'APROBADO|REVISAR|BLOQUEADO' | tail -1; } || true)

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

# ── Intentar el merge ─────────────────────────────────────────────────────────
echo "🔀  Intentando merge de '$BRANCH'..."
set +e
git merge --no-commit --no-ff "$BRANCH" 2>&1
MERGE_EXIT=$?
set -e

CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)

# ── Sin conflictos: verificar scope y confirmar ───────────────────────────────
if [[ $MERGE_EXIT -eq 0 && -z "$CONFLICTS" ]]; then
  echo "✅  Merge sin conflictos. Verificando scope con Claude..."
  echo ""

  STAGED_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  PROMPT="El merge se aplicó sin conflictos. Verifica que los cambios son exactamente lo declarado.

## Tarea declarada
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

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null)
  verdict=$({ echo "$report" | grep -oE 'APROBADO|REVISAR|BLOQUEADO' | tail -1; } || true)

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$report"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$verdict" in
    APROBADO)
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
        git commit --no-edit
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      ;;
  esac
  exit 0
fi

# ── Con conflictos: resolución inteligente por archivo ────────────────────────
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

## Tarea declarada (lo único que debe entrar en el merge)
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

    resolved=$("$CLAUDE" --print "$PROMPT" 2>/dev/null)

    if [[ $? -ne 0 || -z "$resolved" ]]; then
      echo "   ⚠️  No se pudo resolver '$file' automáticamente."
      resolved_all=false
      continue
    fi

    # Verificar que no quedaron marcadores de conflicto
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

  # Verificación final del resultado completo
  echo "🔍  Verificación final del merge resuelto..."
  FINAL_DIFF=$(capture "git diff --cached -- . ':(exclude)package-lock.json' ':(exclude)yarn.lock' ':(exclude)*.lock'" 10000)

  PROMPT="Verificación final post-resolución de conflictos.

## Tarea declarada
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

  report=$("$CLAUDE" --print "$PROMPT" 2>/dev/null)
  verdict=$({ echo "$report" | grep -oE 'APROBADO|REVISAR|BLOQUEADO' | tail -1; } || true)

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
      [[ "$verdict" == "REVISAR" ]] && echo "⚠️  Hay observaciones. ¿Confirmar igualmente? [s/N]" && read -r answer < /dev/tty && [[ ! "$answer" =~ ^[sS]$ ]] && git merge --abort && echo "↩️   Merge cancelado." && exit 1
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
        git commit --no-edit
      else
        git merge --abort
        echo "↩️   Merge cancelado."
      fi
      ;;
  esac
fi
