# toolkit

Four independent Claude Code repos that compose into one working loop:
**start a session with context → route the work to the right surface → review it →
log what happened → turn the log back into better prompts.**

Each repo stands alone and is useful alone. This repo is the connective tissue: the
map of how they fit, an installer that sets them up in dependency order, and an
onboarding path that gets you from zero to the full loop without swallowing all four
at once.

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

The one non-obvious property: **the last step feeds the first.** `clog-lessons` reads
the `LEARNING` entries the other three tools produced as a side effect of working, and
proposes concrete diffs to your `CLAUDE.md` and skills. Nothing else in the loop has to
be instrumented for that to work — the logging already happened.

---

## How they actually connect

Four real seams, not aspirational ones:

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

Full detail, including the naming gotcha where pm's public config calls clog `logTool`:
**[docs/INTEGRATION.md](docs/INTEGRATION.md)**.

---

## Install

```bash
git clone https://github.com/eimaj/toolkit ~/Code/toolkit
cd ~/Code/toolkit
./install.sh
```

`install.sh` is **interactive and à la carte** — it asks about each repo separately,
clones only what you say yes to, and then delegates to that repo's own installer rather
than reimplementing it. It installs in dependency order (clog → dev-prompter →
orchestrate → pm) so each tool finds its optional dependencies already present.

```bash
./install.sh --dry-run          # print every action, change nothing
./install.sh --all              # yes to all four, no prompts
./install.sh --root ~/src       # clone somewhere other than ~/Code
./install.sh --only clog,dev-prompter
```

Existing clones are detected and reused — it never re-clones over your work, and never
pulls without asking.

**Requirements:** `bash`, `git`, `jq`. `gh` for the GitHub-facing bits.
macOS / Linux / WSL. `herdr` only if you want `/dev-tab`.

---

## You probably shouldn't install all four on day one

The loop is worth more than any one piece, but adopting it all at once means learning
four workflows while trying to get actual work done. The recommended path is
**clog → dev-prompter → orchestrate → pm**, one per week, each one adding a step to a
loop that already works.

That path — with what to actually do on each day, and the checkpoint that tells you
you're ready for the next piece — is in **[docs/ONBOARDING.md](docs/ONBOARDING.md)**.

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
