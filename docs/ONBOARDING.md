# Onboarding — zero to the full loop in four weeks

You can install all four repos in ten minutes. **Don't.** Each one changes a habit, and
four habit changes at once is how a toolkit becomes shelfware.

This is a four-week path. Each week adds one piece to a loop that already works without
it, and ends with a **checkpoint** — a concrete signal you're getting value, not just
running commands. If a checkpoint fails, stay another week. Nothing downstream needs you
to move on.

If you'd rather just install everything: `./install.sh --all`, then read
[INTEGRATION.md](INTEGRATION.md) and skip this file.

---

## Before you start

```bash
command -v bash git jq     # required
command -v gh              # needed for the GitHub-facing bits
```

You should already be using Claude Code day to day. If you're evaluating Claude Code
itself, come back to this after — the toolkit assumes the base workflow is familiar.

---

## Week 1 — clog

**The habit:** write one line about what you just did, before you move to the next thing.

### Day 1 — install

```bash
./install.sh --only clog
```

This clones clog, runs its `setup.sh` (which detects your AI tools, writes
`~/.config/clog/config.yaml`, symlinks the skills, and registers the Claude Code
`PostToolUse` hooks), and puts `clog` on your PATH.

Then open `~/.config/clog/config.yaml` and set **`log_root`** to somewhere you'll
actually look. Leave everything else alone for now.

### Days 1–3 — log manually, badly

Don't aim for completeness. Log the three things that hurt most when you lose them:

```bash
clog DECISION "chose X over Y because Z"
clog FOLLOWUP "the thing I'll forget by Thursday"
clog LEARNING "why that attempt failed" --family tooling --kpi failure
```

The commit/push/PR hooks fire on their own — you don't log those.

### Day 3 — turn on Ledger

```bash
cat ~/Code/clog/persona/PERSONA.md >> ~/.claude/CLAUDE.md
```

Ledger makes any session proactively log-aware: it watches tool calls and flags
unlogged state-changes inline. This is what moves you from "remembering to log" to
"being reminded." (clog's `setup.sh` offers to do this for you — say yes then and skip
this step.)

### Day 5 — the first retro

```
/clog-sweep     (audit mode — find what you missed, don't backfill yet)
/clog-week
```

### ✅ Checkpoint

**Read your `clog-week` report. Does it tell you something you'd already forgotten?**

If yes, the habit is working — go to week 2. If the report is thin or generic, your
entries are too vague. Spend another week writing *why*, not *what*: `"use yq with a
grep fallback — avoids a mandatory dep"` beats `"updated config parsing"`.

---

## Week 2 — dev-prompter

**The habit:** state the contract before you delegate, and review before you trust.

### Day 1 — install

```bash
./install.sh --only dev-prompter
```

This symlinks the six skills plus `pr-review` into `~/.claude/skills/`, and installs
`agents/personas.md`. **If you already maintain a `~/.claude/agents/personas.md`, the
installer will not overwrite it** — it warns and leaves yours in place. Merge the *Task
Personas* table in by hand.

### Days 1–3 — one command only

Use `/dev-sa-q` and nothing else. It's the lowest-commitment surface: one-shot subagent,
no review, protects your main session from token-heavy reads.

```
/dev-sa-q find every call site of processPayment across this repo
```

Watch what it does with the 4-part contract — **model / persona / request / deliverable**.
The deliverable line is the one most people under-specify; notice how much the result
improves when it's exact.

### Days 3–5 — add the review step

Drop the `-q` and use `/dev-sa` on a change that actually touches files. It runs
`/pr-review` afterward: five lenses (Saboteur, New Hire, Security Auditor, Test-coverage,
Simplify), severity-ranked, advisory only.

Then try `/pr-review` standalone on a diff you were about to push anyway.

### ✅ Checkpoint

**Has `/pr-review` caught one real thing you'd have shipped?**

One is enough. If it hasn't after a week of real changes, you're likely running it on
changes too small to warrant it — point it at your largest pending diff before deciding
it isn't earning its place.

Also confirm the seam is live: after a `/dev-sa` run, `grep LEARNING` today's clog file.
You should see the learn step's entry. If not, `clog` isn't on PATH from that context.

---

## Week 3 — orchestrate

**The habit:** for big work, write the intent down *first*, and read the retro after.

### Day 1 — install and configure

```bash
./install.sh --only orchestrate
```

Then two things the installer deliberately leaves to you:

```bash
cd ~/Code/orchestrate

# 1. artifact_root — where runs land. Point it at your notes.
$EDITOR config.json

# 2. Copy a recipe and its three agents out of the examples
cp recipes/code-writer-once.example.json recipes/local/code-writer-once.json
cp prompts/agents/writer.example.md   prompts/agents/local/writer.md
cp prompts/agents/reviewer.example.md prompts/agents/local/reviewer.md
cp prompts/agents/retro.example.md    prompts/agents/local/retro.md
```

**Now edit those three agent files.** They ship with `[TODO]` placeholders for persona
and domain. A run **fast-fails** if a resolved agent still has one — this is intentional,
not a bug. Write the persona you'd actually want: *"a senior Go backend engineer who
treats every dependency as a liability"* beats *"a helpful assistant."*

Confirm the clog seam picked itself up: `config.json`'s `clog.enabled` should stay
`null` (auto-detect), and clog is already on your PATH from week 1.

### Day 2 — the first run

Pick something **genuinely too big for `/dev`** — multi-file, you expect pushback. That
is the whole point; running orchestrate on a small change teaches you it's heavy, which
you already know.

```
/orchestrate code-writer-once "add rate limiting to the payments API"
```

It asks three intake questions, writes `brief.md`, shows you a summary, waits for your
confirm, then dispatches writer → reviewer → retro.

### Day 3 — read the retro, not just the diff

`{artifact_root}/runs/<run-id>/retro.md`. This is the part everyone skips and it's where
the value is. The retro runs even when the run fails — **especially** read that one.

### ✅ Checkpoint

**Did the retro tell you something the diff didn't?**

If the retro reads like a restatement of the changes, your `brief.md` was too thin —
acceptance criteria were vague, so there was nothing concrete to reflect against. Run
`/orchestrate-brief` first next time to get explicit file scoping and sharper criteria.

---

## Week 4 — pm

**The habit:** open and close sessions deliberately, so tomorrow-you starts warm.

pm goes last on purpose. `/pm-generate` audits your installed skills and active MCP
servers and builds a tool registry around what it finds — running it now means it can
offer you clog's and dev-prompter's skills as links. Run it first and you'd re-run it
anyway.

### Day 1 — generate your skill set

```bash
./install.sh --only pm
```

Then in Claude Code:

```
/pm-generate
```

It walks you through each capability group — meetings, calendar, email, tasks, todo,
logs, github, notes — and for each asks: include it? what do you want to **name** it?
which provider backs it? where do its notes go? which skills link to it?

**Answer `none` freely.** An undefined tool degrades gracefully — the briefing says the
capability is unavailable rather than fabricating data. A registry with three honest
tools beats one with eight aspirational ones.

> **The one thing to get right:** when it reaches the **logs** group, set the provider to
> **`clog`**. The shipped example config uses the placeholder `logTool`, and if that
> value survives into your real config the slot silently resolves to nothing. See the
> naming gotcha in [INTEGRATION.md](INTEGRATION.md#seam-1--clog-is-the-shared-write-target).

Verify:

```bash
jq '.tools' ~/.config/pm/config.json
```

### Day 2 — onboard one project

Pick your **longest-running** project — the one you context-switch away from and lose
the thread on. That's where handoffs pay.

```
cd <that project>
/pm-init
```

It scaffolds `.pm/config.json`, `CONTEXT.md`, `CALENDAR.md`, `meetings.jsonl`, and flows
straight into `/pm-start`.

### Days 2–5 — run the lifecycle

```
/pm-start     once, at session open      — live sync, full briefing
/pm-status    anytime, rerunnable        — cache-only, no network
/pm-end       when you stop              — handoff block into LAST-SESSION.md
```

Hand-populate `collaborators` in `.pm/config.json` as you go — it's a local lookup index
so agents can resolve a teammate's handle without an MCP call. It is never used to
message anyone.

### ✅ Checkpoint

**Open a session with `/pm-start` after two days away. Do you know where you left off
without re-reading the diff?**

If not, your `/pm-end` handoffs are too terse. The blocks want *current state / open
threads / next-up / blockers* — the next-up line is the one that does the work.

---

## You're done — the loop closes

Now run the thing that makes the whole toolkit compound:

```
/clog-lessons
```

It reads your `LEARNING` entries — the ones the `/dev` family, orchestrate, and your own
manual logging have been accumulating for four weeks — clusters them by `family` + `kpi`,
and proposes **concrete diffs** to your `CLAUDE.md` and skill files.

It never auto-applies. You read the diffs and take what's right.

That's the loop: the system that improves your prompts is reading data you produced as a
side effect of working.

### A weekly rhythm that works

```
Daily     /pm-start … work … /pm-end
Friday    /clog-sweep (audit) → /clog-sweep (backfill) → /clog-lessons → /clog-week
```

---

## Troubleshooting

**A slash command doesn't appear.** Confirm the symlink exists under
`~/.claude/skills/`, then restart the Claude Code session — skills are scanned at start.

**`/orchestrate` fast-fails on `[TODO]`.** A resolved agent still has a placeholder in
its persona line or work step. Edit `prompts/agents/local/<name>.md`, or run
`/orchestrate-agent` for a guided walkthrough.

**pm's briefing says a capability is unavailable.** That's the graceful-degradation path,
not an error — the named tool has no provider, or the provider is `none`/blank. Check
`jq '.tools' ~/.config/pm/config.json`; re-run `/pm-generate` to change a mapping.

**Log entries stopped appearing.** Check `CLOG_DISABLE` isn't still exported from a CI
or automation run: `echo $CLOG_DISABLE` → `unset CLOG_DISABLE`.

**An installer says "already exists — skipping."** Working as designed; none of them
overwrite. Remove the target under `~/.claude/skills/` by hand and re-run to relink.

**`/dev-tab` errors.** It needs `herdr` and `HERDR_ENV=1`. `/dev`, `/dev-sa`, and
`/dev-sa-q` have no herdr dependency — use those.
