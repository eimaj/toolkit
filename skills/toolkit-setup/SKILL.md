---
name: toolkit-setup
description: Walk someone through installing and configuring the toolkit repos — clog, dev-prompter, orchestrate, project-manager — one stage at a time, asking before each. Use when setting up the toolkit, adding one of its tools, or checking which parts are already installed.
---

# toolkit-setup

Interactive walkthrough of [docs/ONBOARDING.md](../../docs/ONBOARDING.md). That file is
the source of truth for every command; this skill drives it, verifies each step, and
stops when the person has what they came for.

## The contract

Four rules, in priority order. They override any convenience below.

1. **Ask, don't assume.** Never install, configure, or edit a file the person did not
   agree to in this session. "Set up the toolkit" is not consent to four repos.
2. **Never assume the full set.** Most people want one or two. Suggesting the rest once
   is fine; installing them is not.
3. **One stage at a time.** Install → verify → use → checkpoint → *ask whether to
   continue*. Do not chain stages.
4. **Stop means stop.** At any checkpoint, "this is enough" is a successful outcome.
   Summarise and finish. Do not re-pitch the remaining tools.

Never run `install.sh --all` — it accepts everything. Always `--only` with exactly what
was agreed.

## Step 0 — find out what's already there

Run this before asking anything; it changes what's worth offering, and it makes the
walkthrough resumable mid-way.

```bash
command -v clog >/dev/null && echo "clog: installed" || echo "clog: no"
ls ~/.claude/skills 2>/dev/null | grep -qx pr-review && echo "dev-prompter: installed" || echo "dev-prompter: no"
ls ~/.claude/skills 2>/dev/null | grep -qx orchestrate && echo "orchestrate: installed" || echo "orchestrate: no"
ls ~/.claude/skills 2>/dev/null | grep -qx pm-generate && echo "pm: installed" || echo "pm: no"
```

Also resolve where the repos live (`~/Code` unless they used `--root`) and confirm
`bash`, `git`, and — only if pm is wanted — `jq`.

## Step 1 — ask what problem they have

Do not open with a list of four tools. Ask what's actually bothering them, then map:

| What they say | Offer |
| --- | --- |
| loses context on `/clear`, autocompact, or overnight | clog |
| delegation goes badly; wants changes reviewed | dev-prompter |
| big changes with no record of what happened | orchestrate |
| loses the thread on long projects across sessions | pm |
| wants the whole loop | all four, in that order |

Confirm the list back before touching anything. If they want more than one, note that
clog goes first and pm last, and that stopping partway is fine.

## Step 2 — per-stage loop

For each agreed tool, in the order clog → dev-prompter → orchestrate → pm:

1. **Install** — `./install.sh --only <name>` from the toolkit repo.
2. **Verify** — run that stage's `VERIFY` from ONBOARDING.md and check the output
   against its `EXPECT`. Report what actually came back, not what should have.
3. **Configure** — walk the stage's decision points (below). Ask each one; never pick
   for them.
4. **Use it once** — the stage's first real command, so the checkpoint has something to
   judge.
5. **Checkpoint** — ask the stage's question. Then ask whether to continue, stop, or
   come back later. Honour the answer.

If a verify fails, fix it before moving on. The installer's summary names skipped
symlinks and failed repos — read it rather than assuming success.

### Decision points to ask, never assume

| Stage | Ask |
| --- | --- |
| clog | `log_root` location · whether to append the Ledger persona to `~/.claude/CLAUDE.md` (it changes agent behaviour globally — have them read it first) · whether `~/.local/bin` is on PATH |
| dev-prompter | whether to merge task personas into an existing `~/.claude/agents/personas.md` (never overwrite it) |
| orchestrate | `artifact_root` · which recipe · whether to write specific agent personas or keep the shipped generic ones |
| pm | every capability group in `/pm-generate` · which project to onboard first |

### Stage notes worth surfacing

- **clog** — the CLI lands in `~/.local/bin`; its setup only *warns* if that is off
  PATH. `command -v clog` returning nothing is the most common first-run snag.
- **dev-prompter** — seven directories link, not six: five `/dev` skills, `pr-review`,
  and `_devkit` (a shared base, not a slash command).
- **orchestrate** — the `code-writer` agents run as shipped. Only `feature-scoper`'s
  carry `[TODO]` placeholders, and a run fast-fails while any remain.
- **pm** — at the `logs` group the provider must be `clog`, not the example config's
  `logTool` placeholder, or the slot silently resolves to nothing.
- Skills are scanned at session start. After installing, and again after
  `/pm-generate` renders its skills, tell them to restart.

## Step 3 — finish

Summarise: what was installed, what was verified, what they declined, and the one or
two next steps that actually apply to their set. Do not describe tools they skipped.

If two or more landed, mention `/clog-lessons` — it turns the LEARNING entries the
others produce into proposed edits to their own prompts.

## Related

- [docs/ONBOARDING.md](../../docs/ONBOARDING.md) — the commands this skill runs
- [docs/INTEGRATION.md](../../docs/INTEGRATION.md) — the seams, and what degrades
  when a tool is absent
