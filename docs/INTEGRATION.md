# Integration — how the four repos actually wire together

This is the reference for the seams. If you only want the install path, read
[ONBOARDING.md](ONBOARDING.md) instead.

Every seam below is **optional in one direction**: the tool that depends on another
degrades to a documented fallback rather than failing. Nothing here is a hard
requirement except `clog` for pm's `logs` slot, and that slot itself is optional.

---

## Seam 1 — clog is the shared write target

`clog` is the substrate. The other three write into it; it depends on none of them.

### orchestrate → clog

Configured in orchestrate's repo-root `config.json`:

```json
"clog": {
  "enabled": null,
  "bin": "~/.claude/hooks/clog.sh",
  "fallback": { "jsonl": "{artifact_root}/logs/YYYYMMDD.jsonl" }
}
```

- `enabled: null` (default) **auto-detects** — checks `PATH`, then `~/.claude/hooks/clog.sh`.
- Set `true` to make clog mandatory (the run errors if it's missing), `false` to always
  use the plain-JSONL fallback.
- When clog is present, every dispatch, join, learning, and commit is logged in real
  time with a shared `--session` ID, so all entries for one run are greppable together.

**Verify the seam:** run `/orchestrate` and confirm entries land in today's clog file
with a common `session` value — not in `{artifact_root}/logs/`.

> If you installed clog *after* orchestrate, run `bash install-clog.sh --path ~/Code/clog`
> from the orchestrate repo, or just confirm `command -v clog` resolves and leave
> `enabled: null` alone.

### dev-prompter → clog

Every one of the five `/dev` skills ends its cycle with a **learn** step: a `clog`
`LEARNING` or `LESSON` entry capturing anything surprising or reusable from the run.
This is the only clog dependency in dev-prompter, and it's explicitly optional — if
`clog` isn't installed, skip the step; nothing else in the toolkit breaks.

The `-q` variants (`/dev-sa-q`, `/dev-tab-q`) skip the *review* step but **still log**.

### pm → clog

pm's personal config (`~/.config/pm/config.json`) carries a named-tool registry. clog
occupies the `logs` name:

```json
"logs": {
  "provider": "clog",
  "root": "~/pm-notes/logs",
  "skills": ["clog", "clog-sweep", "clog-day", "clog-week", "clog-search"]
}
```

> ### ⚠️ Naming gotcha
>
> pm's shipped `config/config.example.json` is deliberately vendor-neutral — it uses
> **placeholder provider names**, not real ones:
>
> | Example config says | You almost certainly mean |
> | --- | --- |
> | `"provider": "logTool"` | `clog` |
> | `"skills": ["logtool", "logtool-sweep", "logtool-day", …]` | `clog`, `clog-sweep`, `clog-day`, … |
> | `"provider": "todoApp"` | your actual todo CLI |
>
> `/pm-generate` normally overwrites these during its walk-through, but if you hand-edit
> the config instead, **replace `logTool` with `clog`** or the `logs` slot silently
> resolves to nothing and pm's briefings quietly drop your log data. This is the single
> most likely thing to go wrong in a full-toolkit install.

**Verify the seam:** `jq '.tools.logs' ~/.config/pm/config.json` — the `provider` must
be a real, resolvable name, not `logTool`.

---

## Seam 2 — `/pr-review` is the single review engine

Both the light path and the heavy path converge on the same rubric.

| Path | Review mechanism | Produces artifacts? |
| --- | --- | --- |
| `/dev`, `/dev-tab`, `/dev-sa` | calls `/pr-review` directly | no — advisory, in-session |
| `/orchestrate` | its own `reviewer` agent step | yes — `learnings.md`, `retro.md` |
| `/dev-sa-q`, `/dev-tab-q` | none (skipped by design) | no |

`/pr-review` ships **inside dev-prompter** (`skills/pr-review/`), so installing
dev-prompter gets you the review engine whether or not you use the `/dev` family. It is
advisory only: it never posts to GitHub and never blocks.

If you install **orchestrate without dev-prompter**, orchestrate's reviewer agent still
works — it's a separate implementation. You just won't have the lightweight
`/pr-review` for one-off diffs.

---

## Seam 3 — routing between the light and heavy paths

This is the decision the toolkit exists to make cheap. dev-prompter's skills already
encode the handoff — every `/dev` skill carries a routing gate that sends you to
`/orchestrate` when the work outgrows it.

| The work is… | Use |
| --- | --- |
| A question, a search, a scan — no files change | `/dev-sa-q` |
| One scoped change you'll eyeball yourself | `/dev-sa-q` or `/dev-tab-q` |
| One scoped change you want reviewed | `/dev`, `/dev-sa`, or `/dev-tab` |
| Multi-phase (write → review → retro), or you expect reviewer pushback | `/orchestrate` |
| Large or parallel, and you want explicit file scoping first | `/orchestrate-brief` → `/orchestrate` |

Pick the **surface** by how you want to interact (inline / separate pane / one-shot
subagent) and the **cycle** by whether you want it reviewed. The `-q` suffix is always
"skip the review."

**The gate, as `/dev-sa` words it:** *"if the ask needs multiple phases (write → review
→ retro), will produce tracked artifacts, or involves iterative cycles, stop here and
use `/orchestrate` instead."* The other `/dev` skills carry the same rule in their own
words.

---

## Seam 4 — pm hands briefs to orchestrate

`/orchestrate-brief` writes `brief.md` to orchestrate's global
`{artifact_root}/runs/<run-id>/`. That's fine for a one-off, but a brief for a
long-running project belongs *with* the project.

`/pm-end` closes that gap. Each pm project's `.pm/config.json` carries a **`briefs_dir`**
(default `<project-root>/briefs/`, seeded by `/pm-init`). On session end, pm:

1. resolves `briefs_dir`,
2. moves the run's `brief.md` there as `YYYY-MM-DD-<TICKET>-<slug>.md`,
3. **commits it** — briefs live untracked in the project tree, and a concurrent session
   can wipe an uncommitted one.

It never modifies orchestrate's global `artifact_root`. Pass the *relocated* path to
`/orchestrate` on the next run.

**Without pm:** briefs stay under `~/.orchestrate/runs/` and you manage them yourself.
**Without orchestrate:** `briefs_dir` just stays empty. Neither is an error.

---

## Degradation matrix

What breaks when a piece is missing. "Degrades" means documented fallback, not failure.

| Missing | clog | dev-prompter | orchestrate | pm |
| --- | --- | --- | --- | --- |
| **clog** | — | learn step skipped; everything else works | degrades to plain JSONL under `{artifact_root}/logs/` | `logs` slot degrades; briefing says so instead of fabricating |
| **dev-prompter** | unaffected | — | unaffected (has its own reviewer agent) | `github`/`pr-review` skill links go unresolved |
| **orchestrate** | unaffected | routing gate points at a command you don't have | — | `briefs_dir` stays empty |
| **pm** | unaffected | unaffected | unaffected | — |

Read across a row: the leftmost cell names what is absent, the rest say how each tool
copes.

The pattern: clog is depended *on* by all three and depends on none; pm is depended on
by none and optionally reads all three. Install in that order and every optional
dependency is satisfied by the time the dependent tool looks for it.

---

## Install order and why it matters

```
clog  →  dev-prompter  →  orchestrate  →  pm
 │            │                │            │
 │            │                │            └─ /pm-generate audits installed skills
 │            │                │               and MCP servers; the more that exist
 │            │                │               when it runs, the better the mapping
 │            │                └─ auto-detects clog at install and first run
 │            └─ pr-review is what /dev's review step will call
 └─ nothing to wait for
```

pm goes last for a specific reason: **`/pm-generate` audits `~/.claude/skills/*` and
your active MCP servers, then walks you through naming tools around what it found.**
Run it before installing the others and it can't offer you `clog-week` or `pr-review`
as skill links — you'd have to re-run `/pm-generate` afterward anyway.

`install.sh` walks them in that order so each one's optional dependencies are already
present. Installing by hand out of order is recoverable — the only part that really
matters is clog before the others, and pm last.

---

## Shared conventions

Things all four assume, worth knowing once:

- **Skills install to `~/.claude/skills/<name>/SKILL.md`.** All four either symlink the
  repo directory there (clog, orchestrate, pm's `pm-generate`, dev-prompter) or render
  real files (pm's generated `pm-init`/`pm-start`/`pm-status`/`pm-end`).
- **Symlinks track the repo.** Pull the repo, get the new skill version — with the one
  exception of pm's rendered skills, which need a `/pm-generate` re-run. The flip side
  is worth knowing before it surprises anyone: a `git pull` in a linked checkout
  rewrites standing agent instructions, with no diff shown and nothing to re-run. That
  is the trade for not silently going stale. Read the log before pulling if the skills
  are load-bearing, or copy the directories instead of linking them to pin them.
- **Personal config is gitignored and lives outside the repo** —
  `~/.config/clog/config.yaml`, `~/.config/pm/config.json`. orchestrate is the odd one
  out: its `config.json` sits in the repo root, gitignored.
- **Installers are idempotent and never overwrite.** A real directory, or a symlink
  pointing anywhere other than where this installer would point it, is skipped and
  reported. Re-run freely.
- **Nothing auto-applies a change to your prompts.** `clog-lessons` proposes diffs.
  `/pr-review` is advisory. orchestrate's retro writes a report. You decide.
