#!/usr/bin/env bash
# Install parts of fabeee-code into your pi setup.
# Never overwrites models.json or settings.json; existing extensions are backed up first.
#
#   ./scripts/install.sh skills [project]    copy skills/* to <project>/.agents/skills/ (default: current folder)
#                                            and the /skills-global pi command to ~/.pi/agent/extensions/
#   ./scripts/install.sh context [project]   add/update the rules section (context/AGENTS.md) in <project>/AGENTS.md
#   ./scripts/install.sh extension           copy extensions/quality-gate.ts to ~/.pi/agent/extensions/
#   ./scripts/install.sh mcp                 copy config/mcp.json to ~/.pi/agent/mcp.json (only if absent)
#   ./scripts/install.sh packages <tier>     pi install the packages in a tier (see TIERS below)
#   ./scripts/install.sh all [project]       skills + rules + extension + mcp (no packages)
#
# Set DRY_RUN=1 to print actions without doing them. Messages follow FABEEE_CODE_LANG (en, ja, ko, bn).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PI_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
STAMP="${FABEEE_CODE_STAMP:-$(date +%Y%m%d-%H%M%S)}"
# shellcheck source=lib/i18n.sh
source "$ROOT/scripts/lib/i18n.sh"
set_lang "${FABEEE_CODE_LANG:-en}"

core=(pi-lens cc-safety-net @ssk_dev/rpiv-todo-lean pi-rtk-optimizer)
tokens=(@sting8k/pi-vcc pi-prefix-stabilizer pi-caveman)
ondemand=(@narumitw/pi-plan-mode pi-simplify pi-subagents)
tuning=(pi-context-view)
cloud=(pi-cache-optimizer pi-context-diet)
ab=(pi-hashline-edit-pro)

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then echo "+ $*"; else "$@"; fi
}

backup() {
  local target="$1" backup_root="$2"
  if [[ -e "$target" ]]; then
    run mkdir -p "$backup_root"
    run mv "$target" "$backup_root/"
    t inst_backed_up "$(basename "$target")" "$backup_root"; echo
  fi
}

install_skills() {
  local target="${1:-${FABEEE_CODE_PROJECT:-$PWD}}/.agents/skills"
  run mkdir -p "$target"
  for dir in "$ROOT"/skills/*/; do
    local name; name="$(basename "$dir")"
    run rm -rf "$target/$name"
    run cp -R "$dir" "$target/$name"
    t inst_skill "$name"; echo
  done
  run mkdir -p "$PI_DIR/extensions"
  run cp "$ROOT/extensions/skills-global.ts" "$PI_DIR/extensions/skills-global.ts"
  t inst_skills_done "$target"; echo
}

install_context() {
  local project="${1:-${FABEEE_CODE_PROJECT:-$PWD}}" target
  # Use the project's existing context file; pi reads AGENTS.md or CLAUDE.md.
  target="$project/AGENTS.md"
  [[ ! -e $target && -e $project/CLAUDE.md ]] && target="$project/CLAUDE.md"
  local begin="<!-- fabeee-code:rules -->" end="<!-- /fabeee-code:rules -->" tmp
  tmp=$(mktemp)
  # Keep everything outside our marked section (dropping trailing blank lines), then append it fresh.
  if [[ -f $target ]]; then
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip = 1; next }
      $0 == e { skip = 0; next }
      skip { next }
      /^$/ { blank++; next }
      { while (blank > 0) { print ""; blank-- } print }' "$target" > "$tmp"
  fi
  { [[ -s $tmp ]] && { cat "$tmp"; echo; }; echo "$begin"; cat "$ROOT/context/AGENTS.md"; echo "$end"; } > "$tmp.new"
  if [[ -f $target ]] && cmp -s "$tmp.new" "$target"; then
    t inst_agents_same "$target"; echo
  else
    run cp "$tmp.new" "$target"
    t inst_agents_done "$target"; echo
  fi
  rm -f "$tmp" "$tmp.new"
}

install_extension() {
  run mkdir -p "$PI_DIR/extensions"
  backup "$PI_DIR/extensions/quality-gate.ts" "$PI_DIR/extensions-backup-$STAMP"
  run cp "$ROOT/extensions/quality-gate.ts" "$PI_DIR/extensions/quality-gate.ts"
  t inst_ext_done; echo
}

install_mcp() {
  if [[ -e "$PI_DIR/mcp.json" ]]; then
    t inst_mcp_exists "$PI_DIR/mcp.json"; echo
  else
    run mkdir -p "$PI_DIR"
    run cp "$ROOT/config/mcp.json" "$PI_DIR/mcp.json"
    t inst_mcp_done; echo
  fi
  command -v probe >/dev/null || { t inst_probe_missing; echo; }
  t inst_mcp_check; echo
}

install_packages() {
  local tier="${1:-}"
  case "$tier" in
    core|tokens|ondemand|tuning|cloud|ab) ;;
    *) { t inst_pkg_usage "$0"; echo; } >&2; exit 2 ;;
  esac
  # tier is validated above; eval keeps this working on macOS's bash 3.2 (no namerefs)
  local pkgs; eval "pkgs=(\"\${${tier}[@]}\")"
  t inst_pkg_warn; echo
  local failed=()
  for pkg in "${pkgs[@]}"; do
    # settings.json lists installed packages as "npm:<name>" or "npm:<name>@<version>"
    if grep -q "\"npm:$pkg[\"@]" "$PI_DIR/settings.json" 2>/dev/null; then
      t inst_pkg_skip "$pkg"; echo
      continue
    fi
    # One failing package (for example a native module that won't build) must not stop the rest.
    if ! run pi install "npm:$pkg"; then
      failed+=("$pkg")
      t inst_pkg_failed "$pkg"; echo
    fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    t inst_pkg_failed_hint; echo
    return 1
  fi
}

case "${1:-}" in
  skills) install_skills "${2:-}" ;;
  context) install_context "${2:-}" ;;
  extension) install_extension ;;
  mcp) install_mcp ;;
  packages) install_packages "${2:-}" ;;
  all) install_skills "${2:-}"; install_context "${2:-}"; install_extension; install_mcp ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
