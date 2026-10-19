#!/usr/bin/env bash
# Install parts of pi-agent-kit into your pi setup.
# Never overwrites models.json or settings.json; existing skills, extensions and AGENTS.md are backed up first.
#
#   ./scripts/install.sh skills              copy skills/* to ~/.agents/skills/ and context/AGENTS.md to ~/.pi/agent/
#   ./scripts/install.sh context             only install context/AGENTS.md (global rules: language, terse internals)
#   ./scripts/install.sh extension           copy extensions/quality-gate.ts to ~/.pi/agent/extensions/
#   ./scripts/install.sh mcp                 copy config/mcp.json to ~/.pi/agent/mcp.json (only if absent)
#   ./scripts/install.sh packages <tier>     pi install the packages in a tier (see TIERS below)
#   ./scripts/install.sh all                 skills + extension + mcp (no packages)
#
# Set DRY_RUN=1 to print actions without doing them. Messages follow PI_KIT_LANG (en, ja, ko, bn).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="${HOME}/.agents/skills"
PI_DIR="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
STAMP="${PI_KIT_STAMP:-$(date +%Y%m%d-%H%M%S)}"
# shellcheck source=lib/i18n.sh
source "$ROOT/scripts/lib/i18n.sh"
set_lang "${PI_KIT_LANG:-en}"

core=(pi-lens cc-safety-net @ssk_dev/rpiv-todo-lean pi-token-killer)
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
  run mkdir -p "$SKILLS_DIR"
  for dir in "$ROOT"/skills/*/; do
    local name; name="$(basename "$dir")"
    backup "$SKILLS_DIR/$name" "${SKILLS_DIR}-backup-$STAMP"
    run cp -R "$dir" "$SKILLS_DIR/$name"
    t inst_skill "$name"; echo
  done
  t inst_skills_done; echo
  install_context
}

install_context() {
  local target="$PI_DIR/AGENTS.md"
  run mkdir -p "$PI_DIR"
  if [[ -e "$target" ]] && cmp -s "$ROOT/context/AGENTS.md" "$target"; then
    t inst_agents_same; echo
    return
  fi
  if [[ -e "$target" ]]; then
    # pi only loads the exact name AGENTS.md, so a suffixed backup beside it stays inert
    run mv "$target" "$target.backup-$STAMP"
    t inst_agents_backup "$target.backup-$STAMP"; echo
  fi
  run cp "$ROOT/context/AGENTS.md" "$target"
  t inst_agents_done "$target"; echo
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
  for pkg in "${pkgs[@]}"; do
    run pi install "npm:$pkg"
  done
}

case "${1:-}" in
  skills) install_skills ;;
  context) install_context ;;
  extension) install_extension ;;
  mcp) install_mcp ;;
  packages) install_packages "${2:-}" ;;
  all) install_skills; install_extension; install_mcp ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
