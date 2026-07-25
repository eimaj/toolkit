#!/usr/bin/env bash
#
# install.sh — set up the four toolkit repos in dependency order.
#
# Interactive and a la carte: asks about each repo separately, clones only what you
# accept, and delegates to that repo's OWN installer rather than reimplementing it.
# Existing clones are reused, never re-cloned and never pulled without asking.
#
# Order is clog -> dev-prompter -> orchestrate -> pm, so each tool finds its optional
# dependencies already present. See docs/INTEGRATION.md for why pm goes last.
#
# Usage: ./install.sh [--all] [--dry-run] [--root DIR] [--only a,b,c] [--help]

set -euo pipefail

TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="${TOOLKIT_ROOT_DIR:-$HOME/Code}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGENTS_DIR="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
DRY_RUN=false
ASSUME_YES=false
ONLY=""

# Install order is load-bearing — see docs/INTEGRATION.md.
ORDER=(clog dev-prompter orchestrate pm)

repo_url() {
  case "$1" in
    clog)         echo "https://github.com/eimaj/clog" ;;
    dev-prompter) echo "https://github.com/eimaj/dev-prompter" ;;
    orchestrate)  echo "https://github.com/eimaj/orchestrate" ;;
    pm)           echo "https://github.com/eimaj/project-manager" ;;
  esac
}

repo_blurb() {
  case "$1" in
    clog)         echo "structured JSONL session logging + retro skills (the substrate)" ;;
    dev-prompter) echo "the /dev family + /pr-review, the multi-lens review engine" ;;
    orchestrate)  echo "multi-agent write -> review -> retro runs with auditable artifacts" ;;
    pm)           echo "per-project context, live session sync, multi-session handoffs" ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --all             Yes to all four repos; no prompts.
  --only a,b,c      Only consider these repos (clog, dev-prompter, orchestrate, pm).
                    Still installs them in dependency order.
  --root DIR        Where to clone repos. Default: ~/Code
  --dry-run         Print every action, change nothing.
  -h, --help        This message.

Install order is always clog -> dev-prompter -> orchestrate -> pm.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --root)    ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --root=*)  ROOT="${1#*=}"; shift ;;
    --only)    ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --only=*)  ONLY="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

ROOT="${ROOT/#\~/$HOME}"

say()   { echo "  $*"; }
info()  { echo ""; echo "==> $*"; }
warn()  { echo "  [!] $*" >&2; }
fail()  { echo "" >&2; echo "ERROR: $*" >&2; exit 1; }
run()   { if $DRY_RUN; then printf '  [dry-run]'; printf ' %q' "$@"; echo; else "$@"; fi; }

# Track outcomes so the closing summary reflects what actually happened.
INSTALLED=()
SKIPPED=()
NOTES=()

prompt_yn() {
  # prompt_yn <question> <default y|n>
  local q="$1" default="${2:-y}" reply hint
  $ASSUME_YES && { echo "  ${q} [auto: yes]"; return 0; }
  [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
  if [[ ! -t 0 ]]; then
    say "${q} ${hint} -> non-interactive, using default: ${default}"
    [[ "$default" == "y" ]]
    return
  fi
  read -r -p "  ${q} ${hint} " reply || reply=""
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy] ]]
}

selected() {
  [[ -z "$ONLY" ]] && return 0
  local want
  IFS=',' read -ra want <<< "$ONLY"
  for w in "${want[@]}"; do
    [[ "${w// /}" == "$1" ]] && return 0
  done
  return 1
}

# Symlink a directory into place. Never clobbers a real directory — that is almost
# always a hand-maintained skill the user cares more about than ours.
link_dir() {
  local src="$1" dst="$2"
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    warn "$dst exists and is not a symlink — skipping (remove it manually to relink)"
    return 1
  fi
  run ln -sfn "$src" "$dst"
  say "linked: $dst -> $src"
}

# Sets RESOLVED_DIR rather than echoing it — progress output goes to the user, so
# capturing this function's stdout would swallow the messages into the path.
RESOLVED_DIR=""
ensure_clone() {
  local name="$1" url dest
  url="$(repo_url "$name")"
  dest="$ROOT/$name"

  if [[ -d "$dest/.git" ]]; then
    say "found existing clone: $dest (left untouched — pull it yourself if you want)"
  elif [[ -e "$dest" ]]; then
    fail "$dest exists but is not a git clone. Move it aside and re-run."
  else
    run mkdir -p "$ROOT"
    say "cloning $url -> $dest"
    run git clone --quiet "$url" "$dest"
  fi
  RESOLVED_DIR="$dest"
}

# ── Per-repo installers ─────────────────────────────────────────────────────────
# Each one delegates to the repo's own installer where one exists. dev-prompter is the
# exception: it ships no installer, so we do the documented symlink install here.

install_clog() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  # clog's setup.sh is itself interactive (tool detection, hook registration, Ledger).
  if [[ -e "$HOME/.claude/hooks/clog.sh" || -e "$HOME/.config/clog/config.yaml" ]]; then
    say "existing clog install detected — passing --migrate (backs up, never deletes)"
    args+=(--migrate)
  fi
  run bash "$dir/setup.sh" "${args[@]}"
  NOTES+=("clog: set log_root in ~/.config/clog/config.yaml to somewhere you'll actually look")
}

install_dev_prompter() {
  local dir="$1" s
  run mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"
  for s in _devkit dev dev-tab dev-sa dev-sa-q dev-tab-q pr-review; do
    link_dir "$dir/skills/$s" "$SKILLS_DIR/$s" || true
  done

  local personas="$AGENTS_DIR/personas.md"
  if [[ -e "$personas" ]]; then
    warn "$personas already exists — NOT overwriting."
    NOTES+=("dev-prompter: merge the Task Personas table from $dir/agents/personas.md into your existing $personas")
  else
    run cp "$dir/agents/personas.md" "$personas"
    say "installed: $personas"
  fi
}

install_orchestrate() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  run bash "$dir/install.sh" "${args[@]}"
  NOTES+=("orchestrate: set artifact_root in $dir/config.json")
  NOTES+=("orchestrate: copy a recipe + its agents into recipes/local/ and prompts/agents/local/, then replace every [TODO] — runs fast-fail on placeholders")
}

install_pm() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  command -v jq >/dev/null 2>&1 || fail "pm requires jq. Install it (brew install jq) and re-run."
  run bash "$dir/install.sh" "${args[@]}"
  NOTES+=("pm: run /pm-generate in Claude Code — and when it reaches the 'logs' group, set the provider to 'clog' (the example config's placeholder is 'logTool')")
}

# ── Preflight ───────────────────────────────────────────────────────────────────
echo "toolkit installer — clog, dev-prompter, orchestrate, pm"
$DRY_RUN && echo "(dry-run mode — nothing will be changed)"

info "Checking prerequisites..."
for bin in bash git; do
  command -v "$bin" >/dev/null 2>&1 || fail "$bin is required."
  say "$bin: $(command -v "$bin")"
done
if command -v jq >/dev/null 2>&1; then
  say "jq: $(command -v jq)"
else
  warn "jq not found — required by pm, and used by clog's retro skills."
fi
command -v gh >/dev/null 2>&1 && say "gh: $(command -v gh)" || warn "gh not found — needed for the GitHub-facing skills."
say "clone root: $ROOT"
say "skills dir: $SKILLS_DIR"

if [[ -n "$ONLY" ]]; then
  for w in ${ONLY//,/ }; do
    case "$w" in
      clog|dev-prompter|orchestrate|pm) ;;
      *) fail "--only: unknown repo '$w' (valid: clog, dev-prompter, orchestrate, pm)" ;;
    esac
  done
fi

# ── Main loop ───────────────────────────────────────────────────────────────────
for name in "${ORDER[@]}"; do
  selected "$name" || continue

  info "$name — $(repo_blurb "$name")"
  if ! prompt_yn "Install ${name}?" "y"; then
    say "skipped."
    SKIPPED+=("$name")
    continue
  fi

  ensure_clone "$name"
  dir="$RESOLVED_DIR"
  case "$name" in
    clog)         install_clog "$dir" ;;
    dev-prompter) install_dev_prompter "$dir" ;;
    orchestrate)  install_orchestrate "$dir" ;;
    pm)           install_pm "$dir" ;;
  esac
  INSTALLED+=("$name")
done

# ── Summary ─────────────────────────────────────────────────────────────────────
info "Done."
if [[ ${#INSTALLED[@]} -gt 0 ]]; then
  say "Installed: ${INSTALLED[*]}"
else
  say "Installed: nothing"
fi
[[ ${#SKIPPED[@]} -gt 0 ]] && say "Skipped:   ${SKIPPED[*]}"

if [[ ${#NOTES[@]} -gt 0 ]]; then
  echo ""
  say "Next steps:"
  for n in "${NOTES[@]}"; do echo "    - $n"; done
fi

echo ""
say "Restart your Claude Code session so it re-scans ~/.claude/skills/."
say "Then read docs/ONBOARDING.md for the four-week adoption path."
echo ""
