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
# Two preview modes, deliberately separate:
#   --dry-run  inert and local. Prints what this script would do and runs nothing.
#   --preview  additionally runs each tool's own --dry-run, which means EXECUTING code
#              from those repos. Better preview, real trust cost — hence opt-in.
#
# Usage: ./install.sh [--all] [--dry-run|--preview] [--root DIR] [--only a,b,c]
#                     [--ref TAG|SHA] [--help]

set -euo pipefail

# This repo's own root, used to link the walkthrough skill. The ${...:-$0} fallback
# keeps `cat install.sh | bash` from aborting on an unbound BASH_SOURCE under set -u.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)" || SELF="$PWD"

ROOT="${TOOLKIT_ROOT_DIR:-$HOME/Code}"
SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
AGENTS_DIR="${CLAUDE_AGENTS_DIR:-$HOME/.claude/agents}"
DRY_RUN=false
PREVIEW=false
ASSUME_YES=false
ONLY=""
REF=""

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

# Extract owner/repo from a remote, but ONLY when the host really is github.com.
# The host must be anchored, not stripped to: a greedy "${u##*github.com/}" reduced
# https://evil.example.com/github.com/eimaj/clog to eimaj/clog, so a hostile checkout
# passed the origin check below and had its installer executed. Anything that is not
# a plain github.com remote returns empty, which can never equal an expected slug.
github_slug() {
  local u="${1%.git}"
  u="${u%/}"
  if [[ "$u" =~ ^(https://|http://|ssh://)?(git@)?github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    echo "${BASH_REMATCH[3]}/${BASH_REMATCH[4]}"
  fi
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
  --ref TAG|SHA     Check out this revision in repos this run clones, instead of
                    whatever their default branch points at. Existing clones are
                    left alone, so it does not apply to them. Either way the
                    resolved commit is printed before that repo's installer runs.
  --dry-run         Change nothing and run nothing. Prints what this script would do.
                    Safe to use on a repo you have not read yet.
  --preview         Everything --dry-run does, and additionally runs each tool's own
                    --dry-run for a fuller picture. That EXECUTES code from those
                    repos, so only use it once you trust them. Repos that are not
                    cloned yet are reported, not fetched.
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
    --preview) DRY_RUN=true; PREVIEW=true; shift ;;
    --root)    ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --root=*)  ROOT="${1#*=}"; [[ -n "$ROOT" ]] || { echo "--root needs a directory" >&2; exit 1; }; shift ;;
    --only)    ONLY="${2:?--only needs a comma-separated list}"; shift 2 ;;
    --only=*)  ONLY="${1#*=}"; [[ -n "$ONLY" ]] || { echo "--only needs a comma-separated list" >&2; exit 1; }; shift ;;
    --ref)     REF="${2:?--ref needs a tag, branch, or SHA}"; shift 2 ;;
    --ref=*)   REF="${1#*=}"; [[ -n "$REF" ]] || { echo "--ref needs a tag, branch, or SHA" >&2; exit 1; }; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

ROOT="${ROOT/#\~/$HOME}"

# $ROOT lands in git clone's positional slot, and git's option parser will happily
# read a leading dash there as a flag: --root '--template=/tmp/evil' makes git install
# hooks from that path and fire post-checkout during the clone. Reject it outright;
# every git invocation below also uses -- to end option parsing.
# Inline echo/exit rather than fail(): the helpers are not defined until below.
[[ "$ROOT" != -* ]] || { echo "ERROR: --root must be a path, not an option: $ROOT" >&2; exit 1; }

# $REF reaches git checkout's positional slot and needs the same treatment as $ROOT:
# a leading dash there is read as a flag, not a revision.
[[ "$REF" != -* ]] || { echo "ERROR: --ref must be a tag, branch, or SHA, not an option: $REF" >&2; exit 1; }

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

# Reads SELECTED, which the preflight resolves once. Repo names carry no spaces or
# glob characters, so the substring test is exact.
selected() {
  case " ${SELECTED[*]+${SELECTED[*]}} " in *" $1 "*) return 0 ;; esac
  return 1
}

# True when two paths name the same directory after resolving symlinked components,
# so a checkout reached via /tmp and via /private/tmp is recognised as one place.
same_dir() {
  local a b
  a="$(cd -P "$1" 2>/dev/null && pwd -P)" || return 1
  b="$(cd -P "$2" 2>/dev/null && pwd -P)" || return 1
  [[ "$a" == "$b" ]]
}

# Symlink a directory into place, clobbering nothing. A real directory is a
# hand-maintained skill; a symlink pointing somewhere else is someone else's install.
# Only a link this script already owns (same target) is touched, which keeps re-runs
# idempotent. Returns non-zero on refusal or failure so the caller can report it.
link_dir() {
  local src="$1" dst="$2" current
  # ln -sfn will happily create a link to nothing, and the result is a live entry in
  # the skills dir that resolves to whatever someone later puts at that path.
  if [[ ! -d "$src" ]]; then
    warn "no such directory: $src — refusing to create a dangling link at $dst"
    return 1
  fi
  if [[ -L "$dst" ]]; then
    current="$(readlink "$dst")"
    if [[ "$current" == "$src" ]] || same_dir "$current" "$src"; then
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
  # run() executes nothing in dry-run and still returns 0, so an unconditional
  # "linked:" here asserted a symlink that was never created — and the walkthrough
  # shows this output to the user as the preview they consent from.
  if $DRY_RUN; then
    say "would link: $dst -> $src"
  else
    say "linked: $dst -> $src"
  fi
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
    local origin expected actual
    origin="$(git -C "$dest" remote get-url origin 2>/dev/null || echo "")"
    expected="$(github_slug "$url")"
    actual="$(github_slug "$origin")"
    # An unresolvable expected slug would make every comparison pass on empty==empty.
    [[ -n "$expected" ]] || fail "internal: could not parse the expected remote for $name"
    if [[ "$actual" != "$expected" ]]; then
      warn "$dest is a git repo, but its origin is '${origin:-none}' rather than $url"
      # A fork is a legitimate reason to say yes, so a human gets the choice. An
      # unattended run does not — it skips rather than executing an unknown repo.
      if $ASSUME_YES || ! prompt_yn "Run the installer in $dest anyway?" "n"; then
        warn "skipping $name — nothing in that directory was run"
        return 1
      fi
    fi
    say "found existing clone: $dest (left untouched — pull it yourself if you want)"
    # Leaving existing clones alone is deliberate, so --ref has nothing to act on here.
    # Saying so is better than pinning silently failing.
    [[ -z "$REF" ]] || warn "--ref $REF not applied — an existing clone is left as it is"
  elif [[ -e "$dest" ]]; then
    warn "$dest exists but is not a git clone — skipping $name"
    return 1
  else
    run mkdir -p -- "$ROOT"
    say "cloning $url -> $dest"
    if ! run git clone --quiet -- "$url" "$dest"; then
      warn "clone failed for $name"
      return 1
    fi
    # Detached on purpose: a pinned install should not look like it is on a branch
    # that a later pull would move.
    if [[ -n "$REF" ]] && ! run git -C "$dest" checkout --quiet --detach "$REF"; then
      warn "could not check out --ref $REF in $dest"
      return 1
    fi
  fi

  # The origin check above says WHERE this code came from. Nothing so far says WHAT it
  # says, and the next step executes it — so name the exact commit first.
  if [[ -d "$dest/.git" ]]; then
    local sha
    if sha="$(git -C "$dest" rev-parse --short HEAD 2>/dev/null)"; then
      say "commit: $sha"
    else
      warn "could not resolve HEAD in $dest"
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
# Plain --dry-run runs NOTHING: the whole point of a dry run is to be safe on a repo
# you have not read, and delegating the preview to an untrusted installer would make
# the cautious path the dangerous one. --preview opts into executing each tool's own
# --dry-run for a fuller picture, and says so up front.
run_installer() {
  local script="$1"; shift
  if $DRY_RUN && ! $PREVIEW; then
    say "[dry-run] would run: bash $script $*"
    return 0
  fi
  if [[ ! -f "$script" ]]; then
    if $PREVIEW; then
      warn "not cloned yet, so there is nothing to preview: $script"
      warn "run without --preview first, or clone it yourself"
    else
      warn "expected installer not found: $script"
    fi
    return 1
  fi
  bash "$script" "$@"
}

# An exact copy of the three probes in clog's own detect_existing_install. It is a
# copy, so it CAN drift — re-check it against clog/setup.sh if that function changes.
# When the two disagree, clog's setup exits telling the user to re-run with a flag
# this script never exposed, and clog fails on the first repo.
clog_installed() {
  [[ -f "$HOME/.claude/hooks/clog.sh" ]] && return 0
  [[ -n "${CLOG_BIN:-}" ]] && return 0
  [[ -n "${AI_LOG_ROOT:-}" ]] && return 0
  return 1
}

install_clog() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  # clog gates --migrate behind an explicit opt-in because it rewrites an existing
  # install. Answering yes on the user's behalf is exactly what that gate exists to
  # prevent, so --all declines it rather than auto-consenting.
  if clog_installed; then
    say "an existing clog install was detected."
    if $ASSUME_YES; then
      say "--all does not auto-consent to rewriting it; re-run interactively to migrate"
    elif prompt_yn "Pass --migrate so clog's setup can update it (it backs up first)?" "y"; then
      args+=(--migrate)
    else
      say "continuing without --migrate — clog's setup will stop and install nothing"
    fi
  fi
  # `|| return 1` is load-bearing: a function returns its LAST command's status, so
  # ending on NOTES+=() reported every failed sub-installer as a success.
  run_installer "$dir/setup.sh" "${args[@]+"${args[@]}"}" || return 1
  NOTES+=("clog: set log_root in ~/.config/clog/config.yaml, and confirm 'command -v clog' resolves (its CLI lands in ~/.local/bin)")
}

# dev-prompter ships no installer, so the documented symlink install lives here.
# _devkit is the shared base the five /dev skills read, not a slash command; it is
# linked alongside them because they resolve it by path.
install_dev_prompter() {
  local dir="$1" s refused=0
  # One list, used for both the loop and the counts below — a hardcoded total silently
  # breaks the all-refused check the moment a skill is added or removed.
  local skills=(_devkit dev dev-tab dev-sa dev-sa-q dev-tab-q pr-review)
  run mkdir -p -- "$SKILLS_DIR" "$AGENTS_DIR"
  for s in "${skills[@]}"; do
    # Collisions and missing sources are survivable and must not abort the remaining
    # repos, so refusals are counted and reported rather than raised. link_dir
    # rejects a missing source itself.
    link_dir "$dir/skills/$s" "$SKILLS_DIR/$s" || refused=$((refused + 1))
  done

  local personas="$AGENTS_DIR/personas.md"
  if [[ -e "$personas" ]]; then
    say "$personas already exists — left as-is"
    NOTES+=("dev-prompter: if you want its task personas, merge them from $dir/agents/personas.md into $personas")
  elif [[ ! -f "$dir/agents/personas.md" ]]; then
    warn "$dir/agents/personas.md is missing upstream — skipping personas"
    refused=$((refused + 1))
  elif run cp "$dir/agents/personas.md" "$personas"; then
    say "installed: $personas"
  else
    warn "failed to copy personas into $personas"
    refused=$((refused + 1))
  fi

  # Nothing landing at all is a failure, not a caveat.
  if (( refused > ${#skills[@]} )); then
    warn "nothing could be installed into $SKILLS_DIR"
    return 1
  fi
  if (( refused == ${#skills[@]} )); then
    warn "no skills could be linked into $SKILLS_DIR"
    return 1
  fi
  if (( refused > 0 )); then
    PARTIAL+=("dev-prompter: $refused of $(( ${#skills[@]} + 1 )) items skipped — the rest are in place")
  fi
}

install_orchestrate() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  run_installer "$dir/install.sh" "${args[@]+"${args[@]}"}" || return 1
  NOTES+=("orchestrate: set artifact_root in $dir/config.json")
  NOTES+=("orchestrate: copy a recipe and the agents it names into recipes/local/ and prompts/agents/local/ — code-writer's three run as shipped; feature-scoper's carry [TODO] personas and fast-fail until filled in")
}

install_pm() {
  local dir="$1" args=()
  $DRY_RUN && args+=(--dry-run)
  run_installer "$dir/install.sh" "${args[@]+"${args[@]}"}" || return 1
  NOTES+=("pm: run /pm-generate in Claude Code — and when it reaches the 'logs' group, set the provider to 'clog' (the example config's placeholder is 'logTool')")
}

# ── Preflight ───────────────────────────────────────────────────────────────────
echo "toolkit installer — clog, dev-prompter, orchestrate, pm"
echo "clones from github.com/eimaj and runs each repo's own installer."
if $PREVIEW; then
  echo "(preview — nothing is written, but each tool's own installer IS executed"
  echo " with its --dry-run flag. That runs code from those repos.)"
elif $DRY_RUN; then
  echo "(dry-run — nothing is written and no installer is executed)"
fi

# Consent cannot be inferred from silence. Without a terminal there is nobody to ask,
# so the only non-interactive path is an explicit --all.
if [[ ! -t 0 ]] && ! $ASSUME_YES; then
  # The wording matters: an earlier version called --only "optional" here, and that
  # steered unattended callers into installing all four when they wanted one.
  fail "no terminal to prompt on, so consent cannot be collected.

       --all stands in for typed consent, and on its own it accepts ALL FOUR repos.
       Pair it with --only to say what you actually want:

         ./install.sh --all --only clog
         ./install.sh --all --only clog,dev-prompter

       Use --all by itself only if you genuinely want every repo."
fi

info "Checking prerequisites..."
for bin in bash git; do
  command -v "$bin" >/dev/null 2>&1 || fail "$bin is required."
  say "$bin: $(command -v "$bin")"
done
command -v gh >/dev/null 2>&1 && say "gh: $(command -v gh)" || warn "gh not found — needed for the GitHub-facing skills."
say "clone root: $ROOT"
say "skills dir: $SKILLS_DIR"

# --only is resolved into SELECTED once, here, and only read afterwards. Validating and
# matching in two places meant they could disagree on the separator, and they did:
# '--only "clog pm"' passed validation and then matched nothing. Valid names come from
# ORDER, so adding a repo cannot leave a stale list behind.
SELECTED=("${ORDER[@]}")
if [[ -n "$ONLY" ]]; then
  SELECTED=()
  IFS=',' read -ra _want <<< "$ONLY"
  for w in "${_want[@]+"${_want[@]}"}"; do
    w="${w// /}"
    [[ -n "$w" ]] || continue
    case " ${ORDER[*]} " in
      *" $w "*) SELECTED+=("$w") ;;
      *) fail "--only: unknown repo '$w' (valid: ${ORDER[*]})" ;;
    esac
  done
  (( ${#SELECTED[@]} > 0 )) || fail "--only matched no repos (valid: ${ORDER[*]})"
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
summary() {
  local verb="Installed"
  $DRY_RUN && verb="Would install"
  info "Done."
  if [[ ${#INSTALLED[@]} -gt 0 ]]; then
    say "${verb}: ${INSTALLED[*]}"
  else
    say "${verb}: nothing"
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
  if [[ ${#INSTALLED[@]} -gt 0 ]] && ! $DRY_RUN; then
    say "Restart your Claude Code session so it re-scans ${SKILLS_DIR}."
    say "docs/ONBOARDING.md is the how-to; /toolkit-setup walks you through it in a session."
  fi
  echo ""
}
trap summary EXIT

# Ctrl-C must actually stop the run. Without this the interrupted installer's death
# was swallowed and the remaining repos installed anyway — the opposite of what the
# person pressing Ctrl-C asked for. Exiting here still fires the EXIT trap, so the
# summary reports whatever already landed.
on_interrupt() {
  echo "" >&2
  warn "interrupted — stopping here."
  exit 130
}
trap on_interrupt INT

# ── The walkthrough skill ───────────────────────────────────────────────────────
# Linked regardless of which repos were chosen: it is this repo's own skill, and it is
# what a person runs to be walked through the rest.
info "toolkit-setup — the interactive walkthrough (/toolkit-setup)"
if prompt_yn "Link the walkthrough skill into ${SKILLS_DIR}?" "y"; then
  run mkdir -p -- "$SKILLS_DIR"
  if link_dir "$SELF/skills/toolkit-setup" "$SKILLS_DIR/toolkit-setup"; then
    NOTES+=("run /toolkit-setup in Claude Code to be walked through the tools you picked")
  fi
else
  say "skipped — docs/ONBOARDING.md has the same path to follow by hand."
fi

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

# A broken install must be visible to CI, agents, and && chains — not just to a reader
# of the summary. The EXIT trap still prints before this takes effect.
(( ${#FAILED[@]} == 0 )) || exit 1
