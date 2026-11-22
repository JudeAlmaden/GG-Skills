# How to Use GG_Skills on a New Project

## 🚀 Quick Setup (30 seconds)

### Step 1: Navigate to Your Project

```powershell
cd C:\Projects\MyNewProject
```

### Step 2: Install Skills (Choose One Method)

#### Option A: Interactive Mode (Recommended for First Time)

```powershell
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Interactive
```

You'll see:
```
GG_Skills Interactive Installer
================================

Available collections:

  [1] all
      Every skill in the GG_Skills collection
  [2] caveman
      Complete caveman skill suite - terse communication and development workflows
  [3] ponytail
      Lazy senior dev workflow skills - minimal code, maximum impact
  [4] superpowers
      Complete software development methodology with agentic skills framework

  [0] Exit

Select collections (comma-separated numbers, e.g., 1,3,5):
```

Type `3,4` and press Enter to install ponytail and superpowers.

#### Option B: Direct Install

```powershell
# Install specific collections
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail,superpowers

# Install everything
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections all
```

### Step 3: Verify Installation

```powershell
Get-ChildItem .agents\skills
```

You should see skill directories like `ponytail/`, `brainstorming/`, etc.

### Step 4: Start Using

Open your AI assistant (Claude Code, Cursor, Windsurf, etc.) in this project and use the skills:

```
You: /ponytail - create a REST API for user management

You: /brainstorming - let's build a todo app

You: /caveman - refactor this authentication code
```

## 📋 Common Installation Patterns

### For New Projects (Clean Slate)

```powershell
# Minimal setup - just the essentials
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail

# Development workflow - planning + lazy coding
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections superpowers,ponytail

# Full toolkit
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections all
```

### For Existing Projects

Same as above! The script creates `.agents/skills/` if it doesn't exist.

### For Legacy Codebases

```powershell
# Caveman is great for understanding and refactoring
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections caveman
```

## 🎯 Collection Descriptions

| Collection | Best For | When to Use |
|------------|----------|-------------|
| **ponytail** | Clean, minimal code | New features, bug fixes, keeping it simple |
| **caveman** | Terse communication | When token costs matter, terminal use, fast answers |
| **superpowers** | Complete methodology | Serious projects, TDD workflows, planning |
| **all** | Everything | When you want the full toolkit available |

## 🔄 Updating Skills in a Project

If you update GG_Skills collections (new commit hashes, new skills), reinstall:

```powershell
cd C:\Projects\MyProject
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail,superpowers
```

The script will overwrite existing skills with the new versions.

## 📁 What Gets Created

After installation:

```
MyProject/
├── .agents/
│   └── skills/           ← Skills copied here
│       ├── ponytail/
│       ├── brainstorming/
│       ├── caveman/
│       └── ...
├── skills-lock.json      ← Tracks what's installed
└── (your project files)
```

### Should I Commit These?

**Option 1: Commit (Recommended)**
- Everyone on the team gets the same skills
- No setup needed for new team members
- Add to `.gitignore`: (nothing)

**Option 2: Don't Commit**
- Each developer chooses their own skills
- Add to `.gitignore`:
  ```
  .agents/
  skills-lock.json
  ```
- Document in README how to install skills

Most teams commit `.agents/skills/` so everyone has the same workflow.

## 🛠️ Advanced Usage

### Install to Different Directory

```powershell
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail -TargetPath C:\Projects\OtherProject
```

### List Available Collections

```powershell
powershell C:\Projects\GG_Skills\scripts\install.ps1 -List
```

### See What's in a Collection

```powershell
cd C:\Projects\GG_Skills
.\scripts\list-skills.ps1 -Collection superpowers
```

## 🌐 Using on Another Machine

### Step 1: Clone GG_Skills

```powershell
git clone https://github.com/JudeAlmaden/GG_Skills.git C:\Projects\GG_Skills
```

### Step 2: Install to Projects

Same as above! Just use the install script.

## 👥 Team Setup

### For the Team Lead

1. Set up GG_Skills (already done!)
2. Share the repo URL with team
3. Document which collections to use (in project README)

```markdown
## AI Skills Setup

This project uses skills from GG_Skills:

```powershell
git clone https://github.com/JudeAlmaden/GG_Skills.git C:\Dev\GG_Skills
cd C:\Projects\OurProject
powershell C:\Dev\GG_Skills\scripts\install.ps1 -Collections superpowers,ponytail
```
```

### For Team Members

1. Clone GG_Skills once
2. Install to each project they work on
3. That's it!

## 📝 Example Workflow

### Scenario: Starting a New React App

```powershell
# Create project
npx create-react-app my-app
cd my-app

# Install skills
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections superpowers,ponytail

# Open AI assistant and start building
# The skills auto-trigger based on what you're doing
```

### Scenario: Taking Over Legacy Code

```powershell
# Clone existing project
git clone https://company.com/legacy-app.git
cd legacy-app

# Install caveman for code exploration
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections caveman

# Use caveman-discover, caveman-explore to understand codebase
```

### Scenario: Multiple Projects

```powershell
# Install to all your active projects
cd C:\Projects\ProjectA
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail

cd C:\Projects\ProjectB
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections all

cd C:\Projects\ClientWork
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections superpowers
```

## ❓ FAQ

**Q: Do I need to install GG_Skills in every project?**
No! Install GG_Skills once (in `C:\Projects\GG_Skills` or anywhere). Then use the scripts to deploy skills to each project.

**Q: Can I use different skill sets in different projects?**
Yes! Each project can have different collections installed.

**Q: What if I don't want all skills from a collection?**
Create a custom collection in GG_Skills that only includes the skills you want.

**Q: How much disk space do skills take?**
~100KB per skill (just text files). A full installation of all collections is ~3MB.

**Q: Do skills work offline?**
Yes, once installed. The initial installation downloads from GitHub (requires internet).

**Q: Can I customize a skill for one project?**
Yes! Edit `.agents/skills/skill-name/SKILL.md` in your project. To save it back to GG_Skills, use `save-skill.ps1`.

**Q: Which AI assistants support these skills?**
Any assistant that reads `.agents/skills/` directory:
- Claude Code
- Cursor
- Windsurf  
- Cline
- Codex
- And more

## 🎓 Next Steps

1. **Try it**: Install skills to a test project
2. **Experiment**: Try different collections, see what works for you
3. **Customize**: Create your own skills with `save-skill.ps1`
4. **Share**: Push your custom skills to GG_Skills and use across projects

## 📚 More Resources

- **README.md** - Full documentation
- **QUICKSTART.md** - 5-minute guide
- **HOW_IT_WORKS.md** - Architecture deep-dive
- **SUMMARY.md** - What's included

---

**Need help?** Check the docs or create an issue on GitHub.
