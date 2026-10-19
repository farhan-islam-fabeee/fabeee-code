#!/usr/bin/env bash
# Install parts of fabeee-code into a project, so the whole setup is committed and shared.
# [project] defaults to the current folder. Nothing is written to ~/.pi/agent.
#
#   ./scripts/install.sh skills [project]           skills/* -> .pi/skills/, /skills-global command
#   ./scripts/install.sh context [project]          rules section in .pi/AGENTS.md, extension that makes pi read it
#   ./scripts/install.sh models [project]           extension that loads .pi/models.json (project model providers)
#   ./scripts/install.sh extension [project]        quality gate -> .pi/extensions/
#   ./scripts/install.sh mcp [project]              config/mcp.json -> .pi/mcp.json (only if absent)
#   ./scripts/install.sh packages <tier> [project]  pi install -l the packages in a tier (see tiers below)
#   ./scripts/install.sh all [project]              skills + context + models + extension + mcp (no packages)
#
# Set DRY_RUN=1 to print actions without doing them. Messages follow FABEEE_CODE_LANG (en, ja, ko, bn).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

project_dir() { printf '%s' "${1:-${FABEEE_CODE_PROJECT:-$PWD}}"; }

add_extension() { # add_extension PROJECT FILE
  run mkdir -p "$1/.pi/extensions"
  run cp "$ROOT/extensions/$2" "$1/.pi/extensions/$2"
}

install_skills() {
  local project target
  project=$(project_dir "${1:-}")
  target="$project/.pi/skills"
  run mkdir -p "$target"
  for dir in "$ROOT"/skills/*/; do
    local name; name="$(basename "$dir")"
    run rm -rf "$target/$name"
    run cp -R "$dir" "$target/$name"
    t inst_skill "$name"; echo
  done
  add_extension "$project" skills-global.ts
  t inst_skills_done "$target"; echo
}

install_context() {
  local project target
  project=$(project_dir "${1:-}")
  target="$project/.pi/AGENTS.md"
  run mkdir -p "$project/.pi"
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
  # Makes pi read .pi/AGENTS.md instead of the root AGENTS.md/CLAUDE.md other harnesses use.
  add_extension "$project" pi-agents-md.ts
}

install_models() {
  add_extension "$(project_dir "${1:-}")" project-models.ts
}

install_extension() {
  add_extension "$(project_dir "${1:-}")" quality-gate.ts
  t inst_ext_done; echo
}

install_mcp() {
  local file
  file="$(project_dir "${1:-}")/.pi/mcp.json"
  if [[ -e $file ]]; then
    t inst_mcp_exists "$file"; echo
  else
    run mkdir -p "$(dirname "$file")"
    run cp "$ROOT/config/mcp.json" "$file"
    t inst_mcp_done; echo
  fi
  command -v probe >/dev/null || { t inst_probe_missing; echo; }
}

install_packages() {
  local tier="${1:-}" project
  project=$(project_dir "${2:-}")
  case "$tier" in
    core|tokens|ondemand|tuning|cloud|ab) ;;
    *) { t inst_pkg_usage "$0"; echo; } >&2; exit 2 ;;
  esac
  # tier is validated above; eval keeps this working on macOS's bash 3.2 (no namerefs)
  local pkgs; eval "pkgs=(\"\${${tier}[@]}\")"
  t inst_pkg_warn; echo
  local failed=()
  for pkg in "${pkgs[@]}"; do
    # .pi/settings.json lists packages as "npm:<name>" or "npm:<name>@<version>"
    if grep -q "\"npm:$pkg[\"@]" "$project/.pi/settings.json" 2>/dev/null; then
      t inst_pkg_skip "$pkg"; echo
      continue
    fi
    # -l: declare in .pi/settings.json, download into .pi/npm/. --approve: trust the project for this
    # command only. One failing package (e.g. a native module that won't build) must not stop the rest.
    if ! (cd "$project" && run pi install -l --approve "npm:$pkg"); then
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
  models) install_models "${2:-}" ;;
  extension) install_extension "${2:-}" ;;
  mcp) install_mcp "${2:-}" ;;
  packages) install_packages "${2:-}" "${3:-}" ;;
  all) install_skills "${2:-}"; install_context "${2:-}"; install_models "${2:-}"; install_extension "${2:-}"; install_mcp "${2:-}" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
