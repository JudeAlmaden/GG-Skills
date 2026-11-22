# Offline tests for scripts/gg.ps1. No Pester, no network.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests/gg.tests.ps1

$ErrorActionPreference = "Stop"

. (Join-Path (Split-Path $PSScriptRoot -Parent) "scripts\gg.ps1")

$script:Failures = 0
$script:Passes = 0

function Check {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        $script:Passes++
        Write-Host "  [ok] $Name" -ForegroundColor Green
    }
    else {
        $script:Failures++
        Write-Host "  [xx] $Name" -ForegroundColor Red
    }
}

$tempRoot = Join-Path $env:TEMP ("gg-tests-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    $reg = Get-Registry

    Write-Host "registry"
    Check (@(Test-Registry -Reg $reg).Count -eq 0) "registry validates"
    Check (@(Resolve-Collection -Reg $reg -Name "all").Count -eq @($reg.skills.PSObject.Properties).Count) "collection 'all' resolves to every skill"
    Check (@(Resolve-Collection -Reg $reg -Name "core") -contains "ponytail") "collection 'core' includes ponytail"

    Write-Host "picker"
    $target = Join-Path $tempRoot "picker"
    New-Item -ItemType Directory -Path (Join-Path $target ".agents\skills\ponytail-audit") -Force | Out-Null
    Set-Content (Join-Path $target ".agents\skills\ponytail-audit\SKILL.md") "x"

    $librarySkills = @()
    if (Test-Path $LocalSkillsDir) {
        $librarySkills = @(Get-ChildItem $LocalSkillsDir -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } |
            ForEach-Object { $_.Name })
    }
    $expectedNames = @(@($reg.skills.PSObject.Properties.Name) + $librarySkills | Select-Object -Unique)

    $rows = @(Get-PickerRows -Reg $reg -TargetPath $target)
    $skillRows = @($rows | Where-Object { $_.Kind -eq "skill" })
    Check ($skillRows.Count -eq $expectedNames.Count) "picker lists every registry and library skill"
    Check (@($skillRows | Where-Object { $_.Installed }).Count -eq 1) "picker pre-ticks installed skills"
    Check (@($rows | Where-Object { $_.Kind -eq "header" -and $_.Label -eq "collections" }).Count -eq 1) "picker has a collections header"

    Write-Host "prune"
    $pruneTarget = Join-Path $tempRoot "prune"
    New-Item -ItemType Directory -Path (Join-Path $pruneTarget ".agents\skills\ponytail-audit") -Force | Out-Null
    Set-Content (Join-Path $pruneTarget ".agents\skills\ponytail-audit\SKILL.md") "x"
    $lock = [ordered]@{
        version     = 3
        collections = @()
        skills      = [ordered]@{ "ponytail-audit" = [ordered]@{ source = "ponytail"; sourceType = "github"; repo = "DietrichGebert/ponytail"; commit = "ebd8654"; hash = "deadbeef" } }
    }
    [System.IO.File]::WriteAllText((Join-Path $pruneTarget "skills-lock.json"), ($lock | ConvertTo-Json -Depth 10))

    Invoke-PickerApply -Reg $reg -Chosen @("ponytail") -TargetPath $pruneTarget
    Check (-not (Test-Path (Join-Path $pruneTarget ".agents\skills\ponytail-audit"))) "unticked skill is pruned"
    $after = Read-Lock $pruneTarget
    Check (-not $after.skills.ContainsKey("ponytail-audit")) "pruned skill leaves the lock"

    Write-Host "verify"
    $verifyTarget = Join-Path $tempRoot "verify"
    New-Item -ItemType Directory -Path (Join-Path $verifyTarget ".agents\skills\ponytail") -Force | Out-Null
    Set-Content (Join-Path $verifyTarget ".agents\skills\ponytail\SKILL.md") "tampered"
    $verifyLock = [ordered]@{
        version     = 3
        collections = @()
        skills      = [ordered]@{ "ponytail" = [ordered]@{ source = "ponytail"; sourceType = "github"; repo = "DietrichGebert/ponytail"; commit = "ebd8654"; hash = "0000" } }
    }
    [System.IO.File]::WriteAllText((Join-Path $verifyTarget "skills-lock.json"), ($verifyLock | ConvertTo-Json -Depth 10))
    Check ((Invoke-Verify -TargetPath $verifyTarget) -eq 1) "verify reports a hash mismatch as failure"

    Write-Host "add-source helpers"
    $skillDir = Join-Path $tempRoot "fm\my-skill"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    Set-Content (Join-Path $skillDir "SKILL.md") "---`nname: renamed-skill`ndescription: x`n---`n`nbody"
    Check ((Get-SkillFrontmatterName -Path (Join-Path $skillDir "SKILL.md")) -eq "renamed-skill") "frontmatter name is read"

    $registryText = [System.IO.File]::ReadAllText((Join-Path (Split-Path $PSScriptRoot -Parent) "registry.json"))
    $snippet = "    `"test-source`": {`n      `"repo`": `"owner/repo`",`n      `"commit`": `"abc`"`n    }"
    $updated = Add-JsonBlock -Text $registryText -Key "sources" -Block $snippet
    $parsed = $updated | ConvertFrom-Json
    Check ($parsed.sources.PSObject.Properties["test-source"].Value.repo -eq "owner/repo") "Add-JsonBlock inserts a source entry"
    Check (@($parsed.sources.PSObject.Properties).Count -eq (@($reg.sources.PSObject.Properties).Count + 1)) "Add-JsonBlock keeps existing sources"
    Check (@($parsed.skills.PSObject.Properties).Count -eq @($reg.skills.PSObject.Properties).Count) "Add-JsonBlock leaves other blocks alone"
}
finally {
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

Write-Host ""
if ($script:Failures -gt 0) {
    Write-Host "$($script:Failures) failed, $($script:Passes) passed" -ForegroundColor Red
    exit 1
}
Write-Host "$($script:Passes) passed" -ForegroundColor Green
exit 0
