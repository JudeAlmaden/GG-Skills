# GG_Skills Quick Start

## 🚀 5-Minute Setup

### 1. List Available Skills

```powershell
cd C:\Projects\GG_Skills
.\scripts\list-skills.ps1
```

### 2. Install to a Project

```powershell
# Go to your project
cd C:\Projects\MyProject

# Interactive mode (recommended for first time)
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Interactive

# Or direct install
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections ponytail,git-workflow
```

### 3. Use the Skills

In your AI assistant, you can now use:
- `/ponytail` - Activate lazy senior dev mode
- `/caveman` - Terse communication mode
- `/caveman-commit` - Smart commit message generation
- And all other installed skills!

## 📝 Common Workflows

### Install Everything

```powershell
cd C:\Projects\MyProject
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections all
```

### Install Only Code Quality Skills

```powershell
powershell C:\Projects\GG_Skills\scripts\install.ps1 -Collections code-quality
```

### See What's in a Collection

```powershell
cd C:\Projects\GG_Skills
.\scripts\list-skills.ps1 -Collection ponytail
```

### Save Your Custom Skill

```powershell
# After creating .agents/skills/my-skill/SKILL.md in your project
cd C:\Projects\MyProject
powershell C:\Projects\GG_Skills\scripts\save-skill.ps1 -SkillName my-skill
```

## 🎯 Recommended Collections

**For most projects:**
```powershell
-Collections ponytail,caveman-core,git-workflow
```

**For refactoring work:**
```powershell
-Collections code-quality,caveman-advanced
```

**For exploring new codebases:**
```powershell
-Collections caveman-advanced,investigate-first
```

## 🔧 Troubleshooting

### "Skill not found"
Make sure you're in the right directory. The install script needs to be run from your target project.

### "Collection not found"
Run `.\scripts\list-skills.ps1` to see available collections.

### Git errors during install
The script clones from GitHub. Ensure you have:
- Git installed
- Internet connection
- Access to public repos

## 📚 Next Steps

- Read the full [README.md](README.md)
- Browse skill sources:
  - [caveman](https://github.com/JuliusBrussee/caveman)
  - [ponytail](https://github.com/DietrichGebert/ponytail)
- Create your own custom skills!
