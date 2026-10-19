#!/usr/bin/env bash
# Set up pi with pi-agent-kit for the project in the current directory.
#
#   cd /path/to/your-project
#   /path/to/pi-agent-kit/scripts/setup.sh [--dry-run] [--lang=en|ja|ko|bn]
#
# Asks for a display language first (English, Japanese, Korean or Bengali; skip the question
# with --lang or PI_KIT_LANG). Then installs pi if missing, configures a local server, a cloud
# provider or both, installs the kit (skills, global AGENTS.md, quality gate, MCP servers,
# packages you pick) and prepares the project (.pi/check, starter AGENTS.md, .gitignore).
# Every pi config file it changes is backed up first (<file>.backup-<timestamp>).
# --dry-run asks the same questions but writes nothing.
set -euo pipefail

KIT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$(pwd)"
PI_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_KIT_STAMP="$(date +%Y%m%d-%H%M%S)"
# shellcheck source=lib/i18n.sh
LANG_ARG="${PI_KIT_LANG:-}"   # read before set_lang, which exports PI_KIT_LANG
source "$KIT/scripts/lib/i18n.sh"
set_lang en

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --lang=*) LANG_ARG=${arg#--lang=} ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf '%s\n' "$(t unknown_option "$arg")" >&2; exit 2 ;;
  esac
done
if [[ -n $LANG_ARG ]] && valid_lang "$LANG_ARG"; then set_lang "$LANG_ARG"; else choose_language; fi
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
  if [[ -n $__def ]]; then read -r -p "$__prompt [$__def]: " __ans || die "$(t no_input)"
  else read -r -p "$__prompt: " __ans || die "$(t no_input)"; fi
  printf -v "$__var" '%s' "${__ans:-$__def}"
}

ask_secret() { # ask_secret VAR "Prompt"
  local __var=$1 __ans=""
  read -r -s -p "$2: " __ans || die "$(t no_input)"
  printf '\n'
  printf -v "$__var" '%s' "$__ans"
}

confirm() { # confirm "Question" [y|n]
  local def=${2:-y} hint="[Y/n]" ans=""
  [[ $def == n ]] && hint="[y/N]"
  read -r -p "$1 $hint " ans || die "$(t no_input)"
  case "${ans:-$def}" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

choose() { # choose VAR "Question" option... -> VAR is the 1-based index
  local __var=$1 __q=$2 i=1 o ans=""
  shift 2
  printf '%s\n' "$__q"
  for o in "$@"; do printf '  %d) %s\n' "$i" "$o"; i=$((i + 1)); done
  while true; do
    read -r -p "$(t choose_n $#) " ans || die "$(t no_input)"
    if [[ $ans =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le $# ]; then break; fi
    warn "$(t enter_number $#)"
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
  if [[ $allow_login == 1 ]]; then labels+=("$(t key_login "$id")"); kinds+=(login); fi
  if [[ $(uname) == Darwin ]]; then labels+=("$(t key_keychain)"); kinds+=(keychain); fi
  labels+=("$(t key_env "$envvar")"); kinds+=(env)
  if [[ $allow_plain == 1 ]]; then labels+=("$(t key_plain)"); kinds+=(plain); fi
  choose c "$(t key_where "$id")" "${labels[@]}"
  KEY_REF="" KEY_VALUE="" NEED_LOGIN=0
  case "${kinds[$((c - 1))]}" in
    login) NEED_LOGIN=1 ;;
    keychain)
      if [[ $DRY_RUN == 1 ]]; then
        ask_secret KEY_VALUE "$(t key_dry "$id")"
      else
        info "$(t key_twice)"
        security add-generic-password -U -a pi-agent-kit -s "$svc" -w || die "$(t keychain_failed)"
        KEY_VALUE=$(security find-generic-password -a pi-agent-kit -s "$svc" -w)
      fi
      KEY_REF="!security find-generic-password -a pi-agent-kit -s $svc -w"
      [[ $DRY_RUN == 1 ]] || ok "$(t key_stored "$svc")" ;;
    env)
      if [[ -n ${!envvar:-} ]]; then KEY_VALUE=${!envvar}; ok "$(t env_set "$envvar")"
      else
        warn "$(t env_unset "$envvar" "$envvar")"
        ask_secret KEY_VALUE "$(t key_paste)"
      fi
      KEY_REF="\${$envvar}" ;;
    plain)
      ask_secret KEY_VALUE "$(t api_key)"
      KEY_REF=$KEY_VALUE ;;
  esac
}

# pick_model VAR "candidates (newline separated)"
pick_model() {
  local __var=$1 list=$2 filter n
  n=$(printf '%s\n' "$list" | grep -c . || true)
  if [ "$n" -gt 30 ]; then
    ask filter "$(t models_filter "$n")" ""
    list=$(printf '%s\n' "$list" | grep -i -- "$filter" | head -n 30 || true)
    n=$(printf '%s\n' "$list" | grep -c . || true)
  fi
  if [ "$n" -eq 0 ]; then ask "$__var" "$(t model_id)" ""; return; fi
  local arr=() line idx
  while IFS= read -r line; do [[ -n $line ]] && arr+=("$line"); done <<< "$list"
  arr+=("$(t type_model_instead)")
  choose idx "$(t which_model)" "${arr[@]}"
  if [ "$idx" -eq "${#arr[@]}" ]; then ask "$__var" "$(t model_id)" ""; else printf -v "$__var" '%s' "${arr[$((idx - 1))]}"; fi
}

# ---------- state ----------
USE_LOCAL=0 USE_CLOUD=0
LOCAL_PROVIDER="" LOCAL_MODEL="" LOCAL_URL="" LOCAL_CTX="" LOCAL_BACKEND=""
CLOUD_PROVIDER="" CLOUD_MODEL="" CLOUD_LOGIN=0
INSTALLED_PKGS=""

# ---------- 1. project ----------
step "$(t step_project)"
info "$(t project_folder "$PROJECT")"
[[ "$PROJECT" == "$HOME" || "$PROJECT" == "/" ]] && die "$(t not_in_home "$PROJECT")"
[[ "$PROJECT" == "$KIT" ]] && warn "$(t kit_folder)"
[[ $DRY_RUN == 1 ]] && warn "$(t dry_run_notice)"
confirm "$(t confirm_setup)" y || exit 0
command -v curl >/dev/null 2>&1 || die "$(t need_curl)"

# ---------- 2. pi ----------
step "$(t step_pi)"
PATH="$PI_DIR/bin:$PATH"
if command -v pi >/dev/null 2>&1; then
  ok "$(t pi_found "$(pi --version 2>/dev/null)" "$(command -v pi)")"
else
  warn "$(t pi_missing)"
  choose how "$(t pi_how)" "$(t pi_opt_official)" "$(t pi_opt_npm)" "$(t cancel)"
  case $how in
    1) run sh -c 'curl -fsSL https://pi.dev/install.sh | sh' ;;
    2) find_node || die "$(t node_missing_npm)"
       nv=$("$NODE" -p 'process.versions.node')
       "$NODE" -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(a>22||(a===22&&b>=19)?0:1)' \
         || die "$(t node_too_old "$nv")"
       run npm install -g --ignore-scripts @earendil-works/pi-coding-agent ;;
    3) exit 0 ;;
  esac
  hash -r
  if [[ $DRY_RUN == 0 ]]; then
    command -v pi >/dev/null 2>&1 || die "$(t pi_not_on_path)"
    ok "$(t pi_installed "$(pi --version)")"
  fi
fi
HAVE_PI=0; command -v pi >/dev/null 2>&1 && HAVE_PI=1
if [[ $HAVE_PI == 1 ]]; then
  major=$(pi --version 2>/dev/null | cut -d. -f1)
  if [[ $major =~ ^[0-9]+$ ]] && [ "$major" -lt 1 ]; then
    warn "$(t pi_too_old "$(pi --version)")"
    confirm "$(t pi_update_q)" y && run pi update self
  fi
fi
find_node || die "$(t node_missing)"

# ---------- 3. models ----------
step "$(t step_models)"
choose mode "$(t mode_q)" "$(t mode_local)" "$(t mode_cloud)" "$(t mode_both)"
case $mode in 1) USE_LOCAL=1 ;; 2) USE_CLOUD=1 ;; 3) USE_LOCAL=1; USE_CLOUD=1 ;; esac

setup_local() {
  local b url needs_key="n" ids="" ctx_def=32768 ctx maxout reasoning images model
  info ""
  choose b "$(t local_server_q)" "oMLX" "Ollama" "LM Studio" "$(t llama_router)" "$(t other_server)"
  case $b in
    1) LOCAL_PROVIDER=omlx url=http://127.0.0.1:8000/v1 needs_key=y LOCAL_BACKEND=omlx ;;
    2) LOCAL_PROVIDER=ollama url=http://127.0.0.1:11434/v1 LOCAL_BACKEND=ollama ;;
    3) LOCAL_PROVIDER=lmstudio url=http://127.0.0.1:1234/v1 LOCAL_BACKEND=lmstudio ;;
    4) LOCAL_BACKEND=llamacpp
       info "$(t llama_builtin)"
       info "  llama-server --models-dir ~/models --no-models-autoload --jinja --host 127.0.0.1 --port 8080 -ngl 999 -c 32768"
       ask LOCAL_URL "$(t router_url)" "http://127.0.0.1:8080"
       if curl -fsS -m 3 "$LOCAL_URL/health" >/dev/null 2>&1; then ok "$(t router_ok)"; else warn "$(t router_no "$LOCAL_URL")"; fi
       [[ $LOCAL_URL != "http://127.0.0.1:8080" ]] && warn "$(t llama_env "$LOCAL_URL")"
       info "$(t llama_next)"
       LOCAL_PROVIDER=llama.cpp
       return ;;
    5) ask LOCAL_PROVIDER "$(t provider_id)" "local"
       url=http://127.0.0.1:8080/v1 LOCAL_BACKEND=other ;;
  esac
  ask LOCAL_URL "$(t base_url)" "$url"

  if cfg has-provider "$PI_DIR/models.json" "$LOCAL_PROVIDER" 2>/dev/null; then
    warn "$(t provider_exists "$LOCAL_PROVIDER")"
  fi
  if confirm "$(t needs_key_q)" "$needs_key"; then
    pick_key_storage "$LOCAL_PROVIDER" "$(upper_env "$LOCAL_PROVIDER")" 1 0
  else
    KEY_REF=$LOCAL_PROVIDER KEY_VALUE=""   # dummy key: makes the provider available, the server ignores it
  fi

  local r
  while true; do
    info "$(t asking_models "$LOCAL_URL")"
    if ids=$(PI_KIT_KEY="$KEY_VALUE" cfg list-models "$LOCAL_URL" 2>/dev/null); then pick_model model "$ids"; break; fi
    warn "$(t list_failed)"
    choose r "$(t what_now)" "$(t retry)" "$(t type_model)"
    if [ "$r" -eq 2 ]; then ask model "$(t model_id_server)" ""; break; fi
  done
  [[ -n $model ]] || die "$(t model_required)"
  LOCAL_MODEL="$LOCAL_PROVIDER/$model"

  if [[ $LOCAL_BACKEND == omlx ]] && v=$(cfg json-get "$HOME/.omlx/settings.json" sampling.max_context_window 2>/dev/null); then
    ctx_def=$v; info "$(t omlx_ctx "$v")"
  fi
  warn "$(t ctx_warn)"
  ask ctx "$(t ctx_q)" "$ctx_def"
  [[ $ctx =~ ^[0-9]+$ ]] || die "$(t ctx_number)"
  maxout=$((ctx / 4)); [ "$maxout" -gt 8192 ] && maxout=8192
  ask maxout "$(t maxout_q)" "$maxout"
  reasoning=false; confirm "$(t thinking_q)" y && reasoning=true
  images=0; confirm "$(t images_q)" n && images=1
  LOCAL_CTX=$ctx

  PK_ID=$LOCAL_PROVIDER PK_BASE_URL=$LOCAL_URL PK_API_KEY=$KEY_REF PK_MODEL_ID=$model \
  PK_MODEL_NAME="$model (local)" PK_CONTEXT=$ctx PK_MAX_TOKENS=$maxout PK_REASONING=$reasoning \
  PK_IMAGES=$images PK_CACHE_TTL=3600 cfg upsert-provider "$PI_DIR/models.json"
  ok "$(t local_model "$LOCAL_MODEL")"
}

setup_cloud() {
  local c sub envvar ids="" model custom=0 url ctx maxout reasoning ttl
  info ""
  warn "$(t cloud_warn)"
  choose c "$(t cloud_q)" \
    "$(t openrouter_opt)" "DeepSeek" "Z.ai (GLM)" "Moonshot (Kimi)" \
    "$(t other_builtin)" "$(t custom_endpoint)"
  case $c in
    1) CLOUD_PROVIDER=openrouter envvar=OPENROUTER_API_KEY ;;
    2) CLOUD_PROVIDER=deepseek envvar=DEEPSEEK_API_KEY ;;
    3) CLOUD_PROVIDER=zai envvar=ZAI_API_KEY ;;
    4) CLOUD_PROVIDER=moonshotai envvar=MOONSHOT_API_KEY ;;
    5) choose sub "$(t which_one)" "OpenAI" "Anthropic" "Google Gemini" "Groq" "Fireworks" "Together AI" "Mistral" "xAI" \
         "Cerebras" "Vercel AI Gateway" "Kimi For Coding $(t subscription)" "Qwen Token Plan $(t subscription)"
       local pids=(openai anthropic google groq fireworks together mistral xai cerebras vercel-ai-gateway kimi-coding qwen-token-plan)
       local envs=(OPENAI_API_KEY ANTHROPIC_API_KEY GEMINI_API_KEY GROQ_API_KEY FIREWORKS_API_KEY TOGETHER_API_KEY MISTRAL_API_KEY XAI_API_KEY CEREBRAS_API_KEY AI_GATEWAY_API_KEY KIMI_API_KEY QWEN_TOKEN_PLAN_API_KEY)
       CLOUD_PROVIDER=${pids[$((sub - 1))]} envvar=${envs[$((sub - 1))]} ;;
    6) custom=1
       ask CLOUD_PROVIDER "$(t provider_id)" "mycloud"
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
      info "$(t asking_pi_models "$CLOUD_PROVIDER")"
      ids=$(env "$envvar=$KEY_VALUE" pi --no-approve --list-models "$CLOUD_PROVIDER" 2>/dev/null | awk -v p="$CLOUD_PROVIDER" 'NR > 1 && $1 == p { print $2 }' || true)
    fi
    if [[ -n $ids ]]; then pick_model model "$ids"
    else
      info "$(t cant_list "$CLOUD_PROVIDER")"
      ask model "$(t model_id_later)" ""
    fi
  else
    ask url "$(t base_url_v1)" "https://api.example.com/v1"
    pick_key_storage "$CLOUD_PROVIDER" "$envvar" 0 0
    if ids=$(PI_KIT_KEY="$KEY_VALUE" cfg list-models "$url" 2>/dev/null); then pick_model model "$ids"
    else warn "$(t list_failed_url "$url")"; ask model "$(t model_id)" ""; fi
    [[ -n $model ]] || die "$(t model_required_custom)"
    ask ctx "$(t ctx_q)" "131072"
    ask maxout "$(t maxout_q)" "16384"
    reasoning=false; confirm "$(t thinking_q)" y && reasoning=true
    info "$(t prices)"
    local pin pout pcr pcw
    ask pin "$(t price_input)" "0"; ask pout "$(t price_output)" "0"
    ask pcr "$(t price_cache_read)" "0"; ask pcw "$(t price_cache_write)" "0"
    ask ttl "$(t cache_ttl_q)" "300"
    PK_ID=$CLOUD_PROVIDER PK_BASE_URL=$url PK_API_KEY=$KEY_REF PK_MODEL_ID=$model PK_CONTEXT=$ctx \
    PK_MAX_TOKENS=$maxout PK_REASONING=$reasoning PK_COST="$pin,$pout,$pcr,$pcw" PK_CACHE_TTL=$ttl \
    cfg upsert-provider "$PI_DIR/models.json"
  fi
  if [[ -n $model ]]; then
    CLOUD_MODEL="$CLOUD_PROVIDER/$model"
    ok "$(t cloud_provider_model "$CLOUD_PROVIDER" "$CLOUD_MODEL")"
  else
    ok "$(t cloud_provider "$CLOUD_PROVIDER")"
  fi
}

[[ $USE_LOCAL == 1 ]] && setup_local
[[ $USE_CLOUD == 1 ]] && setup_cloud

# ---------- 4. settings ----------
step "$(t step_settings)"
DEFAULT_MODEL="" PROJECT_DEFAULT=""
if [[ $USE_LOCAL == 1 && $USE_CLOUD == 1 ]]; then
  choose d "$(t default_q)" "$(t default_local)" "$(t default_project)" "$(t default_cloud)"
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
info "$(t settings_changes "$PI_DIR/settings.json")"
cfg apply-settings "$PI_DIR/settings.json" preview
info "${DIM}$(t settings_note)${N}"
if confirm "$(t apply_q)" y; then cfg apply-settings "$PI_DIR/settings.json" write; else warn "$(t settings_skipped)"; fi
if [[ -n $PROJECT_DEFAULT ]]; then
  PK_PROJECT=1 PK_DEFAULT=$PROJECT_DEFAULT cfg apply-settings "$PROJECT/.pi/settings.json" write
  info "$(t project_trust)"
fi

if [[ -n $LOCAL_MODEL || -n $CLOUD_MODEL ]] && confirm "$(t aliases_q)" n; then
  rc="$HOME/.bashrc"; [[ ${SHELL:-} == */zsh ]] && rc="$HOME/.zshrc"
  block="# >>> pi-agent-kit >>>"$'\n'
  [[ -n $LOCAL_MODEL ]] && block+="alias pil='pi --model $LOCAL_MODEL'"$'\n'
  [[ -n $CLOUD_MODEL ]] && block+="alias pic='pi --model $CLOUD_MODEL:low'"$'\n'
  block+="# <<< pi-agent-kit <<<"
  if [[ $DRY_RUN == 1 ]]; then printf '%s+ %s%s\n%s\n' "$DIM" "$(t aliases_dry "$rc")" "$N" "$block"
  else
    [[ -f $rc ]] && sed -i.backup-"$PI_KIT_STAMP" '/^# >>> pi-agent-kit >>>$/,/^# <<< pi-agent-kit <<<$/d' "$rc"
    printf '\n%s\n' "$block" >> "$rc"
    ok "$(t aliases_added "$rc")"
  fi
fi

# ---------- 5. kit ----------
step "$(t step_kit)"
"$KIT/scripts/install.sh" skills
if confirm "$(t gate_q)" y; then
  "$KIT/scripts/install.sh" extension
fi

info ""
info "$(t mcp_title)"
servers=()
if confirm "$(t probe_q)" y; then
  servers+=(probe)
  if ! command -v probe >/dev/null 2>&1; then
    if confirm "$(t probe_install_q)" y; then run npm install -g @probelabs/probe@latest
    else warn "$(t probe_later)"; fi
  fi
fi
confirm "$(t context7_q)" y && servers+=(context7)
if [ "${#servers[@]}" -gt 0 ]; then cfg merge-mcp "$PI_DIR/mcp.json" "$KIT/config/mcp.json" "${servers[@]}"; fi

# ---------- 6. packages ----------
step "$(t step_packages)"
warn "$(t packages_warn)"
offer_tier() { # offer_tier TIER DEFAULT "question"
  if [[ $HAVE_PI == 0 ]]; then warn "$(t tier_skip "$1")"; return; fi
  if confirm "$3" "$2"; then "$KIT/scripts/install.sh" packages "$1"; INSTALLED_PKGS+=" $1"; fi
}
offer_tier core y "$(t tier_core)"
offer_tier tokens y "$(t tier_tokens)"
offer_tier ondemand y "$(t tier_ondemand)"
if [[ $USE_CLOUD == 1 ]]; then
  [[ $USE_LOCAL == 1 ]] && info "${DIM}$(t context_diet_note)${N}"
  offer_tier cloud y "$(t tier_cloud)"
fi
offer_tier tuning n "$(t tier_tuning)"

# ---------- 7. project ----------
step "$(t step_project_files)"
cd "$PROJECT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  confirm "$(t git_init_q)" y && run git init -q
fi
run mkdir -p .pi

suggest=$(cfg detect-check "$PROJECT")
if [[ -s .pi/check ]] && ! confirm "$(t check_replace_q "$(head -n 1 .pi/check)")" n; then
  check=$(head -n 1 .pi/check)
else
  ask check "$(t check_q)" "$suggest"
  if [[ -n $check ]]; then
    if [[ $DRY_RUN == 1 ]]; then run "$(t check_dry "$check")"; else printf '%s\n' "$check" > .pi/check; ok "$(t check_written "$check")"; fi
  fi
fi

if [[ ! -e AGENTS.md && ! -e CLAUDE.md ]]; then
  if confirm "$(t agents_q)" y; then
    if [[ $DRY_RUN == 1 ]]; then run "$(t agents_dry)"; cfg agents-template "$PROJECT" "${check:-}"
    else cfg agents-template "$PROJECT" "${check:-}" > AGENTS.md; ok "$(t agents_created)"; fi
  fi
else
  ok "$(t agents_exists)"
fi

if ! grep -qx '.pi/handoff.md' .gitignore 2>/dev/null; then
  if [[ $DRY_RUN == 1 ]]; then run "$(t gitignore_dry)"
  else printf '.pi/handoff.md\n' >> .gitignore; ok "$(t gitignore_added)"; fi
fi

# ---------- summary ----------
step "$(t step_checks)"
if [[ $HAVE_PI == 1 && $DRY_RUN == 0 ]]; then
  for p in $LOCAL_PROVIDER $CLOUD_PROVIDER; do
    [[ $p == llama.cpp ]] && continue
    if out=$(pi auth check --provider "$p" --json 2>/dev/null) && [[ $out == *'"ready"'* ]]; then ok "$(t creds_ready "$p")"
    elif [[ $p == "$CLOUD_PROVIDER" && $CLOUD_LOGIN == 1 ]]; then warn "$(t not_logged_in "$p" "$p")"
    else warn "$(t not_ready "$p" "$out")"; fi
  done
  if [[ -n $LOCAL_URL && $LOCAL_BACKEND != llamacpp ]]; then
    if curl -s -m 3 -o /dev/null "$LOCAL_URL/models"; then ok "$(t local_ok "$LOCAL_URL")"; else warn "$(t local_no "$LOCAL_URL")"; fi
  fi
fi

step "$(t step_next)"
n=1
next() { info "$n. $*"; n=$((n + 1)); }
next "$(t next_run "$PROJECT")"
[[ $CLOUD_LOGIN == 1 ]] && next "$(t next_login "$CLOUD_PROVIDER")"
[[ -z $DEFAULT_MODEL ]] && next "$(t next_model)"
next "$(t next_map)"
next "$(t next_mcp)"
[[ $INSTALLED_PKGS == *core* ]] && next "$(t next_rtk)"
[[ $INSTALLED_PKGS == *tokens* ]] && next "$(t next_caveman)"
if [[ $LOCAL_BACKEND == omlx ]]; then
  info ""
  info "$(t omlx_tip1)"
  info "$(t omlx_tip2)"
fi
info ""
info "$(t measure)"
[[ $DRY_RUN == 1 ]] && warn "$(t dry_done)"
exit 0
