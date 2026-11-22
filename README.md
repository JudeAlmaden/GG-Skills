# GG_Skills

A pinned library of AI agent skills. Install a collection into any project and it
lands in `.agents/skills/`, where Claude Code, Cursor, Windsurf, Cline, and other
`.agents/skills/`-aware assistants pick it up.

```
registry.json      sources (repo + commit), skills, collections
gg.cmd             shortcut: "gg core", "gg list", "gg sync"
scripts/gg.ps1     the actual tool
skills/            your own skills (committed)
```

Skills are vendored from three upstream repos, each pinned to a commit:

| Source | Repo | Pinned commit |
|---|---|---|
| `ponytail` | `DietrichGebert/ponytail` | `ebd8654` |
| `caveman` | `JuliusBrussee/caveman` | `70f4f34` |
| `superpowers` | `obra/superpowers` | `22f0b46` |

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+
- `git` on PATH
- Internet for the first clone of each source (cached in `%TEMP%\gg_skills_cache`)

## Collections

| Collection | Skills | What it is |
|---|---|---|
| `ponytail` | 6 | Lazy senior dev: smallest change that works |
| `caveman` | 22 | Terse communication, review, refactor, migration workflows |
| `superpowers` | 15 | Planning, TDD, debugging, code review, worktrees |
| `core` | 5 | ponytail + brainstorming, writing-plans, TDD, verification |
| `all` | 43 | Everything above |

Add the repo root to your `PATH` once, then the command is just `gg`:

```powershell
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\Projects\GG_Skills", "User")
```

```powershell
gg list
gg list -Collection core
```

Without the PATH entry, run `C:\Projects\GG_Skills\gg.cmd` instead of `gg`.

## Install into a project

Ad-hoc install (merges with whatever is already installed):

```powershell
cd C:\Projects\MyApp
gg core
gg install -Collections ponytail -Skills caveman-commit
```

Typing a collection name alone (`gg core`, `gg all`) is shorthand for
`gg install -Collections core`.

Or make it declarative: write `skills.json` once, commit it, then `sync`:

```powershell
gg init -Collections ponytail,core
git add skills.json
gg sync
```

`sync` installs what the manifest lists and removes skills that `gg` installed
earlier but the manifest no longer asks for. Directories you created by hand in
`.agents/skills/` are never touched.

## Commands

| Command | Purpose |
|---|---|
| `list [-Collection name]` | Show collections or the skills in one |
| `install -Collections a,b [-Skills x,y] [-Force]` | Add skills; merges `skills-lock.json` |
| `init -Collections a,b [-Skills x,y] [-Force]` | Write `skills.json` in the target |
| `sync [-Force]` | Install + prune to match `skills.json` |
| `save -SkillName name [-Force]` | Copy a project skill into `skills/` |
| `verify` | Check installed files against the lock; exit 1 on drift |
| `doctor` | Validate the registry; report skills not tracked by the lock |

All commands take `-Target <path>` (defaults to the current directory).
`-Force` re-copies skills even when the hash matches.

## Custom skills

```powershell
cd C:\Projects\MyApp
# ... author .agents/skills/my-api/SKILL.md, test it with your assistant ...
powershell C:\Projects\GG_Skills\gg.cmd save -SkillName my-api
```

Then add the name to a collection in `registry.json` so it can be installed elsewhere:

```json
"collections": {
  "core": ["ponytail", "brainstorming", "my-api"]
}
```

Local skills need no entry under `"skills"`: a skill name resolves to
`skills/<name>/` when that directory exists, otherwise to the registry source.
Commit `skills/my-api/` and the registry change, and every machine that clones
this repo gets it.

## Updating a pin

Edit the `commit` for that source in `registry.json`, then `sync` in each project
(or `install -Force`). Use a full SHA; branch names are rejected so installs stay
reproducible (`-AllowBranch` overrides for a one-off test).

## State files

- `skills.json` - project intent, committed by the project (only with `init`).
- `skills-lock.json` - resolved source, commit, and SKILL.md hash per installed
  skill. Generated; safe to delete and rebuild. Commit it if you want
  reproducible installs across machines.
- In this library repo, `.agents/` and `skills-lock.json` are gitignored: they
  are install artifacts, not content.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Unknown collection` | Typo, or the registry entry is missing. `gg list` |
| `Unknown skill` | Not in `registry.json` and not in `skills/` |
| `pinned to 'main', not a commit SHA` | Use a SHA, or pass `-AllowBranch` |
| `lock is empty` | Nothing installed in that target yet |
| `verify` reports a skill as modified | You edited the installed copy; `install ... -Force` restores the pinned version |
| Clone fails | No network or no access to the public repo; check `git` on PATH |
| Skills not showing in your assistant | It must read `.agents/skills/`; check the target path |

## Credits

Skill content belongs to its upstream projects and keeps their licenses:

- `DietrichGebert/ponytail`
- `JuliusBrussee/caveman`
- `obra/superpowers`
