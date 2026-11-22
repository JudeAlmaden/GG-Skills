# How GG_Skills Works

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       GG_Skills Repo                         │
│  (Your central skills library - committed to Git)           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  collections/          ← Skill group definitions (JSON)     │
│  ├── ponytail.json     → Points to GitHub source + commit   │
│  ├── caveman-core.json                                      │
│  └── my-custom.json    → Points to skills/ directory        │
│                                                              │
│  skills/               ← Your custom skills (committed)     │
│  ├── my-api-workflow/                                       │
│  │   ├── SKILL.md      → The actual skill instructions      │
│  │   └── README.md     → Human documentation                │
│  └── my-testing/                                            │
│                                                              │
│  .agents/              ← Downloaded skills (gitignored)     │
│  └── skills/           → Cloned from GitHub as needed       │
│                                                              │
│  scripts/              ← Management tools                   │
│  ├── install.ps1       → Install skills to projects         │
│  ├── save-skill.ps1    → Save skills from projects          │
│  └── list-skills.ps1   → Browse collections                 │
└─────────────────────────────────────────────────────────────┘

                            ↓ install.ps1

┌─────────────────────────────────────────────────────────────┐
│                    Your Project Directory                    │
│              (Any project you're working on)                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  .agents/                                                    │
│  └── skills/           ← Skills copied here by install.ps1  │
│      ├── ponytail/                                          │
│      ├── caveman/                                           │
│      └── my-api-workflow/                                   │
│                                                              │
│  skills-lock.json      ← Tracks installed skills            │
│                                                              │
│  (your actual project code)                                 │
│  src/                                                        │
│  package.json                                               │
│  etc.                                                        │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 The Flow

### 1. Collection Definition (JSON Files)

Collections are JSON files that define groups of skills:

```json
{
  "name": "ponytail",
  "description": "Lazy senior dev workflow skills",
  "skills": [
    {
      "name": "ponytail",
      "source": "DietrichGebert/ponytail",    ← GitHub repo
      "commit": "ebd8654c2c627..."            ← Specific commit (pinned)
    }
  ]
}
```

**Why commit pinning?**
- Ensures everyone gets the same version
- Skills don't break when source repo updates
- You control when to upgrade

### 2. Installing Skills

When you run:
```powershell
.\scripts\install.ps1 -Collections ponytail,git-workflow
```

**What happens:**

```
Step 1: Read collection files
  ✓ Load ponytail.json
  ✓ Load git-workflow.json
  
Step 2: Resolve all skills
  ✓ ponytail (6 skills)
  ✓ git-workflow (2 skills)
  → Total: 8 unique skills
  
Step 3: Download sources (if needed)
  ✓ Clone DietrichGebert/ponytail → temp directory
  ✓ Checkout commit ebd8654c2c627...
  ✓ Clone JuliusBrussee/caveman → temp directory
  ✓ Checkout commit 70f4f34e83489...
  
Step 4: Copy to target project
  ✓ Copy skills/ from temp → YourProject/.agents/skills/
  
Step 5: Generate lock file
  ✓ Create YourProject/skills-lock.json
  ✓ Record all installed skills with hashes
```

**Temp directory:** Skills are cloned to `%TEMP%/gg_skills_temp/` and reused on subsequent installs.

### 3. Custom Skills Flow

```
┌──────────────┐
│ Your Project │
│              │
│ Create:      │
│ .agents/     │
│   skills/    │
│     my-skill/│
│       SKILL.md
└──────────────┘
       ↓
   Test it with your AI assistant
   (/my-skill)
       ↓
   save-skill.ps1
       ↓
┌──────────────┐
│  GG_Skills   │
│              │
│ Copied to:   │
│ skills/      │
│   my-skill/  │
│     SKILL.md │
└──────────────┘
       ↓
   Add to collection
   (edit collections/my-custom.json)
       ↓
   git commit && git push
       ↓
┌──────────────────────────┐
│ Now available on all     │
│ machines that clone      │
│ your GG_Skills repo!     │
└──────────────────────────┘
```

## 📦 What Gets Committed vs Ignored

### ✅ Committed (Shared via Git)

```
GG_Skills/
├── collections/          ✓ Collection definitions
├── skills/              ✓ YOUR custom skills
├── scripts/             ✓ Management scripts
├── README.md            ✓ Documentation
└── .gitignore           ✓ Git configuration
```

### ❌ Ignored (Local only)

```
GG_Skills/
├── .agents/             ✗ Downloaded skills (can be re-cloned)
├── skills-lock.json     ✗ Your local installation state
└── ~/                   ✗ Kiro runtime files
```

**Why ignore downloaded skills?**
- They come from external GitHub repos
- Can be re-downloaded anytime
- Keeps your repo small
- No license concerns

**Why ignore skills-lock.json in GG_Skills?**
- This is YOUR skills library, not a project
- Each target project gets its own lock file
- Lock files track what's installed WHERE

## 🔑 Key Concepts

### 1. **Source vs Installed**

- **Source:** Where skills come from (GitHub repos or your `skills/` directory)
- **Installed:** Where skills are copied to (project's `.agents/skills/`)

### 2. **Collections vs Skills**

- **Skill:** A single SKILL.md file with instructions for Kiro
- **Collection:** A JSON file that groups multiple skills together

Think of it like:
- **Skill** = A single book
- **Collection** = A bookshelf/category (e.g., "Programming Books")

### 3. **Remote vs Custom**

```
Remote Skills (from GitHub):
  - Maintained by others
  - Cloned when needed
  - Pinned to specific commits
  - Examples: ponytail, caveman

Custom Skills (in skills/):
  - Created by you
  - Committed to YOUR repo
  - Available immediately
  - Examples: my-api-workflow
```

### 4. **Meta-Collections**

The `all.json` collection includes other collections:

```json
{
  "name": "all",
  "includes": ["ponytail", "caveman-core", "git-workflow"]
}
```

Installing "all" recursively installs everything it includes.

## 🎯 Real-World Example

### Scenario: New Laravel Project

**1. You start a new Laravel project:**
```powershell
laravel new MyApp
cd MyApp
```

**2. Install your preferred skills:**
```powershell
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Interactive
# Select: ponytail, git-workflow
```

**3. Work with your AI assistant using installed skills:**
```
You: /ponytail - create a user CRUD API

AI: (follows ponytail skill - minimal code approach)
     Creates controller, routes, validation...
```

**4. Create a project-specific pattern:**
```
You: Create .agents/skills/laravel-api/SKILL.md
     (Document your API response format, error handling, etc.)
```

**5. Save it to GG_Skills:**
```powershell
powershell C:\Projects\GG_Skills\scripts\save-skill.ps1 -SkillName laravel-api
```

**6. Add to a collection:**
```powershell
cd C:\Projects\GG_Skills
# Edit collections/my-laravel.json
# Add laravel-api skill
git add .
git commit -m "Add Laravel API skill"
git push
```

**7. Use in next Laravel project:**
```powershell
cd C:\Projects\NextLaravelApp
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections my-laravel
# Your laravel-api skill is now available!
```

## 🔧 Under the Hood

### How install.ps1 Works

```powershell
# 1. Parse command line
$collections = @("ponytail", "git-workflow")

# 2. Load collection files
foreach ($col in $collections) {
    $json = Get-Content "collections/$col.json" | ConvertFrom-Json
    $allSkills += $json.skills
}

# 3. De-duplicate skills
$uniqueSkills = $allSkills | Group-Object name | Select -First 1

# 4. Download from GitHub
foreach ($skill in $uniqueSkills) {
    if ($skill.source -ne "local") {
        git clone "https://github.com/$($skill.source).git" $tempDir
        git checkout $skill.commit
        Copy-Item "$tempDir/skills/$($skill.name)" "$target/.agents/skills/"
    }
}

# 5. Copy custom skills
foreach ($skill in $uniqueSkills) {
    if ($skill.source -eq "local") {
        Copy-Item "skills/$($skill.name)" "$target/.agents/skills/"
    }
}

# 6. Generate lock file
$lockData = @{
    version = 2
    skills = $installedSkills
}
$lockData | ConvertTo-Json > "$target/skills-lock.json"
```

### Skills Lock File Format

```json
{
  "version": 2,
  "skills": {
    "ponytail": {
      "source": "DietrichGebert/ponytail",
      "commit": "ebd8654c2c627f721eb8f9c0d1bd4090a29f9e10",
      "sourceType": "github",
      "skillPath": "skills/ponytail/SKILL.md",
      "computedHash": "56d72677aca02689ac89bd48734e8c19..."
    }
  }
}
```

**Purpose:**
- Tracks what's installed
- Records exact versions (commit hashes)
- Enables reproducible installs
- Shows file integrity (SHA256 hash)

## ❓ Common Questions

### Q: Why not just copy skills manually?

**Manual approach:**
- Copy .agents/skills/ from project to project
- Hard to track what came from where
- Difficult to update
- No version control

**GG_Skills approach:**
- One command install
- Clear source tracking
- Easy updates (change commit hash)
- Shareable via Git

### Q: Can I modify installed skills?

Yes, but modifications are local to that project. If you want to save the modification:

1. Modify in project's `.agents/skills/my-skill/`
2. Run `save-skill.ps1 -SkillName my-skill -Force`
3. This overwrites the version in GG_Skills
4. Commit and push

### Q: What if GitHub repos are unavailable?

Your custom skills in `skills/` always work since they're committed. Remote skills require internet to download initially, but are cached in `%TEMP%/gg_skills_temp/` for future installs.

### Q: Can I share with my team?

Yes! Push GG_Skills to a shared GitHub/GitLab repo:

```powershell
cd C:\Projects\GG_Skills
git remote add origin https://github.com/YourTeam/company-skills.git
git push -u origin main
```

Team members clone and use the same collections.

### Q: How do I update a skill?

**For remote skills:**
1. Find new commit hash in source repo
2. Update `collections/*.json` with new commit
3. Delete cached version: `%TEMP%/gg_skills_temp/`
4. Re-run install.ps1

**For custom skills:**
1. Modify in `skills/my-skill/`
2. Commit and push
3. Re-run install.ps1 in target projects

## 🎓 Advanced Usage

### Creating Meta-Collections

Group your collections:

```json
{
  "name": "full-stack-web",
  "description": "Everything for full-stack web development",
  "includes": [
    "ponytail",
    "git-workflow",
    "my-frontend",
    "my-backend"
  ]
}
```

### Multiple Skill Sources

Mix and match in one collection:

```json
{
  "skills": [
    {
      "name": "ponytail",
      "source": "DietrichGebert/ponytail",
      "commit": "ebd8654..."
    },
    {
      "name": "my-custom",
      "source": "local",
      "commit": "custom"
    }
  ]
}
```

### Environment-Specific Collections

```
collections/
├── work.json          → Company-specific skills
├── personal.json      → Your personal workflows
├── client-acme.json   → Client-specific patterns
```

## 🚀 Next Steps

1. **Try it:** Run `install.ps1 -Interactive` on a test project
2. **Create a skill:** Make your first custom skill
3. **Organize:** Create collections that match your workflow
4. **Share:** Push to GitHub and use across machines

---

**Need help?** Check [README.md](README.md) or [QUICKSTART.md](QUICKSTART.md)
