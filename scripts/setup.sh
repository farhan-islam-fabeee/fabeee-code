#!/usr/bin/env bash
# Set up pi with pi-agent-kit for the project in the current directory.
#
#   cd /path/to/your-project
#   /path/to/pi-agent-kit/scripts/setup.sh [--dry-run]
#
# Installs pi if missing, configures a local server, a cloud provider or both, installs the
# kit (skills, global AGENTS.md, quality gate, MCP servers, packages you pick) and prepares
# the project (.pi/check, starter AGENTS.md, .gitignore). Every pi config file it changes is
# backed up first (<file>.backup-<timestamp>). --dry-run asks the same questions but writes nothing.
set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$(pwd)"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_KIT_STAMP="$(date +%Y%m%d-%H%M%S)"
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done
export DRY_RUN PI_KIT_STAMP PI_KIT_DRY_RUN="$DRY_RUN"

# ---------- ui ----------
if [[ -t 1 ]]; then B=$'\033[1m' DIM=$'\033[2m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'
else B="" DIM="" G="" Y="" R="" N=""; fi
step() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
info() { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
run()  { if [[ $DRY_RUN == 1 ]]; then printf '%s+ %s%s\n' "$DIM" "$*" "$N"; else "$@"; fi; }

ask() { # ask VAR "Prompt" [default]
  local __var=$1 __prompt=$2 __def=${3:-} __ans=""
  if [[ -n $__def ]]; then read -r -p "$__prompt [$__def]: " __ans || die "no input"
  else read -r -p "$__prompt: " __ans || die "no input"; fi
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

ask_secret() { # ask_secret VAR "Prompt"
  local __var=$1 __ans=""
  read -r -s -p "$2: " __ans || die "no input"
  printf '\n'
  printf -v "$__var" '%s' "$__ans"
}

confirm() { # confirm "Question" [y|n]
  local def=${2:-y} hint="[Y/n]" ans=""
  [[ $def == n ]] && hint="[y/N]"
  read -r -p "$1 $hint " ans || die "no input"
  case "${ans:-$def}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

choose() { # choose VAR "Question" option... -> VAR is the 1-based index
  local __var=$1 __q=$2 i=1 o ans=""
  shift 2
  printf '%s\n' "$__q"
  for o in "$@"; do printf '  %d) %s\n' "$i" "$o"; i=$((i + 1)); done
  while true; do
    read -r -p "Choose 1-$#: " ans || die "no input"
    if [[ $ans =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le $# ]; then break; fi
    warn "Enter a number from 1 to $#."
  done
  printf -v "$__var" '%s' "$ans"
}

upper_env() { printf '%s_API_KEY' "$(printf '%s' "$1" | tr '[:lower:].-' '[:upper:]__')"; }

find_node() {
  NODE=$(command -v node 2>/dev/null || true)
  local bundled="${XDG_DATA_HOME:-$HOME/.local/share}/pi-node/current/bin"
  if [[ -z $NODE && -x "$bundled/node" ]]; then NODE="$bundled/node"; PATH="$bundled:$PATH"; fi
  [[ -n $NODE ]]
}
cfg() { "$NODE" "$KIT/scripts/lib/pi-config.mjs" "$@"; }

# ---------- api keys ----------
# pick_key_storage ID ENV_VAR ALLOW_PLAIN ALLOW_LOGIN
# Sets KEY_REF (models.json "apiKey" value, empty = leave pi's default lookup alone),
# KEY_VALUE (in memory only, used to list models during setup) and NEED_LOGIN.
pick_key_storage() {
  local id=$1 envvar=$2 allow_plain=$3 allow_login=$4 c svc="pi-agent-kit:$1"
  local labels=() kinds=()
  if [[ $allow_login == 1 ]]; then labels+=("Log in inside pi later with /login $id (pi stores the key itself)"); kinds+=(login); fi
  if [[ $(uname) == Darwin ]]; then labels+=("macOS Keychain (pi reads it with the security command on each request)"); kinds+=(keychain); fi
  labels+=("Environment variable \$$envvar (you export it in your shell profile)"); kinds+=(env)
  if [[ $allow_plain == 1 ]]; then labels+=("Plain text in models.json (only for a local server's key)"); kinds+=(plain); fi
  choose c "Where should the API key for $id live?" "${labels[@]}"
  KEY_REF="" KEY_VALUE="" NEED_LOGIN=0
  case "${kinds[$((c - 1))]}" in
    login) NEED_LOGIN=1 ;;
    keychain)
      if [[ $DRY_RUN == 1 ]]; then
        ask_secret KEY_VALUE "API key for $id (dry run: kept in memory only)"
      else
        info "macOS will ask for the key twice (it is typed into the security tool, not this script)."
        security add-generic-password -U -a pi-agent-kit -s "$svc" -w || die "Keychain write failed."
        KEY_VALUE=$(security find-generic-password -a pi-agent-kit -s "$svc" -w)
      fi
      KEY_REF="!security find-generic-password -a pi-agent-kit -s $svc -w"
      [[ $DRY_RUN == 1 ]] || ok "Key stored in the login keychain as \"$svc\"." ;;
    env)
      if [[ -n ${!envvar:-} ]]; then KEY_VALUE=${!envvar}; ok "\$$envvar is set in this shell."
      else
        warn "\$$envvar is not set. Add this to your shell profile: export $envvar=..."
        ask_secret KEY_VALUE "Paste the key to test it now (kept in memory only, Enter to skip)"
      fi
      KEY_REF="\${$envvar}" ;;
    plain)
      ask_secret KEY_VALUE "API key"
      KEY_REF=$KEY_VALUE ;;
  esac
}

# pick_model VAR "candidates (newline separated)"
pick_model() {
  local __var=$1 list=$2 filter n
  n=$(printf '%s\n' "$list" | grep -c . || true)
  if [ "$n" -gt 30 ]; then
    ask filter "$n models available. Filter by name (e.g. qwen, glm, kimi, deepseek)" ""
    list=$(printf '%s\n' "$list" | grep -i -- "$filter" | head -n 30 || true)
    n=$(printf '%s\n' "$list" | grep -c . || true)
  fi
  if [ "$n" -eq 0 ]; then ask "$__var" "Model ID" ""; return; fi
  local arr=() line idx
  while IFS= read -r line; do [[ -n $line ]] && arr+=("$line"); done <<< "$list"
  arr+=("Type a model ID instead")
  choose idx "Which model?" "${arr[@]}"
  if [ "$idx" -eq "${#arr[@]}" ]; then ask "$__var" "Model ID" ""; else printf -v "$__var" '%s' "${arr[$((idx - 1))]}"; fi
}

# ---------- state ----------
USE_LOCAL=0 USE_CLOUD=0
LOCAL_PROVIDER="" LOCAL_MODEL="" LOCAL_URL="" LOCAL_CTX="" LOCAL_BACKEND=""
CLOUD_PROVIDER="" CLOUD_MODEL="" CLOUD_LOGIN=0
INSTALLED_PKGS=""

# ---------- 1. project ----------
step "1/7 Project"
info "Project folder: $PROJECT"
[[ "$PROJECT" == "$HOME" || "$PROJECT" == "/" ]] && die "Run this inside a project folder, not $PROJECT."
[[ "$PROJECT" == "$KIT" ]] && warn "This is the kit's own folder; the project steps will apply to it."
[[ $DRY_RUN == 1 ]] && warn "Dry run: nothing will be written or installed."
confirm "Set up pi for this folder?" y || exit 0
command -v curl >/dev/null 2>&1 || die "curl is required."

# ---------- 2. pi ----------
step "2/7 pi"
PATH="$PI_DIR/bin:$PATH"
if command -v pi >/dev/null 2>&1; then
  ok "pi $(pi --version 2>/dev/null) at $(command -v pi)"
else
  warn "pi is not installed."
  choose how "How should pi be installed?" \
    "Official installer: curl -fsSL https://pi.dev/install.sh | sh (recommended, brings its own Node)" \
    "npm: npm install -g --ignore-scripts @earendil-works/pi-coding-agent (needs Node 22.19+)" \
    "Cancel"
  case $how in
    1) run sh -c 'curl -fsSL https://pi.dev/install.sh | sh' ;;
    2) find_node || die "Node.js not found. Install Node 22.19+ or use the official installer."
       nv=$("$NODE" -p 'process.versions.node')
       "$NODE" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=19)?0:1)' \
         || die "Node $nv is too old; pi needs 22.19+."
       run npm install -g --ignore-scripts @earendil-works/pi-coding-agent ;;
    3) exit 0 ;;
  esac
  hash -r
  if [[ $DRY_RUN == 0 ]]; then
    command -v pi >/dev/null 2>&1 || die "pi is still not on PATH. Open a new terminal and run this script again."
    ok "pi $(pi --version) installed"
  fi
fi
HAVE_PI=0; command -v pi >/dev/null 2>&1 && HAVE_PI=1
if [[ $HAVE_PI == 1 ]]; then
  major=$(pi --version 2>/dev/null | cut -d. -f1)
  if [[ $major =~ ^[0-9]+$ ]] && [ "$major" -lt 1 ]; then
    warn "pi $(pi --version) is older than 1.0; this kit relies on pi 1.x (built-in MCP, codemode)."
    confirm "Update pi now (pi update self)?" y && run pi update self
  fi
fi
find_node || die "Node.js not found. The pi installer normally provides it; re-run the installer."

# ---------- 3. models ----------
step "3/7 Models"
choose mode "Which models will you use?" \
  "Local server only (oMLX, Ollama, LM Studio, llama.cpp, other)" \
  "Cloud provider only (OpenRouter, DeepSeek, Z.ai, Kimi, any OpenAI-compatible API)" \
  "Both: local by default, cloud for hard tasks"
case $mode in 1) USE_LOCAL=1 ;; 2) USE_CLOUD=1 ;; 3) USE_LOCAL=1; USE_CLOUD=1 ;; esac

setup_local() {
  local b url needs_key="n" ids="" ctx_def=32768 ctx maxout reasoning images model
  info ""
  choose b "Which local server?" "oMLX" "Ollama" "LM Studio" "llama.cpp router (llama-server)" "Other OpenAI-compatible server"
  case $b in
    1) LOCAL_PROVIDER=omlx url=http://127.0.0.1:8000/v1 needs_key=y LOCAL_BACKEND=omlx ;;
    2) LOCAL_PROVIDER=ollama url=http://127.0.0.1:11434/v1 LOCAL_BACKEND=ollama ;;
    3) LOCAL_PROVIDER=lmstudio url=http://127.0.0.1:1234/v1 LOCAL_BACKEND=lmstudio ;;
    4) LOCAL_BACKEND=llamacpp
       info "pi has a built-in llama.cpp provider. Start the router without a model, for example:"
       info "  llama-server --models-dir ~/models --no-models-autoload --jinja --host 127.0.0.1 --port 8080 -ngl 999 -c 32768"
       ask LOCAL_URL "Router URL" "http://127.0.0.1:8080"
       if curl -fsS -m 3 "$LOCAL_URL/health" >/dev/null 2>&1; then ok "Router is answering."; else warn "No answer from $LOCAL_URL/health (start it before using pi)."; fi
       [[ $LOCAL_URL != "http://127.0.0.1:8080" ]] && warn "Add to your shell profile: export LLAMA_BASE_URL=$LOCAL_URL"
       info "In pi: run /llama to load a model, then /model to select it."
       LOCAL_PROVIDER=llama.cpp
       return ;;
    5) ask LOCAL_PROVIDER "Provider ID for pi (letters, digits, -)" "local"
       url=http://127.0.0.1:8080/v1 LOCAL_BACKEND=other ;;
  esac
  ask LOCAL_URL "Base URL (OpenAI-compatible, usually ending in /v1)" "$url"

  if cfg has-provider "$PI_DIR/models.json" "$LOCAL_PROVIDER" 2>/dev/null; then
    warn "models.json already has a provider \"$LOCAL_PROVIDER\"; its settings for the chosen model will be replaced (other models kept)."
  fi
  if confirm "Does the server require an API key?" "$needs_key"; then
    pick_key_storage "$LOCAL_PROVIDER" "$(upper_env "$LOCAL_PROVIDER")" 1 0
  else
    KEY_REF=$LOCAL_PROVIDER KEY_VALUE=""   # dummy key: makes the provider available, the server ignores it
  fi

  local r
  while true; do
    info "Asking $LOCAL_URL/models ..."
    if ids=$(PI_KIT_KEY="$KEY_VALUE" cfg list-models "$LOCAL_URL" 2>/dev/null); then pick_model model "$ids"; break; fi
    warn "Couldn't list models (is the server running, and is the key right?)."
    choose r "What now?" "Retry (start the server first)" "Type the model ID"
    if [ "$r" -eq 2 ]; then ask model "Model ID as the server names it" ""; break; fi
  done
  [[ -n $model ]] || die "A model ID is required."
  LOCAL_MODEL="$LOCAL_PROVIDER/$model"

  if [[ $LOCAL_BACKEND == omlx ]] && v=$(cfg json-get "$HOME/.omlx/settings.json" sampling.max_context_window 2>/dev/null); then
    ctx_def=$v; info "oMLX's configured context window is $v (sampling.max_context_window)."
  fi
  warn "Use the context the server actually serves, not the model's advertised maximum, or compaction will never trigger in time."
  ask ctx "Context window in tokens" "$ctx_def"
  [[ $ctx =~ ^[0-9]+$ ]] || die "Context window must be a number."
  maxout=$((ctx / 4)); [ "$maxout" -gt 8192 ] && maxout=8192
  ask maxout "Max output tokens per reply" "$maxout"
  reasoning=false; confirm "Does the model have a thinking (reasoning) mode?" y && reasoning=true
  images=0; confirm "Does it accept images?" n && images=1
  LOCAL_CTX=$ctx

  PK_ID=$LOCAL_PROVIDER PK_BASE_URL=$LOCAL_URL PK_API_KEY=$KEY_REF PK_MODEL_ID=$model \
  PK_MODEL_NAME="$model (local)" PK_CONTEXT=$ctx PK_MAX_TOKENS=$maxout PK_REASONING=$reasoning \
  PK_IMAGES=$images PK_CACHE_TTL=3600 cfg upsert-provider "$PI_DIR/models.json"
  ok "Local model: $LOCAL_MODEL"
}

setup_cloud() {
  local c sub envvar ids="" model custom=0 url ctx maxout reasoning cost ttl
  info ""
  warn "Before you continue: use a separate API key with a spending cap, and check the provider's data/training policy for work code."
  choose c "Which cloud provider?" \
    "OpenRouter (one key, every model)" "DeepSeek" "Z.ai (GLM)" "Moonshot (Kimi)" \
    "Another built-in provider" "Custom OpenAI-compatible endpoint"
  case $c in
    1) CLOUD_PROVIDER=openrouter envvar=OPENROUTER_API_KEY ;;
    2) CLOUD_PROVIDER=deepseek envvar=DEEPSEEK_API_KEY ;;
    3) CLOUD_PROVIDER=zai envvar=ZAI_API_KEY ;;
    4) CLOUD_PROVIDER=moonshotai envvar=MOONSHOT_API_KEY ;;
    5) choose sub "Which one?" "OpenAI" "Anthropic" "Google Gemini" "Groq" "Fireworks" "Together AI" "Mistral" "xAI" \
         "Cerebras" "Vercel AI Gateway" "Kimi For Coding (subscription)" "Qwen Token Plan (subscription)"
       local pids=(openai anthropic google groq fireworks together mistral xai cerebras vercel-ai-gateway kimi-coding qwen-token-plan)
       local envs=(OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GROQ_API_KEY FIREWORKS_API_KEY TOGETHER_API_KEY MISTRAL_API_KEY XAI_API_KEY CEREBRAS_API_KEY AI_GATEWAY_API_KEY KIMI_API_KEY QWEN_TOKEN_PLAN_API_KEY)
       CLOUD_PROVIDER=${pids[$((sub - 1))]} envvar=${envs[$((sub - 1))]} ;;
    6) custom=1
       ask CLOUD_PROVIDER "Provider ID for pi (letters, digits, -)" "mycloud"
       envvar=$(upper_env "$CLOUD_PROVIDER") ;;
  esac

  if [[ $custom == 0 ]]; then
    pick_key_storage "$CLOUD_PROVIDER" "$envvar" 0 1
    CLOUD_LOGIN=$NEED_LOGIN
    # Keychain needs an apiKey override; env var / login use pi's built-in lookup.
    if [[ $KEY_REF == "!security"* ]]; then
      PK_ID=$CLOUD_PROVIDER PK_API_KEY=$KEY_REF cfg upsert-provider "$PI_DIR/models.json"
    fi
    if [[ $HAVE_PI == 1 && -n $KEY_VALUE ]]; then
      info "Asking pi which $CLOUD_PROVIDER models this key can use ..."
      ids=$(env "$envvar=$KEY_VALUE" pi --no-approve --list-models "$CLOUD_PROVIDER" 2>/dev/null | awk -v p="$CLOUD_PROVIDER" 'NR > 1 && $1 == p { print $2 }' || true)
    fi
    if [[ -n $ids ]]; then pick_model model "$ids"
    else
      info "Can't list models yet. After logging in, 'pi --list-models $CLOUD_PROVIDER' shows the IDs."
      ask model "Model ID (Enter to pick later with /model)" ""
    fi
  else
    ask url "Base URL (ending in /v1)" "https://api.example.com/v1"
    pick_key_storage "$CLOUD_PROVIDER" "$envvar" 0 0
    if ids=$(PI_KIT_KEY="$KEY_VALUE" cfg list-models "$url" 2>/dev/null); then pick_model model "$ids"
    else warn "Couldn't list models from $url."; ask model "Model ID" ""; fi
    [[ -n $model ]] || die "A model ID is required for a custom provider."
    ask ctx "Context window in tokens" "131072"
    ask maxout "Max output tokens per reply" "16384"
    reasoning=false; confirm "Does the model have a thinking (reasoning) mode?" y && reasoning=true
    info "Prices in USD per million tokens, from the provider's pricing page (pi uses them for cost totals)."
    local pin pout pcr pcw
    ask pin "  input" "0"; ask pout "  output" "0"; ask pcr "  cache read" "0"; ask pcw "  cache write" "0"
    ask ttl "Prompt cache lifetime in seconds (0 if the provider doesn't cache)" "300"
    PK_ID=$CLOUD_PROVIDER PK_BASE_URL=$url PK_API_KEY=$KEY_REF PK_MODEL_ID=$model PK_CONTEXT=$ctx \
    PK_MAX_TOKENS=$maxout PK_REASONING=$reasoning PK_COST="$pin,$pout,$pcr,$pcw" PK_CACHE_TTL=$ttl \
    cfg upsert-provider "$PI_DIR/models.json"
  fi
  [[ -n $model ]] && CLOUD_MODEL="$CLOUD_PROVIDER/$model"
  ok "Cloud provider: $CLOUD_PROVIDER${CLOUD_MODEL:+ (model $CLOUD_MODEL)}"
}

[[ $USE_LOCAL == 1 ]] && setup_local
[[ $USE_CLOUD == 1 ]] && setup_cloud

# ---------- 4. settings ----------
step "4/7 pi settings"
DEFAULT_MODEL="" PROJECT_DEFAULT=""
if [[ $USE_LOCAL == 1 && $USE_CLOUD == 1 ]]; then
  choose d "Which model should start by default?" \
    "Local everywhere; cloud on demand (pi --model ...)" \
    "Local by default, but cloud by default in this project" \
    "Cloud everywhere"
  case $d in
    1) DEFAULT_MODEL=$LOCAL_MODEL ;;
    2) DEFAULT_MODEL=$LOCAL_MODEL PROJECT_DEFAULT=$CLOUD_MODEL ;;
    3) DEFAULT_MODEL=$CLOUD_MODEL ;;
  esac
elif [[ $USE_LOCAL == 1 ]]; then DEFAULT_MODEL=$LOCAL_MODEL
else DEFAULT_MODEL=$CLOUD_MODEL; fi
ENABLED=""
[[ -n $LOCAL_MODEL && -n $CLOUD_MODEL ]] && ENABLED="$LOCAL_MODEL,$CLOUD_MODEL"

export PK_DEFAULT=$DEFAULT_MODEL PK_LOCAL_MODEL=$LOCAL_MODEL PK_LOCAL_CTX=$LOCAL_CTX PK_ENABLED_MODELS=$ENABLED
info "Changes to $PI_DIR/settings.json:"
cfg apply-settings "$PI_DIR/settings.json" preview
info "${DIM}(low default thinking, codemode on, compaction sized to the local window, cache-miss notices on while tuning)${N}"
if confirm "Apply these settings?" y; then cfg apply-settings "$PI_DIR/settings.json" write; else warn "Settings left unchanged."; fi
if [[ -n $PROJECT_DEFAULT ]]; then
  PK_PROJECT=1 PK_DEFAULT=$PROJECT_DEFAULT cfg apply-settings "$PROJECT/.pi/settings.json" write
  info "pi reads .pi/settings.json only after you trust the project (it asks on first run)."
fi

if [[ -n $LOCAL_MODEL || -n $CLOUD_MODEL ]] && confirm "Add shell aliases (pil = local, pic = cloud)?" n; then
  rc="$HOME/.bashrc"; [[ ${SHELL:-} == */zsh ]] && rc="$HOME/.zshrc"
  block="# >>> pi-agent-kit >>>"$'\n'
  [[ -n $LOCAL_MODEL ]] && block+="alias pil='pi --model $LOCAL_MODEL'"$'\n'
  [[ -n $CLOUD_MODEL ]] && block+="alias pic='pi --model $CLOUD_MODEL:low'"$'\n'
  block+="# <<< pi-agent-kit <<<"
  if [[ $DRY_RUN == 1 ]]; then printf '%s+ write to %s:%s\n%s\n' "$DIM" "$rc" "$N" "$block"
  else
    [[ -f $rc ]] && sed -i.backup-"$PI_KIT_STAMP" '/^# >>> pi-agent-kit >>>$/,/^# <<< pi-agent-kit <<<$/d' "$rc"
    printf '\n%s\n' "$block" >> "$rc"
    ok "Aliases added to $rc (open a new terminal to use them)."
  fi
fi

# ---------- 5. kit ----------
step "5/7 Skills, rules, quality gate"
"$KIT/scripts/install.sh" skills
if confirm "Install the quality-gate extension (re-runs .pi/check when the agent finishes)?" y; then
  "$KIT/scripts/install.sh" extension
fi

info ""
info "MCP servers:"
servers=()
if confirm "  Probe: local code search that returns whole functions (runs on your machine)?" y; then
  servers+=(probe)
  if ! command -v probe >/dev/null 2>&1; then
    if confirm "  Probe isn't installed. Run npm install -g @probelabs/probe@latest?" y; then run npm install -g @probelabs/probe@latest
    else warn "  Install it later, or pi will report probe as disconnected."; fi
  fi
fi
confirm "  Context7: up-to-date library docs (remote; sends library names and queries to context7.com)?" y && servers+=(context7)
if [ "${#servers[@]}" -gt 0 ]; then cfg merge-mcp "$PI_DIR/mcp.json" "$KIT/config/mcp.json" "${servers[@]}"; fi

# ---------- 6. packages ----------
step "6/7 pi packages"
warn "Packages run code with your permissions. Review them at https://pi.dev/packages/<name> first."
offer_tier() { # offer_tier TIER DEFAULT "description"
  if [[ $HAVE_PI == 0 ]]; then warn "Skipping $1: pi isn't installed (dry run)."; return; fi
  if confirm "$3" "$2"; then "$KIT/scripts/install.sh" packages "$1"; INSTALLED_PKGS+=" $1"; fi
}
offer_tier core y "core: pi-lens (diagnostics), cc-safety-net, rpiv-todo-lean, pi-token-killer?"
offer_tier tokens y "tokens: pi-vcc (no-LLM compaction), pi-prefix-stabilizer, pi-caveman?"
offer_tier ondemand y "on demand: plan mode, /simplify, subagents?"
if [[ $USE_CLOUD == 1 ]]; then
  [[ $USE_LOCAL == 1 ]] && info "${DIM}(pi-context-diet trims stale output after idle gaps; on the local model that costs one re-prefill per gap)${N}"
  offer_tier cloud y "cloud: pi-cache-optimizer, pi-context-diet?"
fi
offer_tier tuning n "tuning: pi-context-view (see what fills the context; remove after tuning)?"

# ---------- 7. project ----------
step "7/7 Project files"
cd "$PROJECT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  confirm "No git repo here. Initialize one (the quality gate and /simplify use git diff)?" y && run git init -q
fi
run mkdir -p .pi

suggest=$(cfg detect-check "$PROJECT")
if [[ -s .pi/check ]] && ! confirm "Replace the existing .pi/check ($(head -n 1 .pi/check))?" n; then
  check=$(head -n 1 .pi/check)
else
  ask check "Fast check command for the quality gate (Enter to skip)" "$suggest"
  if [[ -n $check ]]; then
    if [[ $DRY_RUN == 1 ]]; then run "write .pi/check: $check"; else printf '%s\n' "$check" > .pi/check; ok ".pi/check: $check"; fi
  fi
fi

if [[ ! -e AGENTS.md && ! -e CLAUDE.md ]]; then
  if confirm "Create a starter AGENTS.md for this project (short, English, with detected commands)?" y; then
    if [[ $DRY_RUN == 1 ]]; then run "write AGENTS.md:"; cfg agents-template "$PROJECT" "${check:-}"
    else cfg agents-template "$PROJECT" "${check:-}" > AGENTS.md; ok "AGENTS.md created. Fill in the TODO lines."; fi
  fi
else
  ok "Project already has an AGENTS.md or CLAUDE.md; left as is."
fi

if ! grep -qx '.pi/handoff.md' .gitignore 2>/dev/null; then
  if [[ $DRY_RUN == 1 ]]; then run "append .pi/handoff.md to .gitignore"
  else printf '.pi/handoff.md\n' >> .gitignore; ok ".gitignore: added .pi/handoff.md"; fi
fi

# ---------- summary ----------
step "Checks"
if [[ $HAVE_PI == 1 && $DRY_RUN == 0 ]]; then
  for p in $LOCAL_PROVIDER $CLOUD_PROVIDER; do
    [[ $p == llama.cpp ]] && continue
    if out=$(pi auth check --provider "$p" --json 2>/dev/null) && [[ $out == *'"ready"'* ]]; then ok "$p: credentials ready"
    elif [[ $p == "$CLOUD_PROVIDER" && $CLOUD_LOGIN == 1 ]]; then warn "$p: not logged in yet (run /login $p in pi)"
    else warn "$p: not ready ($out)"; fi
  done
  if [[ -n $LOCAL_URL && $LOCAL_BACKEND != llamacpp ]]; then
    if curl -s -m 3 -o /dev/null "$LOCAL_URL/models"; then ok "local server answers at $LOCAL_URL"; else warn "local server not answering at $LOCAL_URL"; fi
  fi
fi

step "Next steps"
n=1
next() { info "$n. $*"; n=$((n + 1)); }
next "cd \"$PROJECT\" && pi        (answer yes to the project trust prompt)"
[[ $CLOUD_LOGIN == 1 ]] && next "/login $CLOUD_PROVIDER         store the cloud key in pi"
[[ -z $DEFAULT_MODEL ]] && next "/model                       pick a default model"
next "/skill:project-map           writes .pi/MAP.md so later sessions skip re-exploring"
next "pi mcp list                  confirms the MCP servers connect"
[[ $INSTALLED_PKGS == *core* ]] && next "/rtk settings                turn OFF the file-read filter (pi's edit needs exact text)"
[[ $INSTALLED_PKGS == *tokens* ]] && next "/caveman lite                terse replies; the stronger levels can hurt clarity"
if [[ $LOCAL_BACKEND == omlx ]]; then
  info ""
  info "oMLX dashboard: turn on chunked prefill and the prefill memory guard, set max concurrent requests to 2,"
  info "and keep the SSD cache on (docs/gameplan.md, Phase 0.3)."
fi
info ""
info "Measure before adding more: docs/gameplan.md, Phase 6."
[[ $DRY_RUN == 1 ]] && warn "Dry run finished; nothing was changed."
exit 0
