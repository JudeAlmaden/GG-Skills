# Adding skills to the library

Three routes, cheapest first:

| You have | Route | Effort |
|---|---|---|
| A skill already installed in a project | [`gg save`](#a-copy-a-project-skill-in) | one command |
| A skill you are writing by hand | [drop it in `skills/`](#c-hand-vendor-a-skill) | one folder |
| A GitHub repo full of skills | [pin it in `registry.json`](#b-pin-a-new-upstream-repo) | one JSON edit per skill |

Local skills need no registry entry at all. Registry entries are only needed for
skills that live in someone else's repo.

---

## What a skill looks like

The [Agent Skills specification](https://agentskills.io/specification) defines a
skill as a directory containing one `SKILL.md`, with YAML frontmatter followed by
Markdown instructions:

```
skill-name/
├── SKILL.md          # required: frontmatter + instructions
├── scripts/          # optional: executable code the agent runs
├── references/       # optional: longer docs, loaded on demand
└── assets/           # optional: templates, images, data files
```

Required frontmatter, per the spec:

| Field | Rules |
|---|---|
| `name` | 1–64 chars, lowercase letters/digits/hyphens, **must match the directory name** |
| `description` | 1–1024 chars, non-empty, says what it does *and when to use it* |

Optional: `license`, `compatibility` (≤500 chars, environment needs),
`allowed-tools` (space-separated tool names), `metadata` (string→string map).

```markdown
---
name: my-api
description: Triage failures in the Acme API. Use when a request fails, a 5xx appears in logs, or someone asks why an endpoint is slow.
---

# Acme API triage

1. Read `references/endpoints.md` for the endpoint table.
2. Run `scripts/collect.sh <trace-id>` ...
```

`description` is the field the assistant matches on, so write the words a person
would actually type. The body loads whole once the skill is activated — keep the
essentials at the top.

---

## A. Copy a project skill in

The fastest route: author and test the skill where it runs, then pull it back
into the library.

```powershell
cd C:\Projects\MyApp
# ... author .agents/skills/my-api/SKILL.md, test it with your assistant ...
powershell C:\Projects\GG_Skills\gg.cmd save -SkillName my-api
```

`save` copies `.agents/skills/my-api/` to `skills/my-api/` (refuses to overwrite
without `-Force`). That is the whole job — the next `gg` run lists it under a
`local` group, because a skill name resolves to `skills/<name>/` whenever that
directory exists, before the registry is consulted.

You only need a registry entry if you want the skill reachable through
`-Collections` or `sync`. Then add the name to a collection:

```json
"collections": {
  "core": ["ponytail", "brainstorming", "my-api"]
}
```

Local skills never get a `"skills"` entry. They also shadow an upstream skill of
the same name, which is the intended way to fork one.

---

## B. Pin a new upstream repo

Upstream repos follow the same layout, usually `skills/<name>/SKILL.md` at the
repo root. Claude *plugin* repos instead nest skills under a plugin folder
(`plugins/acme/skills/<name>/SKILL.md`), and marketplaces add a
`.claude-plugin/marketplace.json` catalog — that layout is why `registry.json`
lets you override `path` per skill.

### Do it in one command

```powershell
powershell .\gg.cmd add-source -Repo owner/repo -Write
```

It clones the repo, resolves the commit to a full SHA, finds every `SKILL.md`,
reads the skill's frontmatter `name` (falling back to the folder name), records
`path` whenever the layout is not `skills/<name>`, and inserts the `sources` and
`skills` entries into `registry.json`. Drop `-Write` to print the JSON and paste
it yourself. `-Ref <tag|branch|sha>` pins something other than the default branch
tip (the SHA it resolves to is what gets recorded), and `-Source <name>` overrides
the derived source key.

Names already present in the registry are skipped with a warning, so it is safe to
re-run after a repo adds skills.

It does not touch collections — finish with step 3 below.

### By hand

#### 1. Pin the source to a commit

```powershell
git ls-remote https://github.com/owner/repo HEAD      # or: git rev-parse HEAD in a clone
```

Full 40-char SHA. Branch and tag names are rejected on purpose, so a `sync` on
another machine cannot pick up an unrelated commit.

```json
"sources": {
  "acme": { "repo": "acme/agent-skills", "commit": "3f9c2e1d4b6a8570c1f2e3d4a5b6c7d8e9f0a1b2" }
}
```

#### 2. Declare each skill

One entry per skill. The default lookup is `skills/<name>/SKILL.md`, so a flat
repo needs nothing but the source name:

```json
"skills": {
  "acme-triage": { "source": "acme" }
}
```

If the repo nests skills, point at the real path:

```json
"skills": {
  "acme-triage":  { "source": "acme", "path": "plugins/acme/skills/triage" },
  "acme-release": { "source": "acme", "path": "plugins/acme/skills/release" }
}
```

`path` is repo-root relative, forward slashes, and must contain `SKILL.md`.

The skill name in `registry.json` is the name installed into `.agents/skills/`,
so it may differ from the folder name upstream. Keep them equal unless a
collision forces otherwise — assistants match on the frontmatter `name`, so a
renamed skill is best accompanied by an edited `SKILL.md`, which `gg` will then
see as modified on `verify`. Prefer the upstream names.

#### 3. Optionally group it

Collections are for `gg install -Collections` and `sync`. The picker lists every
registered skill regardless of collection membership, so a new source shows up in
`gg` immediately.

```json
"collections": {
  "acme": ["acme-triage", "acme-release"]
}
```

Collections may also compose:

```json
"all": { "includes": ["ponytail", "caveman", "superpowers", "acme"] }
```

#### 4. Prove it

```powershell
powershell .\gg.cmd doctor                     # registry validates, counts update
powershell .\gg.cmd list -Collection acme      # resolves the collection
mkdir C:\Temp\gg-smoke; powershell .\gg.cmd install -Collections acme -Target C:\Temp\gg-smoke
```

A wrong `path` fails loudly there with
`Skill '<name>' not found at '<path>' in <repo>@<commit>`, which is the cheapest
place to catch it.

---

## C. Hand-vendor a skill

Same as route A, without an install to copy from: create `skills/<name>/SKILL.md`
in this repo, commit it, and it is available everywhere. Use this for skills that
are specific to your own workflow and have no upstream.

---

## Keeping a pin current

Edit `commit` in `registry.json`, then in each project:

```powershell
powershell C:\Projects\GG_Skills\gg.cmd install -Collections core -Force
# or, for a project with skills.json:
powershell C:\Projects\GG_Skills\gg.cmd sync
```

`install` checks out the new pin and compares content, so it reinstalls only the
skills whose `SKILL.md` actually changed, and refreshes `skills-lock.json` with
the new commit either way. `-Force` is only needed to overwrite a copy someone
edited by hand. With `sync`, everything the manifest lists is re-resolved against
the new pin, and skills it no longer asks for are pruned.

`verify` compares the installed file against `skills-lock.json`, not against the
registry, so bumping a pin in the library does not by itself fail verification —
a project reports `modified` only when its own copy drifted from what was
installed.

---

## Attribution

Content stays owned by its upstream project. When you add a source:

- keep the upstream `LICENSE` / `license:` frontmatter intact inside the skill
- add a row for the repo under **Credits** in `README.md`
- record the pin in the sources table there so the vendored version is traceable

---

## Checklist

- [ ] `SKILL.md` has `name` matching its directory, and a `description` naming when to use it
- [ ] source pinned to a full 40-char SHA
- [ ] `path` set for any non-`skills/<name>` layout
- [ ] name added to a collection if it should be installable by name
- [ ] `gg doctor` clean
- [ ] install into a scratch target succeeds
- [ ] README Credits updated with the repo
