# toolkit

Four independent Claude Code repos that compose into one working loop:
**start a session with context → route the work to the right surface → review it →
log what happened → turn the log back into better prompts.**

Each repo stands alone and is useful alone. This repo is the map of how they fit, an
installer that sets up whichever ones you want, and a how-to for picking them up at
whatever pace suits you.

Nothing here is required. Take one, take three, take the lot — the seams are built so
a missing tool degrades instead of breaking.

---

## The four

| Repo | Slash commands | Owns |
| --- | --- | --- |
| [**clog**](https://github.com/eimaj/clog) | `/clog`, `/clog-sweep`, `/clog-day`, `/clog-week`, `/clog-lessons`, `/clog-replay`, `/clog-search` | Structured JSONL session logging + retro skills. The substrate the other three write into. |
| [**dev-prompter**](https://github.com/eimaj/dev-prompter) | `/dev`, `/dev-tab`, `/dev-sa`, `/dev-sa-q`, `/dev-tab-q`, `/pr-review` | Delegating a dev task on a 4-part prompt contract (model / persona / request / deliverable), and the multi-lens review engine. |
| [**orchestrate**](https://github.com/eimaj/orchestrate) | `/orchestrate`, `/orchestrate-brief`, `/orchestrate-recipe`, `/orchestrate-agent` | Multi-agent write → review → retro runs against a brief, with auditable artifacts. |
| [**project-manager** (`pm`)](https://github.com/eimaj/project-manager) | `/pm-generate` → renders `/pm-init`, `/pm-start`, `/pm-status`, `/pm-end` | Per-project context, live session sync, and clean multi-session handoffs. |

---

## The loop

```
   ┌──────────────────────────────────────────────────────────────┐
   │                                                              │
   │   /pm-start          open the session with real context      │
   │       │              (meetings, calendar, tasks, inbox)      │
   │       ▼                                                      │
   │   route the work ─────────────────────────────┐              │
   │       │                                       │              │
   │       ▼                                       ▼              │
   │   /dev  /dev-sa  /dev-tab              /orchestrate          │
   │   one surface, one pass                brief → write →       │
   │       │                                review → retro        │
   │       ▼                                       │              │
   │   /pr-review  ◄────────────────────────────── ┘              │
   │       │        (the same review engine either way)           │
   │       ▼                                                      │
   │   clog ACTION / DECISION / CODE / LEARNING                   │
   │       │        (written throughout, not at the end)          │
   │       ▼                                                      │
   │   /pm-end            handoff block, session summary          │
   │       │                                                      │
   │       ▼                                                      │
   │   /clog-week + /clog-lessons                                 │
   │       │        the log becomes proposed edits to your        │
   │       └──────► prompts and skills ──────────────────────► ◄──┘
   │                                                              │
   └──────────────────────────────────────────────────────────────┘
```

The bit that isn't obvious: **the last step feeds the first.** `clog-lessons` reads
the `LEARNING` entries the other three tools produced as a side effect of working, and
proposes concrete diffs to your `CLAUDE.md` and skills. Nothing else in the loop has to
be instrumented for that to work — the logging already happened.

---

## How they actually connect

Four seams that actually exist:

1. **clog is the shared write target.** orchestrate logs every dispatch/join/learning to
   it (auto-detected; falls back to plain JSONL if absent). Every dev-prompter skill
   closes its cycle with a `clog` entry. pm's `logs` tool slot points at it.
2. **`/pr-review` is the single review engine.** The `/dev` family calls it directly;
   orchestrate's reviewer agent is the heavier, artifact-producing alternative for the
   same job. You don't maintain two review rubrics.
3. **pm hands briefs to orchestrate.** `/pm-end` relocates `/orchestrate-brief` output
   into the project's own `briefs_dir` and commits it, so a brief outlives the run.
4. **Everything degrades.** Each seam is optional in one direction — no tool fails
   because another is missing. See the degradation matrix in
   [docs/INTEGRATION.md](docs/INTEGRATION.md).

Full detail, plus the gotchas worth knowing before they bite:
**[docs/INTEGRATION.md](docs/INTEGRATION.md)**.

---

## Install

```bash
git clone https://github.com/eimaj/ai-toolkit ~/Code/ai-toolkit
cd ~/Code/ai-toolkit
./install.sh
```

`install.sh` is **interactive and à la carte** — it asks about each repo separately,
clones only what you say yes to, and then delegates to that repo's own installer rather
than reimplementing it. It walks them in the order clog → dev-prompter → orchestrate →
pm so each one finds its optional dependencies already present.

> **It clones four repos from `github.com/eimaj` and runs each one's installer.** That
> is code from the internet executing on your machine, at whatever their default branch
> happens to be. Read `install.sh` first, or start with `--dry-run` below — it executes
> nothing.

```bash
./install.sh --dry-run          # change nothing, run nothing
./install.sh --preview          # also run each tool's own dry-run (executes their code)
./install.sh --all              # accept all four, no prompts
./install.sh --root ~/src       # clone somewhere other than ~/Code
./install.sh --only clog,dev-prompter
```

Two preview modes, kept apart on purpose. **`--dry-run` runs nothing** — it prints what
this script would do and never executes another installer, so it's safe on a repo you
haven't read yet. **`--preview`** additionally runs each tool's own `--dry-run` for a
fuller picture, which means executing code from those repos; it's opt-in for exactly
that reason, and it reports rather than fetches anything not already cloned.

Nothing is installed without an answer. With no terminal to prompt on — CI, a pipe, an
agent — it refuses and tells you to pass `--all`. Existing clones are reused (never
re-cloned, never pulled without asking) and only after checking their `origin` is the
repo it expects. Existing skills and symlinks are never overwritten; collisions are
skipped and reported at the end.

**Requirements:** `bash`, `git`. Add `jq` if you want pm, `gh` for the GitHub-facing
skills, and [`herdr`](https://herdr.dev) if you want dev-prompter's `/dev-tab` and
`/dev-tab-q`. macOS / Linux / WSL.

---

## Probably don't install all four on day one

The loop is worth more than any one piece, but adopting it all at once means learning
four workflows while trying to get actual work done. If you want all of them, the
order that goes down easiest is **clog → dev-prompter → orchestrate → pm** — each one
adds a step to a loop that already works without it.

**[docs/ONBOARDING.md](docs/ONBOARDING.md)** is the how-to: the exact commands per
tool, what to verify after each, and a checkpoint that says whether the next piece is
worth it. It's paced out over four weeks, which is a suggestion and not a schedule —
go faster, stop after one, whatever fits.

Prefer to be walked through it? `/toolkit-setup` runs the same path interactively in a
Claude Code session, asking before each step.

### Useful subsets

| You want | Install |
| --- | --- |
| Session memory that survives `/clear` and autocompact | clog |
| Better delegation + real code review, nothing else | dev-prompter (+ clog for the learn step) |
| Auditable multi-agent runs on big changes | orchestrate + clog |
| Long-running projects across many sessions and tabs | pm (+ clog for the `logs` slot) |
| The whole loop | all four, in that order |

---

## Honest limits

- **Claude Code specific.** clog's skills work in Codex/Cursor/OpenCode, but the hooks,
  the `/dev` family, orchestrate, and pm all assume Claude Code.
- **This is a discipline, not automation.** clog only has data if you write entries.
  orchestrate only helps if you actually read the retro. The tools reduce the friction;
  they don't remove the habit.
- **Overhead is real and intentional.** orchestrate in particular is built for work big
  enough to deserve a paper trail. On a 20-minute change it will feel like ceremony,
  because it is.
- **Bash + symlinks.** No native Windows support.

---

## License

MIT — see [LICENSE](LICENSE). Each linked repo carries its own license.
