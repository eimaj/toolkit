# Onboarding — the how-to

Four tools, four stages. Each stage installs one, uses it for real, and ends with a
**checkpoint** that says whether the next one is worth it — plus an **off-ramp**,
because stopping after one is a perfectly good outcome.

A week per stage is a comfortable pace, not a schedule. Go faster if it's landing.

Every step below is `RUN` → `VERIFY` → `EXPECT`, so this doubles as the script an agent
follows. `/toolkit-setup` walks the same path interactively and asks before each step.

> `$TK` below is wherever you cloned the repos — `~/Code` unless you passed `--root`.
> `export TK=~/Code` once and the commands paste cleanly.

---

## Start where your problem is

You do not have to start at clog, and you do not have to finish.

| What's actually bothering you | Start at | Need anything else? |
| --- | --- | --- |
| Losing the *why* when a session compacts or clears | [clog](#1--clog) | no |
| Delegating badly; wanting a real review before you trust a change | [dev-prompter](#2--dev-prompter) | clog is optional — only the learn step uses it |
| Big changes with no paper trail | [orchestrate](#3--orchestrate) | clog optional; it degrades to plain JSONL |
| Losing the thread on long projects across sessions | [pm](#4--pm) | clog optional; fills pm's `logs` slot |

The order below is the one that goes down easiest if you want all four — each stage
adds a step to a loop that already works without it.

## Before you start

```bash
command -v bash && command -v git    # required
command -v jq                        # required for pm, used by clog's retro skills
```

Missing `jq`: `brew install jq`. pm won't install without it, and clog's `/clog-week`
and `/clog-sweep` need it too. Missing `git` or `bash`: stop here.

---

## 1 — clog

**The habit:** write one line about what happened, before moving to the next thing.

### Install

```bash
RUN:    cd $TK/toolkit && ./install.sh --only clog
VERIFY: command -v clog
EXPECT: a path (usually ~/.local/bin/clog)
```

`command -v clog` printing nothing is the most common first-run snag — clog's setup
puts the CLI in `~/.local/bin` and only *warns* if that isn't on your PATH. Fix:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh
```

Then set `log_root` to somewhere you'll actually look:

```bash
RUN:    ${EDITOR:-vi} ~/.config/clog/config.yaml
VERIFY: grep '^log_root:' ~/.config/clog/config.yaml
EXPECT: a path you recognise
```

### Use it for a few days

Don't aim for completeness. Log the three things that hurt most when they're lost:

```bash
clog DECISION "chose X over Y because Z"
clog FOLLOWUP "the thing you'll forget by Thursday"
clog LEARNING "why that attempt failed" --family tooling --kpi failure
```

Commits, pushes, and PRs are logged by hooks — don't log those by hand.

```bash
VERIFY: ls "$(grep '^log_root:' ~/.config/clog/config.yaml | awk '{print $2}' | tr -d '"' | sed "s|^~|$HOME|")"
EXPECT: a YYYYMMDD.jsonl file with today's date
```

### Turn on Ledger

Makes any session proactively log-aware — it flags unlogged state-changes inline
instead of leaving you to remember. clog's `setup.sh` offers this; if you declined:

```bash
RUN:    less $TK/clog/persona/PERSONA.md      # read it first — it edits agent behaviour
RUN:    cat $TK/clog/persona/PERSONA.md >> ~/.claude/CLAUDE.md
VERIFY: grep -c '^# Ledger' ~/.claude/CLAUDE.md
EXPECT: exactly 1 — a 2 means the block was appended twice; delete the duplicate
```

### Retro

```
/clog-sweep    then say "audit my log"    → finds gaps, changes nothing
/clog-week
```

`/clog-sweep` picks its mode from what you ask for, not a flag: *"audit my log"* /
*"clog gaps"* to report, *"clog it"* / *"backfill clogs"* to fill them in.

### ✅ Checkpoint

**Does the `clog-week` report tell you something already forgotten?**

If yes, the habit is working. If the report reads thin, the entries are too vague —
another few days writing *why* rather than *what*. `"use yq with a grep fallback —
avoids a mandatory dep"` beats `"updated config parsing"`.

**🚏 Off-ramp:** if session memory was the whole problem, you're done. The rest of this
document is for people who also want the delegation, review, and project layers.

---

## 2 — dev-prompter

**The habit:** state the contract before delegating; review before trusting.

### Install

```bash
RUN:    cd $TK/toolkit && ./install.sh --only dev-prompter
VERIFY: ls ~/.claude/skills | grep -Ec '^(dev|dev-sa|dev-sa-q|dev-tab|dev-tab-q|pr-review|_devkit)$'
EXPECT: 7
```

Seven directories: five `/dev` skills, `pr-review`, and `_devkit` — a shared base the
others read, not a slash command. Collisions are skipped, not overwritten, and named in
the installer's summary; check there if the count is short.

An existing `~/.claude/agents/personas.md` is left alone. To pick up the task personas,
merge them yourself from `$TK/dev-prompter/agents/personas.md`.

Restart your Claude Code session — skills are scanned at start.

### Start with one command

`/dev-sa-q` is the lowest-commitment surface: one-shot subagent, no review, keeps
token-heavy reads out of your main session.

```
/dev-sa-q find every call site of processPayment across this repo
```

Watch what it does with the four-part contract — **model / persona / request /
deliverable**. The deliverable line is the one most under-specified; being exact about
it changes the result more than anything else.

### Add the review step

Drop the `-q` on a change that touches files. `/dev-sa` runs `/pr-review` afterward —
five lenses, severity-ranked, advisory, never posts and never blocks.

```
/dev-sa <a change worth reviewing>
```

Then try `/pr-review` standalone on a diff you were about to push anyway.

```bash
VERIFY: grep -c LEARNING "$(grep '^log_root:' ~/.config/clog/config.yaml | awk '{print $2}' | tr -d '"' | sed "s|^~|$HOME|")"/$(date +%Y%m%d).jsonl
EXPECT: 1 or more once a /dev cycle has run today. "No such file" means no entries
        yet, not a failure. Skip this if you didn't install clog.
```

### ✅ Checkpoint

**Has `/pr-review` caught one real thing that would have shipped?**

One is enough. If nothing after a week of real changes, it's likely running on changes
too small to warrant it — point it at your largest pending diff before writing it off.

**🚏 Off-ramp:** delegation and review stand on their own. Stages 3 and 4 are for
multi-phase work and long-running projects respectively.

---

## 3 — orchestrate

**The habit:** for big work, write the intent down first and read the retro after.

### Install and configure

```bash
RUN:    cd $TK/toolkit && ./install.sh --only orchestrate
VERIFY: ls ~/.claude/skills | grep -Ecx 'orchestrate|orchestrate-spec|orchestrate-recipe|orchestrate-agent'
EXPECT: 4
```

Two things the installer deliberately leaves to you.

```bash
RUN:    $EDITOR $TK/orchestrate/config.json     # set artifact_root
VERIFY: grep artifact_root $TK/orchestrate/config.json
EXPECT: a path you chose
```

Leave `clog.enabled` at `null` — it auto-detects.

```bash
RUN: cd $TK/orchestrate
RUN: cp recipes/code-writer-once.example.json recipes/local/code-writer-once.json
RUN: cp prompts/agents/writer.example.md   prompts/agents/local/writer.md
RUN: cp prompts/agents/reviewer.example.md prompts/agents/local/reviewer.md
RUN: cp prompts/agents/retro.example.md    prompts/agents/local/retro.md
```

Those three agents run as shipped. Their personas are generic, though, and a specific
one is worth more — *"a senior Go backend engineer who treats every dependency as a
liability"* beats *"a helpful assistant"*. Edit them or don't; the run works either way.

`[TODO]` placeholders only appear in the `feature-scoper` recipe's agents
(`product-lead`, `technical-writer`), and a run fast-fails while any remain. That's
intentional, not a bug.

```bash
VERIFY: grep -l '\[TODO' $TK/orchestrate/prompts/agents/local/*.md 2>/dev/null | wc -l
EXPECT: 0 for the code-writer set
```

### First run

Pick something genuinely too big for `/dev` — multi-file, where you expect pushback.
Running orchestrate on a small change only teaches you it's heavy, which the README
already said.

```
/orchestrate code-writer-once "add rate limiting to the payments API"
```

Three intake questions, a `brief.md`, a summary, your confirm, then writer → reviewer →
retro.

### Read the retro

```bash
VERIFY: ls "$(grep -o '"artifact_root"[^,]*' $TK/orchestrate/config.json | cut -d'"' -f4 | sed "s|~|$HOME|")"
EXPECT: a run directory containing brief.md, learnings.md, retro.md
```

`retro.md` is the part that gets skipped and the part that carries the value. It runs
even when the run fails — especially read that one.

### ✅ Checkpoint

**Did the retro say something the diff didn't?**

If it reads like a restatement of the changes, the `brief.md` was too thin — vague
acceptance criteria leave nothing concrete to reflect against. Run `/orchestrate-spec`
first next time for explicit file scoping and sharper criteria.

**🚏 Off-ramp:** stage 4 is only worth it for projects you return to across many
sessions. One-off work doesn't need it.

---

## 4 — pm

**The habit:** open and close sessions deliberately, so the next one starts warm.

pm goes last on purpose: `/pm-generate` audits your installed skills and MCP servers
and builds a tool registry from what it finds. Run it before the others and it can't
offer clog's or dev-prompter's skills as links.

### Generate your skill set

```bash
RUN:    cd $TK/toolkit && ./install.sh --only pm
VERIFY: ls ~/.claude/skills | grep -c '^pm-generate'
EXPECT: 1
```

Restart the session, then:

```
/pm-generate
```

It walks each capability group — meetings, calendar, email, tasks, todo, logs, github,
notes — asking whether to include it, what to **name** it, which provider backs it,
where its notes go, and which skills link to it.

**Answer `none` freely.** An undefined tool degrades gracefully: the briefing says the
capability is unavailable rather than inventing data.

> **When it reaches the `logs` group, set the provider to `clog`.** The shipped example
> config uses the placeholder `logTool`, and if that value survives into your real
> config the slot resolves to nothing and your log data quietly vanishes from every
> briefing. See the naming gotcha in
> [INTEGRATION.md](INTEGRATION.md#seam-1--clog-is-the-shared-write-target).

```bash
VERIFY: jq -r '.tools | to_entries[] | "\(.key) -> \(.value.provider)"' ~/.config/pm/config.json
EXPECT: real provider names; no "logTool", no "todoApp"
```

Restart the session again — `/pm-generate` renders new skill files.

### Onboard one project

Pick the longest-running one — the project you context-switch away from and lose the
thread on. That's where handoffs pay.

`cd` into that project, then run `/pm-init` **in Claude Code** — it's a skill, not a
shell command.

```bash
VERIFY: ls -d .pm/config.json CONTEXT.md CALENDAR.md meetings.jsonl reports briefs
EXPECT: all present
```

### Run the lifecycle

| Command | When | What it does |
| --- | --- | --- |
| `/pm-start` | once, at session open | live sync, full briefing |
| `/pm-status` | anytime | cache-only, no network |
| `/pm-end` | when you stop | handoff block into `LAST-SESSION.md` |

Populate `collaborators` in `.pm/config.json` by hand as you go — a local lookup index
so agents resolve a teammate's handle without an MCP call. Nobody is ever messaged
from it.

### ✅ Checkpoint

**After two days away, does `/pm-start` tell you where you left off without re-reading
the diff?**

If not, the `/pm-end` handoffs are too terse. The blocks want *current state / open
threads / next-up / blockers* — next-up does most of the work.

---

## Closing the loop

```
/clog-lessons
```

It reads the `LEARNING` entries the other three tools have been accumulating as a side
effect of working, clusters them, and proposes concrete diffs to your `CLAUDE.md` and
skills. It never auto-applies.

A rhythm that holds up:

| When | What |
| --- | --- |
| Daily | `/pm-start` … work … `/pm-end` |
| Friday | `/clog-sweep` (audit), `/clog-sweep` (backfill), `/clog-lessons`, `/clog-week` |

---

## Troubleshooting

**A slash command doesn't appear.** Confirm the symlink under `~/.claude/skills/`, then
restart the session — skills are scanned at start.

**`clog: command not found`.** `~/.local/bin` isn't on your PATH. See stage 1.

**Log entries stopped appearing.** `echo $CLOG_DISABLE` — unset it if a CI or
automation run left it exported.

**`/dev-tab` errors.** Needs [`herdr`](https://herdr.dev) and `HERDR_ENV=1`. `/dev`,
`/dev-sa`, and `/dev-sa-q` have no herdr dependency.

**The installer skipped a repo.** Check its summary: a skipped symlink means something
was already there, and a failed repo names the reason. Nothing is overwritten.
