#!/usr/bin/env pwsh
<#
.SYNOPSIS
    List all available skills in GG_Skills collections.

.DESCRIPTION
    Shows all collections and their skills, or details about a specific collection.

.PARAMETER Collection
    Show details for a specific collection

.PARAMETER Custom
    Show only custom/local skills

.EXAMPLE
    .\list-skills.ps1
    
.EXAMPLE
    .\list-skills.ps1 -Collection ponytail
    
.EXAMPLE
    .\list-skills.ps1 -Custom
#>

param(
    [string]$Collection = "",
    [switch]$Custom
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$CollectionsDir = Join-Path $RepoRoot "collections"
$CustomSkillsDir = Join-Path $RepoRoot "skills"

function Get-Collections {
    $collections = @()
    Get-ChildItem -Path $CollectionsDir -Filter "*.json" | ForEach-Object {
        $content = Get-Content $_.FullName | ConvertFrom-Json
        $collections += [PSCustomObject]@{
            Name = $content.name
            Description = $content.description
            Skills = $content.skills
            Includes = $content.includes
        }
    }
    return $collections
}

function Show-CollectionDetails {
    param($CollectionName)
    
    $collections = Get-Collections
    $col = $collections | Where-Object { $_.Name -eq $CollectionName } | Select-Object -First 1
    
    if (-not $col) {
        Write-Host "Collection '$CollectionName' not found" -ForegroundColor Red
        return
    }
    
    Write-Host "`n$($col.Name)" -ForegroundColor Cyan
    Write-Host ("=" * $col.Name.Length) -ForegroundColor Cyan
    Write-Host $col.Description -ForegroundColor Gray
    Write-Host ""
    
    if ($col.Includes) {
        Write-Host "Includes collections:" -ForegroundColor Yellow
        foreach ($inc in $col.Includes) {
            Write-Host "  - $inc" -ForegroundColor White
        }
        Write-Host ""
    }
    
    if ($col.Skills) {
        Write-Host "Skills ($($col.Skills.Count)):" -ForegroundColor Yellow
        foreach ($skill in $col.Skills) {
            Write-Host "  - $($skill.name)" -ForegroundColor White
            Write-Host "    Source: $($skill.source)" -ForegroundColor DarkGray
            if ($skill.commit) {
                $commitDisplay = if ($skill.commit.Length -gt 7) { $skill.commit.Substring(0,7) } else { $skill.commit }
                Write-Host "    Commit: $commitDisplay" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host ""
}

function Show-CustomSkills {
    Write-Host "`nCustom Skills" -ForegroundColor Cyan
    Write-Host "=============" -ForegroundColor Cyan
    Write-Host "Location: $CustomSkillsDir`n" -ForegroundColor Gray
    
    if (-not (Test-Path $CustomSkillsDir)) {
        Write-Host "No custom skills directory found." -ForegroundColor Yellow
        Write-Host "Create custom skills with: .\save-skill.ps1 -SkillName NAME`n" -ForegroundColor Gray
        return
    }
    
    $customSkills = Get-ChildItem -Path $CustomSkillsDir -Directory
    
    if ($customSkills.Count -eq 0) {
        Write-Host "No custom skills yet." -ForegroundColor Yellow
        Write-Host "Create custom skills with: .\save-skill.ps1 -SkillName NAME`n" -ForegroundColor Gray
        return
    }
    
    foreach ($skill in $customSkills) {
        $skillFile = Join-Path $skill.FullName "SKILL.md"
        Write-Host "  $($skill.Name)" -ForegroundColor Yellow
        
        if (Test-Path $skillFile) {
            $content = Get-Content $skillFile -Raw
            if ($content -match "description:\s*>?\s*\n\s*(.+?)(\n\w+:|---)") {
                $desc = $matches[1].Trim()
                Write-Host "    $desc" -ForegroundColor Gray
            }
            Write-Host "    SKILL.md exists" -ForegroundColor DarkGray
        } else {
            Write-Host "    SKILL.md missing" -ForegroundColor Red
        }
        Write-Host ""
    }
}

try {
    if ($Custom) {
        Show-CustomSkills
        exit 0
    }
    
    if ($Collection -ne "") {
        Show-CollectionDetails -CollectionName $Collection
        exit 0
    }
    
    # Show all collections
    Write-Host "`nGG_Skills Collections" -ForegroundColor Cyan
    Write-Host "=====================`n" -ForegroundColor Cyan
    
    $collections = Get-Collections
    
    foreach ($col in $collections) {
        Write-Host "  $($col.Name)" -ForegroundColor Yellow
        Write-Host "    $($col.Description)" -ForegroundColor Gray
        
        if ($col.Includes) {
            Write-Host "    Type: Meta-collection (includes $($col.Includes.Count) collections)" -ForegroundColor DarkGray
        } else {
            $skillCount = ($col.Skills | Measure-Object).Count
            Write-Host "    Skills: $skillCount" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
    
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  .\list-skills.ps1 -Collection NAME  Show collection details"
    Write-Host "  .\list-skills.ps1 -Custom           Show custom skills"
    Write-Host ""
    
} catch {
    $errMsg = $_.Exception.Message
    Write-Host "Error: $errMsg" -ForegroundColor Red
    exit 1
}
