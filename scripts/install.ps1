#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Install AI skills from GG_Skills collections to a target project.

.DESCRIPTION
    This script installs skills from predefined collections into a target project's
    .agents/skills directory. It can work in interactive mode or accept collection
    names as parameters.

.PARAMETER Collections
    Comma-separated list of collection names (e.g., "ponytail,git-workflow")

.PARAMETER TargetPath
    Target project directory. Defaults to current directory.

.PARAMETER Interactive
    Launch interactive collection selector

.PARAMETER List
    List available collections and exit

.EXAMPLE
    .\install.ps1 -Collections ponytail,git-workflow
    
.EXAMPLE
    .\install.ps1 -Interactive
    
.EXAMPLE
    .\install.ps1 -List
#>

param(
    [string]$Collections = "",
    [string]$TargetPath = ".",
    [switch]$Interactive,
    [switch]$List
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$CollectionsDir = Join-Path $RepoRoot "collections"
$SkillsDir = Join-Path $RepoRoot "skills"
$DownloadedSkillsDir = Join-Path $RepoRoot ".agents\skills"

function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "ℹ $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }

# Get all available collections
function Get-Collections {
    $collections = @()
    Get-ChildItem -Path $CollectionsDir -Filter "*.json" | ForEach-Object {
        $content = Get-Content $_.FullName | ConvertFrom-Json
        $collections += [PSCustomObject]@{
            Name = $content.name
            Description = $content.description
            File = $_.FullName
            Skills = $content.skills
            Includes = $content.includes
        }
    }
    return $collections
}

# List all collections
function Show-Collections {
    $collections = Get-Collections
    Write-Host "`nAvailable Collections:" -ForegroundColor Yellow
    Write-Host "=====================`n" -ForegroundColor Yellow
    
    foreach ($col in $collections) {
        Write-Host "  $($col.Name)" -ForegroundColor Cyan
        Write-Host "    $($col.Description)" -ForegroundColor Gray
        
        if ($col.Includes) {
            Write-Host "    Includes: $($col.Includes -join ', ')" -ForegroundColor DarkGray
        } else {
            $skillCount = ($col.Skills | Measure-Object).Count
            Write-Host "    Skills: $skillCount" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

# Resolve collection includes recursively
function Resolve-CollectionSkills {
    param($CollectionName, [hashtable]$Visited = @{})
    
    if ($Visited.ContainsKey($CollectionName)) {
        return @()
    }
    $Visited[$CollectionName] = $true
    
    $collections = Get-Collections
    $collection = $collections | Where-Object { $_.Name -eq $CollectionName } | Select-Object -First 1
    
    if (-not $collection) {
        Write-Warning "Collection '$CollectionName' not found"
        return @()
    }
    
    $allSkills = @()
    
    # Process includes first
    if ($collection.Includes) {
        foreach ($include in $collection.Includes) {
            $allSkills += Resolve-CollectionSkills -CollectionName $include -Visited $Visited
        }
    }
    
    # Add this collection's skills
    if ($collection.Skills) {
        $allSkills += $collection.Skills
    }
    
    return $allSkills
}

# Clone or update a GitHub skill source
function Get-SkillSource {
    param($Source, $Commit)
    
    $tempDir = Join-Path $env:TEMP "gg_skills_temp"
    $sourceDir = Join-Path $tempDir ($Source -replace '/', '_')
    
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    if (Test-Path $sourceDir) {
        Write-Info "Updating $Source..."
        Push-Location $sourceDir
        git fetch origin | Out-Null
        git checkout $Commit | Out-Null
        Pop-Location
    } else {
        Write-Info "Cloning $Source..."
        git clone "https://github.com/$Source.git" $sourceDir | Out-Null
        Push-Location $sourceDir
        git checkout $Commit | Out-Null
        Pop-Location
    }
    
    return $sourceDir
}

# Install skills to target project
function Install-Skills {
    param($CollectionNames, $TargetPath)
    
    $TargetPath = Resolve-Path $TargetPath -ErrorAction SilentlyContinue
    if (-not $TargetPath) {
        Write-Error "Target path does not exist"
        return
    }
    
    $targetSkillsDir = Join-Path $TargetPath ".agents\skills"
    if (-not (Test-Path $targetSkillsDir)) {
        New-Item -ItemType Directory -Path $targetSkillsDir -Force | Out-Null
    }
    
    # Collect all skills from all collections
    $allSkills = @()
    $skillsHash = @{}
    
    foreach ($colName in $CollectionNames) {
        Write-Info "Processing collection: $colName"
        $skills = Resolve-CollectionSkills -CollectionName $colName
        
        foreach ($skill in $skills) {
            $key = "$($skill.name)"
            if (-not $skillsHash.ContainsKey($key)) {
                $skillsHash[$key] = $skill
                $allSkills += $skill
            }
        }
    }
    
    Write-Info "Installing $($allSkills.Count) unique skills..."
    
    $installedSkills = @{}
    
    foreach ($skill in $allSkills) {
        Write-Host "  Installing: $($skill.name)" -ForegroundColor Yellow
        
        # Check if it's a custom skill first (in skills/ directory)
        $customSkillPath = Join-Path $SkillsDir $skill.name
        if (Test-Path $customSkillPath) {
            Write-Info "    Source: custom (local)"
            $sourcePath = $customSkillPath
        } else {
            # Download from GitHub
            Write-Info "    Source: $($skill.source)@$($skill.commit.Substring(0,7))"
            $repoPath = Get-SkillSource -Source $skill.source -Commit $skill.commit
            $sourcePath = Join-Path $repoPath "skills\$($skill.name)"
            
            if (-not (Test-Path $sourcePath)) {
                Write-Warning "    Skill not found in source repository, skipping"
                continue
            }
        }
        
        # Copy to target
        $destPath = Join-Path $targetSkillsDir $skill.name
        if (Test-Path $destPath) {
            Remove-Item $destPath -Recurse -Force
        }
        Copy-Item $sourcePath $destPath -Recurse -Force
        
        # Calculate hash for lock file
        $skillFile = Join-Path $destPath "SKILL.md"
        if (Test-Path $skillFile) {
            $hash = (Get-FileHash -Path $skillFile -Algorithm SHA256).Hash.ToLower()
            
            $installedSkills[$skill.name] = @{
                source = $skill.source
                commit = $skill.commit
                sourceType = "github"
                skillPath = "skills/$($skill.name)/SKILL.md"
                computedHash = $hash
            }
        }
        
        Write-Success "    Installed"
    }
    
    # Generate skills-lock.json
    $lockFile = Join-Path $TargetPath "skills-lock.json"
    $lockData = @{
        version = 2
        skills = $installedSkills
    }
    
    $lockData | ConvertTo-Json -Depth 10 | Set-Content $lockFile
    Write-Success "Generated skills-lock.json"
    
    Write-Host "`n" -NoNewline
    Write-Success "Installation complete! Installed $($installedSkills.Count) skills to $TargetPath"
}

# Interactive selection
function Start-InteractiveSelection {
    param($TargetPath)
    
    $collections = Get-Collections
    
    Write-Host "`nGG_Skills Interactive Installer" -ForegroundColor Cyan
    Write-Host "================================`n" -ForegroundColor Cyan
    
    Write-Host "Available collections:`n"
    
    for ($i = 0; $i -lt $collections.Count; $i++) {
        Write-Host "  [$($i + 1)] $($collections[$i].Name)" -ForegroundColor Yellow
        Write-Host "      $($collections[$i].Description)" -ForegroundColor Gray
    }
    
    Write-Host "`n  [0] Exit`n"
    
    $selection = Read-Host "Select collections (comma-separated numbers, e.g., 1,3,5)"
    
    if ($selection -eq "0" -or $selection -eq "") {
        Write-Info "Installation cancelled"
        return
    }
    
    $indices = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
    $selectedCollections = @()
    
    foreach ($idx in $indices) {
        if ($idx -gt 0 -and $idx -le $collections.Count) {
            $selectedCollections += $collections[$idx - 1].Name
        }
    }
    
    if ($selectedCollections.Count -eq 0) {
        Write-Error "No valid collections selected"
        return
    }
    
    Write-Host "`nSelected: $($selectedCollections -join ', ')" -ForegroundColor Green
    $confirm = Read-Host "`nInstall to '$TargetPath'? (y/n)"
    
    if ($confirm -eq 'y' -or $confirm -eq 'Y') {
        Install-Skills -CollectionNames $selectedCollections -TargetPath $TargetPath
    } else {
        Write-Info "Installation cancelled"
    }
}

# Main execution
try {
    if ($List) {
        Show-Collections
        exit 0
    }
    
    if ($Interactive) {
        Start-InteractiveSelection -TargetPath $TargetPath
        exit 0
    }
    
    if ($Collections -eq "") {
        Write-Host "GG_Skills Installer" -ForegroundColor Cyan
        Write-Host "==================`n" -ForegroundColor Cyan
        Write-Host "Usage:"
        Write-Host "  .\install.ps1 -Collections ponytail,git-workflow"
        Write-Host "  .\install.ps1 -Interactive"
        Write-Host "  .\install.ps1 -List`n"
        exit 1
    }
    
    $collectionList = $Collections -split ',' | ForEach-Object { $_.Trim() }
    Install-Skills -CollectionNames $collectionList -TargetPath $TargetPath
    
} catch {
    Write-Error "Installation failed: $_"
    exit 1
}
