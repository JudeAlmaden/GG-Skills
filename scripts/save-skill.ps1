#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Save a custom skill from a project to GG_Skills repository.

.DESCRIPTION
    Copies a skill from a project's .agents/skills directory to the GG_Skills
    custom skills directory, making it available for reuse across projects.

.PARAMETER SkillName
    Name of the skill to save

.PARAMETER SourcePath
    Source project directory. Defaults to current directory.

.PARAMETER Force
    Overwrite existing skill without prompting

.EXAMPLE
    .\save-skill.ps1 -SkillName my-api-workflow
    
.EXAMPLE
    .\save-skill.ps1 -SkillName my-testing-style -SourcePath C:\Projects\MyApp
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SkillName,
    
    [string]$SourcePath = ".",
    
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$TargetSkillsDir = Join-Path $RepoRoot "skills"

function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }

try {
    Write-Host "`nGG_Skills - Save Custom Skill" -ForegroundColor Cyan
    Write-Host "=============================`n" -ForegroundColor Cyan
    
    # Resolve source path
    $SourcePath = Resolve-Path $SourcePath -ErrorAction SilentlyContinue
    if (-not $SourcePath) {
        Write-Error "Source path does not exist"
        exit 1
    }
    
    # Find skill in source
    $sourceSkillPath = Join-Path $SourcePath ".agents\skills\$SkillName"
    if (-not (Test-Path $sourceSkillPath)) {
        Write-Error "Skill '$SkillName' not found in $SourcePath\.agents\skills\"
        Write-Info "Available skills:"
        
        $skillsPath = Join-Path $SourcePath ".agents\skills"
        if (Test-Path $skillsPath) {
            Get-ChildItem -Path $skillsPath -Directory | ForEach-Object {
                Write-Host "  - $($_.Name)" -ForegroundColor Yellow
            }
        }
        exit 1
    }
    
    # Check if SKILL.md exists
    $skillFile = Join-Path $sourceSkillPath "SKILL.md"
    if (-not (Test-Path $skillFile)) {
        Write-Error "SKILL.md not found in $sourceSkillPath"
        exit 1
    }
    
    Write-Info "Found skill: $SkillName"
    Write-Info "Source: $sourceSkillPath"
    
    # Check if skill already exists in GG_Skills
    $targetSkillPath = Join-Path $TargetSkillsDir $SkillName
    if (Test-Path $targetSkillPath) {
        if (-not $Force) {
            Write-Warning "Skill '$SkillName' already exists in GG_Skills"
            $overwrite = Read-Host "Overwrite? (y/n)"
            if ($overwrite -ne 'y' -and $overwrite -ne 'Y') {
                Write-Info "Save cancelled"
                exit 0
            }
        }
        
        Write-Info "Removing existing skill..."
        Remove-Item $targetSkillPath -Recurse -Force
    }
    
    # Ensure target directory exists
    if (-not (Test-Path $TargetSkillsDir)) {
        New-Item -ItemType Directory -Path $TargetSkillsDir -Force | Out-Null
    }
    
    # Copy skill
    Write-Info "Copying skill to GG_Skills..."
    Copy-Item $sourceSkillPath $targetSkillPath -Recurse -Force
    
    Write-Success "Skill saved successfully!"
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "  1. Review the skill: $targetSkillPath"
    Write-Host "  2. Add it to a collection in: $RepoRoot\collections\"
    Write-Host "  3. Commit and push to your GG_Skills repository"
    Write-Host "`nExample collection entry:"
    Write-Host @"
    {
      "name": "$SkillName",
      "source": "local",
      "commit": "custom"
    }
"@ -ForegroundColor Gray
    
    Write-Host "`nTo create a new collection for this skill:"
    Write-Host "  New-Item `"$RepoRoot\collections\my-custom.json`"" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to save skill: $_"
    exit 1
}
