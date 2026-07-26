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
# --dry-run runs each tool's OWN dry-run, so the preview shows what every installer
# would actually touch — not just that it would be called.
#
# Usage: ./install.sh [--all] [--dry-run] [--root DIR] [--only a,b,c] [--help]

set -euo pipefail

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

# Reduce a remote URL to owner/repo so the SSH and HTTPS forms of the same repo
# compare equal — plenty of people clone over SSH.
repo_slug() {
  local u="${1%.git}"
  u="${u##*github.com:}"
  u="${u##*github.com/}"
  echo "$u"
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

  --all             Accept every offered repo; no prompts. Required when there is
                    no terminal to prompt on (CI, pipes, agents).
  --only a,b,c      Consider only these repos (clog, dev-prompter, orchestrate, pm).
  --root DIR        Where to clone repos. Default: ~/Code
  --dry-run         Change nothing, and run each tool's own dry-run so the preview
                    shows what that installer would touch.
  -h, --help        This message.

Pick any subset. Repos are walked in the order clog -> dev-prompter -> orchestrate
-> pm so each one finds its optional dependencies already present; the only part
that matters is clog before the others and pm last.

Environment overrides:
  TOOLKIT_ROOT_DIR    same as --root
  CLAUDE_SKILLS_DIR   default ~/.claude/skills
  CLAUDE_AGENTS_DIR   default ~/.claude/agents

This clones four repos from github.com/eimaj and runs each one's installer.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     ASSUME_YES=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --root)    ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --root=*)  ROOT="${1#*=}"; [[ -n "$ROOT" ]] || { echo "--root needs a directory" >&2; exit 1; }; shift ;;
    --only)    ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --only=*)  ONLY="${1#*=}"; [[ -n "$ONLY" ]] || { echo "--only needs a comma-separated list" >&2; exit 1; }; shift ;;
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

# Track outcomes so the closing summary reflects what actually happened. FAILED and
# PARTIAL exist because a repo that errored, or installed with refusals, must not be
# reported the same way as one that landed cleanly.
INSTALLED=()
SKIPPED=()
FAILED=()
PARTIAL=()
NOTES=()

# Never answers on the user's behalf. A missing TTY is rejected up front in the
# preflight, so there is no silent-default path: consent is either typed or --all.
prompt_yn() {
  # prompt_yn <question> <default y|n>
  local q="$1" default="${2:-y}" reply hint
  $ASSUME_YES && { echo "  ${q} [--all: yes]"; return 0; }
  [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
  # EOF (Ctrl-D) is an abort gesture, not consent.
  read -r -p "  ${q} ${hint} " reply || { echo; return 1; }
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

# Symlink a directory into place, clobbering nothing. A real directory is a
# hand-maintained skill; a symlink pointing somewhere else is someone else's install.
# Only a link this script already owns (same target) is touched, which keeps re-runs
# idempotent. Returns non-zero on refusal or failure so the caller can report it.
link_dir() {
  local src="$1" dst="$2" current
  if [[ -L "$dst" ]]; then
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]]; then
      say "already linked: $dst"
      return 0
    fi
    warn "$dst is a symlink to $current — skipping (remove it manually to relink)"
    return 1
  fi
  if [[ -e "$dst" ]]; then
    warn "$dst exists and is not a symlink — skipping (remove it manually to relink)"
    return 1
  fi
  if ! run ln -sfn "$src" "$dst"; then
    warn "failed to link $dst"
    return 1
  fi
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
    # Confirm it is actually the expected repo before running anything inside it —
    # clog/pm/orchestrate are generic directory names and an unrelated checkout
    # would otherwise get its installer executed.
    local origin
    origin="$(git -C "$dest" remote get-url origin 2>/dev/null || echo "")"
    if [[ "$(repo_slug "$origin")" != "$(repo_slug "$url")" ]]; then
      warn "$dest is a git repo, but its origin is '${origin:-none}' rather than $url"
      # A fork is a legitimate reason to say yes, so a human gets the choice. An
      # unattended run does not — it skips rather than executing an unknown repo.
      if $ASSUME_YES || ! prompt_yn "Run the installer in $dest anyway?" "n"; then
        warn "skipping $name — nothing in that directory was run"
        return 1
      fi
    fi
    say "found existing clone: $dest (left untouched — pull it yourself if you want)"
  elif [[ -e "$dest" ]]; then
    warn "$dest exists but is not a git clone — skipping $name"
    return 1
  else
    run mkdir -p "$ROOT"
    say "cloning $url -> $dest"
    if ! run git clone --quiet "$url" "$dest"; then
      warn "clone failed for $name"
      return 1
    fi
  fi
  RESOLVED_DIR="$dest"
}

# ── Per-repo installers ─────────────────────────────────────────────────────────
# Each one delegates to the repo's own installer where one exists. dev-prompter is the
# exception: it ships no installer, so we do the documented symlink install here.
#
# Forwarded flags use the "${args[@]+"${args[@]}"}" guard, not a bare "${args[@]}":
# under `set -u`, bash < 4.4 treats an empty array expansion as an unbound variable and
# aborts. macOS still ships bash 3.2, and args IS empty on the common path (a real
# install with no --dry-run and no --migrate).
#
# run_installer EXECUTES even under --dry-run, passing that tool's own --dry-run.
# The preview then comes from the installer that owns the work instead of from a
# guess here, and it covers what that tool would touch, not merely that it would run.
run_installer() {
  local script="$1"; shift
  if [[ ! -f "$script" ]]; then
    warn "expected installer not found: $script"
    return 1
  fi
  bash "$script" "$@"
}

# Mirrors clog's own detect_existing_install so the two cannot disagree. When they
# do, clog's setup exits telling the user to re-run with a flag this script never
# exposed, and the whole run dies on the first repo.
clog_installed() {
  [[ -e "$HOME/.claude/hooks/clog.sh" ]] && return 0
  [[ -e "$HOME/.config/clog/config.yaml" ]] && return 0
  [[ -n "${CLOG_BIN:-}" ]] && return 0
  [[ -n "${AI_LOG_ROOT:-}" ]] && return 0
  return 1
}

install_clog() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  # clog gates --migrate behind an explicit opt-in. Ask rather than answering for it.
  if clog_installed; then
    say "an existing clog install was detected."
    if prompt_yn "Pass --migrate so clog's setup can update it (it backs up first)?" "y"; then
      args+=(--migrate)
    else
      say "continuing without --migrate — clog's setup will decline to overwrite it"
    fi
  fi
  run_installer "$dir/setup.sh" "${args[@]+"${args[@]}"}"
  NOTES+=("clog: set log_root in ~/.config/clog/config.yaml, and confirm 'command -v clog' resolves (its CLI lands in ~/.local/bin)")
}

# dev-prompter ships no installer, so the documented symlink install lives here.
# _devkit is the shared base the five /dev skills read, not a slash command; it is
# linked alongside them because they resolve it by path.
install_dev_prompter() {
  local dir="$1" s refused=0
  run mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"
  for s in _devkit dev dev-tab dev-sa dev-sa-q dev-tab-q pr-review; do
    if [[ ! -d "$dir/skills/$s" ]]; then
      warn "$dir/skills/$s is missing upstream — not linking a dangling path"
      refused=$((refused + 1))
      continue
    fi
    # Collisions are survivable and must not abort the remaining repos, so the
    # refusal is counted and reported rather than raised.
    link_dir "$dir/skills/$s" "$SKILLS_DIR/$s" || refused=$((refused + 1))
  done

  local personas="$AGENTS_DIR/personas.md"
  if [[ -e "$personas" ]]; then
    say "$personas already exists — left as-is"
    NOTES+=("dev-prompter: if you want its task personas, merge them from $dir/agents/personas.md into $personas")
  else
    run cp "$dir/agents/personas.md" "$personas"
    say "installed: $personas"
  fi

  # Nothing linked at all is a failure, not a caveat.
  if (( refused == 7 )); then
    warn "no skills could be linked into $SKILLS_DIR"
    return 1
  fi
  if (( refused > 0 )); then
    PARTIAL+=("dev-prompter: $refused of 7 links skipped — the rest are in place")
  fi
}

install_orchestrate() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  run_installer "$dir/install.sh" "${args[@]+"${args[@]}"}"
  NOTES+=("orchestrate: set artifact_root in $dir/config.json")
  NOTES+=("orchestrate: copy a recipe and the agents it names into recipes/local/ and prompts/agents/local/ — code-writer's three run as shipped; feature-scoper's carry [TODO] personas and fast-fail until filled in")
}

install_pm() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  run_installer "$dir/install.sh" "${args[@]+"${args[@]}"}"
  NOTES+=("pm: run /pm-generate in Claude Code — and when it reaches the 'logs' group, set the provider to 'clog' (the example config's placeholder is 'logTool')")
}

# ── Preflight ───────────────────────────────────────────────────────────────────
echo "toolkit installer — clog, dev-prompter, orchestrate, pm"
echo "clones from github.com/eimaj and runs each repo's own installer."
$DRY_RUN && echo "(dry-run — nothing changes; each tool's own --dry-run is run instead)"

# Consent cannot be inferred from silence. Without a terminal there is nobody to ask,
# so the only non-interactive path is an explicit --all.
if [[ ! -t 0 ]] && ! $ASSUME_YES; then
  fail "no terminal to prompt on. Re-run with --all to accept every offered repo,
       optionally narrowed with --only clog,pm — nothing is installed by default."
fi

info "Checking prerequisites..."
for bin in bash git; do
  command -v "$bin" >/dev/null 2>&1 || fail "$bin is required."
  say "$bin: $(command -v "$bin")"
done
command -v gh >/dev/null 2>&1 && say "gh: $(command -v gh)" || warn "gh not found — needed for the GitHub-facing skills."
say "clone root: $ROOT"
say "skills dir: $SKILLS_DIR"

# Validation and selection must agree, so both split on comma only. Splitting on
# whitespace here let '--only "clog pm"' validate and then match nothing.
if [[ -n "$ONLY" ]]; then
  IFS=',' read -ra _only_check <<< "$ONLY"
  _matched=0
  for w in "${_only_check[@]+"${_only_check[@]}"}"; do
    case "${w// /}" in
      "") ;;
      clog|dev-prompter|orchestrate|pm) _matched=$((_matched + 1)) ;;
      *) fail "--only: unknown repo '$w' (valid: clog, dev-prompter, orchestrate, pm)" ;;
    esac
  done
  (( _matched > 0 )) || fail "--only matched no repos (valid: clog, dev-prompter, orchestrate, pm)"
fi

# jq is checked before anything is installed rather than inside pm, so a jq-less run
# cannot get three repos deep and then abort.
if ! command -v jq >/dev/null 2>&1; then
  if selected pm; then
    fail "pm requires jq. Install it (brew install jq) and re-run, or use --only to skip pm."
  fi
  warn "jq not found — clog's retro skills use it."
else
  say "jq: $(command -v jq)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────────
# On a trap so a mid-run abort still reports what already landed and what is left to
# do. Without it a failure on the last repo threw away every earlier repo's notes.
SUMMARY_PRINTED=false
summary() {
  $SUMMARY_PRINTED && return 0
  SUMMARY_PRINTED=true
  info "Done."
  if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    say "Installed: ${INSTALLED[*]}"
  else
    say "Installed: nothing"
  fi
  [[ ${#SKIPPED[@]} -gt 0 ]] && say "Skipped:   ${SKIPPED[*]}"
  [[ ${#FAILED[@]}  -gt 0 ]] && say "Failed:    ${FAILED[*]}"
  if [[ ${#PARTIAL[@]} -gt 0 ]]; then
    say "Partial:"
    for p in "${PARTIAL[@]}"; do echo "    - $p"; done
  fi

  if [[ ${#NOTES[@]} -gt 0 ]]; then
    echo ""
    say "Next steps:"
    for n in "${NOTES[@]}"; do echo "    - $n"; done
  fi

  echo ""
  if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    say "Restart your Claude Code session so it re-scans ${SKILLS_DIR}."
    say "docs/ONBOARDING.md is the how-to; /toolkit-setup walks you through it in a session."
  fi
  echo ""
}
trap summary EXIT

# ── Main loop ───────────────────────────────────────────────────────────────────
# One repo's failure never stops the others: each is independent, and a half-run that
# silently drops the rest is worse than one that reports what it could not do.
for name in "${ORDER[@]}"; do
  selected "$name" || continue

  info "$name — $(repo_blurb "$name")"
  if ! prompt_yn "Install ${name}?" "y"; then
    say "skipped."
    SKIPPED+=("$name")
    continue
  fi

  if ! ensure_clone "$name"; then
    FAILED+=("$name")
    continue
  fi
  dir="$RESOLVED_DIR"

  ok=true
  case "$name" in
    clog)         install_clog "$dir"         || ok=false ;;
    dev-prompter) install_dev_prompter "$dir" || ok=false ;;
    orchestrate)  install_orchestrate "$dir"  || ok=false ;;
    pm)           install_pm "$dir"           || ok=false ;;
  esac

  if $ok; then
    INSTALLED+=("$name")
  else
    FAILED+=("$name")
  fi
done
