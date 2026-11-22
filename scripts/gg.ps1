#!/usr/bin/env pwsh
<#
.SYNOPSIS
    GG_Skills - install and sync AI agent skills into a project.

.DESCRIPTION
    Reads registry.json (sources, skills, collections) and copies skills into
    <Target>/.agents/skills/. State is tracked in <Target>/skills-lock.json.

    Commands:
      list    [-Collection name]                       List collections or their skills
      install -Collections a,b [-Skills x,y]           Add skills (merges the lock)
      init    -Collections a,b [-Skills x,y]           Write skills.json for this project
      sync                                             Install + prune to match skills.json
      save    -SkillName name                          Copy a project skill into skills/
      verify                                           Check installed files against the lock
      doctor                                           Validate registry and lock state

.EXAMPLE
    .\gg.ps1 list

.EXAMPLE
    .\gg.ps1 install -Collections ponytail,core

.EXAMPLE
    cd C:\Projects\MyApp
    powershell C:\Projects\GG_Skills\scripts\gg.ps1 sync
#>

param(
    [Parameter(Position = 0)]
    [string]$Command = "",

    [string[]]$Collections = @(),
    [string[]]$Skills = @(),
    [string]$Collection = "",
    [string]$SkillName = "",
    [string]$Target = ".",
    [switch]$Force,
    [switch]$AllowBranch
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RegistryPath = Join-Path $RepoRoot "registry.json"
$LocalSkillsDir = Join-Path $RepoRoot "skills"
$CacheDir = Join-Path $env:TEMP "gg_skills_cache"

function Write-Ok   { param($Message) Write-Host "  [ok] $Message" -ForegroundColor Green }
function Write-Step { param($Message) Write-Host "  [..] $Message" -ForegroundColor Cyan }
function Write-Skip { param($Message) Write-Host "  [--] $Message" -ForegroundColor DarkGray }
function Write-Warn { param($Message) Write-Host "  [!!] $Message" -ForegroundColor Yellow }
function Write-Err  { param($Message) Write-Host "  [xx] $Message" -ForegroundColor Red }

# ---------------------------------------------------------------- registry

function Get-Registry {
    if (-not (Test-Path $RegistryPath)) { throw "registry.json not found at $RegistryPath" }
    $reg = Get-Content $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($field in @("sources", "skills", "collections")) {
        if (-not $reg.PSObject.Properties[$field]) { throw "registry.json is missing '$field'" }
    }
    return $reg
}

function Test-Registry {
    param($Reg)

    $errors = @()

    foreach ($p in $Reg.sources.PSObject.Properties) {
        if (-not $p.Value.repo)   { $errors += "source '$($p.Name)' has no repo" }
        if (-not $p.Value.commit) { $errors += "source '$($p.Name)' has no commit" }
        elseif (-not $AllowBranch -and $p.Value.commit -notmatch '^[0-9a-f]{7,40}$') {
            $errors += "source '$($p.Name)' is pinned to '$($p.Value.commit)', not a commit SHA (use -AllowBranch to accept)"
        }
    }

    foreach ($p in $Reg.skills.PSObject.Properties) {
        if (-not $Reg.sources.PSObject.Properties[$p.Value.source]) {
            $errors += "skill '$($p.Name)' references unknown source '$($p.Value.source)'"
        }
    }

    foreach ($p in $Reg.collections.PSObject.Properties) {
        $def = $p.Value
        if ($def -is [array]) {
            foreach ($skillName in $def) {
                if (-not $Reg.skills.PSObject.Properties[$skillName] -and -not (Test-Path (Join-Path $LocalSkillsDir $skillName))) {
                    $errors += "collection '$($p.Name)' references unknown skill '$skillName'"
                }
            }
        }
        else {
            if ($def.includes) {
                foreach ($inc in $def.includes) {
                    if (-not $Reg.collections.PSObject.Properties[$inc]) {
                        $errors += "collection '$($p.Name)' includes unknown collection '$inc'"
                    }
                }
            }
            if ($def.skills) {
                foreach ($skillName in $def.skills) {
                    if (-not $Reg.skills.PSObject.Properties[$skillName] -and -not (Test-Path (Join-Path $LocalSkillsDir $skillName))) {
                        $errors += "collection '$($p.Name)' references unknown skill '$skillName'"
                    }
                }
            }
        }
    }

    return $errors
}

function Resolve-Collection {
    param($Reg, [string]$Name, [hashtable]$Visited = @{})

    if ($Visited.ContainsKey($Name)) { return @() }
    $Visited[$Name] = $true

    $prop = $Reg.collections.PSObject.Properties[$Name]
    if (-not $prop) { throw "Unknown collection '$Name'. Run 'gg.ps1 list' to see available collections." }

    $def = $prop.Value
    $names = @()

    if ($def -is [array]) {
        $names += @($def)
    }
    else {
        if ($def.includes) {
            foreach ($inc in $def.includes) {
                $names += Resolve-Collection -Reg $Reg -Name $inc -Visited $Visited
            }
        }
        if ($def.skills) { $names += @($def.skills) }
    }

    return $names
}

function Resolve-Skill {
    param($Reg, [string]$Name)

    $localPath = Join-Path $LocalSkillsDir $Name
    if (Test-Path (Join-Path $localPath "SKILL.md")) {
        return [pscustomobject]@{
            Name       = $Name
            SourceType = "local"
            Source     = "local"
            Repo       = $null
            Commit     = $null
            SubPath    = $null
            LocalPath  = $localPath
        }
    }

    $entry = $Reg.skills.PSObject.Properties[$Name]
    if (-not $entry) { throw "Unknown skill '$Name' (not in registry.json and not in skills/)" }

    $sourceName = $entry.Value.source
    $source = $Reg.sources.PSObject.Properties[$sourceName].Value
    $subPath = if ($entry.Value.path) { $entry.Value.path } else { "skills/$Name" }

    return [pscustomobject]@{
        Name       = $Name
        SourceType = "github"
        Source     = $sourceName
        Repo       = $source.repo
        Commit     = $source.commit
        SubPath    = $subPath
        LocalPath  = $null
    }
}

# -------------------------------------------------------------------- git

function Invoke-Git {
    param([string[]]$GitArgs)

    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git @GitArgs 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    return [pscustomobject]@{ Code = $code; Output = $output }
}

function Get-SourceDir {
    param($Reg, [string]$SourceName)

    $source = $Reg.sources.PSObject.Properties[$SourceName].Value
    $dir = Join-Path $CacheDir $SourceName

    if (-not (Test-Path (Join-Path $dir ".git"))) {
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        Write-Step "Cloning $($source.repo)"
        $clone = Invoke-Git @("clone", "--quiet", "https://github.com/$($source.repo).git", $dir)
        if ($clone.Code -ne 0) { throw "git clone failed for $($source.repo): $($clone.Output -join ' ')" }
    }

    $checkout = Invoke-Git @("-C", $dir, "checkout", "--quiet", "--force", $source.commit)
    if ($checkout.Code -ne 0) {
        $fetch = Invoke-Git @("-C", $dir, "fetch", "--quiet", "origin")
        if ($fetch.Code -ne 0) { throw "git fetch failed for $($source.repo): $($fetch.Output -join ' ')" }
        $checkout = Invoke-Git @("-C", $dir, "checkout", "--quiet", "--force", $source.commit)
        if ($checkout.Code -ne 0) { throw "Cannot checkout '$($source.commit)' in $($source.repo): $($checkout.Output -join ' ')" }
    }

    return $dir
}

# ------------------------------------------------------------------- lock

function Read-Lock {
    param([string]$TargetPath)

    $lockPath = Join-Path $TargetPath "skills-lock.json"
    $lock = [pscustomobject]@{ collections = @(); skills = @{} }
    if (-not (Test-Path $lockPath)) { return $lock }

    $raw = Get-Content $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if ($raw.PSObject.Properties["collections"] -and $raw.collections) {
        $lock.collections = @($raw.collections)
    }

    if ($raw.PSObject.Properties["skills"] -and $raw.skills) {
        foreach ($p in $raw.skills.PSObject.Properties) {
            $entry = $p.Value
            $hash = $null
            if ($entry.hash) { $hash = $entry.hash }
            elseif ($entry.computedHash) { $hash = $entry.computedHash }

            $sourceType = "github"
            if ($entry.sourceType) { $sourceType = $entry.sourceType }

            $lock.skills[$p.Name] = [ordered]@{
                source     = $entry.source
                sourceType = $sourceType
                repo       = $entry.repo
                commit     = $entry.commit
                hash       = $hash
            }
        }
    }

    return $lock
}

function Write-Lock {
    param([string]$TargetPath, $Lock)

    $ordered = [ordered]@{
        version     = 3
        collections = @($Lock.collections)
        skills      = [ordered]@{}
    }

    foreach ($name in ($Lock.skills.Keys | Sort-Object)) {
        $ordered.skills[$name] = $Lock.skills[$name]
    }

    $json = $ordered | ConvertTo-Json -Depth 10
    $lockPath = Join-Path $TargetPath "skills-lock.json"
    [System.IO.File]::WriteAllText($lockPath, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

# ---------------------------------------------------------------- install

function Get-SkillHash {
    param([string]$SkillDir)

    $file = Join-Path $SkillDir "SKILL.md"
    if (-not (Test-Path $file)) { return $null }
    return (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
}

function Resolve-Target {
    param([string]$TargetPath)

    $resolved = Resolve-Path $TargetPath -ErrorAction SilentlyContinue
    if (-not $resolved) { throw "Target path not found: $TargetPath" }
    return $resolved.Path
}

function Install-One {
    param($Reg, $Skill, [string]$TargetPath, $Lock)

    $dest = Join-Path (Join-Path $TargetPath ".agents\skills") $Skill.Name

    if ($Skill.SourceType -eq "local") {
        $sourcePath = $Skill.LocalPath
    }
    else {
        $repoDir = Get-SourceDir -Reg $Reg -SourceName $Skill.Source
        $sourcePath = Join-Path $repoDir ($Skill.SubPath -replace '/', '\')
        if (-not (Test-Path (Join-Path $sourcePath "SKILL.md"))) {
            throw "Skill '$($Skill.Name)' not found at '$($Skill.SubPath)' in $($Skill.Repo)@$($Skill.Commit)"
        }
    }

    $sourceHash = Get-SkillHash $sourcePath

    if (-not $Force -and (Test-Path (Join-Path $dest "SKILL.md"))) {
        $destHash = Get-SkillHash $dest
        if ($destHash -eq $sourceHash) {
            Write-Skip "$($Skill.Name) (up to date)"
            $Lock.skills[$Skill.Name] = [ordered]@{
                source     = $Skill.Source
                sourceType = $Skill.SourceType
                repo       = $Skill.Repo
                commit     = $Skill.Commit
                hash       = $sourceHash
            }
            return
        }
    }

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item $sourcePath $dest -Recurse -Force

    $Lock.skills[$Skill.Name] = [ordered]@{
        source     = $Skill.Source
        sourceType = $Skill.SourceType
        repo       = $Skill.Repo
        commit     = $Skill.Commit
        hash       = $sourceHash
    }

    Write-Ok "$($Skill.Name)"
}

function Split-List {
    param([string[]]$Values)

    $out = @()
    foreach ($value in $Values) {
        if (-not $value) { continue }
        $out += ($value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    return $out
}

function Get-DesiredSkills {
    param($Reg, [string[]]$CollectionNames, [string[]]$SkillNames)

    $names = @()
    foreach ($collectionName in $CollectionNames) {
        $names += Resolve-Collection -Reg $Reg -Name $collectionName
    }
    $names += $SkillNames
    return @($names | Where-Object { $_ } | Select-Object -Unique)
}

function Invoke-Install {
    param($Reg, [string[]]$CollectionNames, [string[]]$SkillNames, [string]$TargetPath)

    $TargetPath = Resolve-Target $TargetPath
    $desired = Get-DesiredSkills -Reg $Reg -CollectionNames $CollectionNames -SkillNames $SkillNames
    if ($desired.Count -eq 0) { throw "Nothing to install. Use -Collections and/or -Skills." }

    $lock = Read-Lock $TargetPath
    Write-Host "Installing $($desired.Count) skills into $TargetPath"

    foreach ($name in $desired) {
        Install-One -Reg $Reg -Skill (Resolve-Skill -Reg $Reg -Name $name) -TargetPath $TargetPath -Lock $lock
    }

    foreach ($collectionName in $CollectionNames) {
        if ($lock.collections -notcontains $collectionName) { $lock.collections += $collectionName }
    }

    Write-Lock -TargetPath $TargetPath -Lock $lock
    Write-Ok "lock: $($lock.skills.Count) skills tracked"
}

# ------------------------------------------------------------------- sync

function Invoke-Init {
    param($Reg, [string[]]$CollectionNames, [string[]]$SkillNames, [string]$TargetPath)

    $TargetPath = Resolve-Target $TargetPath
    $manifestPath = Join-Path $TargetPath "skills.json"

    if ((Test-Path $manifestPath) -and -not $Force) {
        throw "skills.json already exists in $TargetPath (use -Force to overwrite)"
    }

    foreach ($collectionName in $CollectionNames) {
        $null = Resolve-Collection -Reg $Reg -Name $collectionName
    }
    foreach ($skillName in $SkillNames) {
        $null = Resolve-Skill -Reg $Reg -Name $skillName
    }

    $manifest = [ordered]@{
        collections = @($CollectionNames | Where-Object { $_ })
        skills      = @($SkillNames | Where-Object { $_ })
    }

    $json = $manifest | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($manifestPath, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "wrote $manifestPath"
}

function Invoke-Sync {
    param($Reg, [string]$TargetPath)

    $TargetPath = Resolve-Target $TargetPath
    $manifestPath = Join-Path $TargetPath "skills.json"
    if (-not (Test-Path $manifestPath)) {
        throw "No skills.json in $TargetPath. Run 'gg.ps1 init -Collections ...' first."
    }

    $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $collectionNames = @()
    $skillNames = @()
    if ($manifest.collections) { $collectionNames = @($manifest.collections) }
    if ($manifest.skills) { $skillNames = @($manifest.skills) }

    $desired = Get-DesiredSkills -Reg $Reg -CollectionNames $collectionNames -SkillNames $skillNames
    $lock = Read-Lock $TargetPath

    Write-Host "Syncing $($desired.Count) skills into $TargetPath"

    foreach ($name in $desired) {
        Install-One -Reg $Reg -Skill (Resolve-Skill -Reg $Reg -Name $name) -TargetPath $TargetPath -Lock $lock
    }

    $pruned = @()
    foreach ($name in @($lock.skills.Keys)) {
        if ($desired -notcontains $name) {
            $dest = Join-Path (Join-Path $TargetPath ".agents\skills") $name
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            $lock.skills.Remove($name)
            $pruned += $name
        }
    }
    foreach ($name in $pruned) { Write-Skip "pruned $name" }

    $lock.collections = @($collectionNames)
    Write-Lock -TargetPath $TargetPath -Lock $lock
    Write-Ok "synced: $($lock.skills.Count) skills tracked, $($pruned.Count) pruned"
}

# ------------------------------------------------------------ verify/save

function Invoke-Verify {
    param([string]$TargetPath)

    $TargetPath = Resolve-Target $TargetPath
    $lock = Read-Lock $TargetPath
    $skillsDir = Join-Path $TargetPath ".agents\skills"

    if ($lock.skills.Count -eq 0) {
        Write-Warn "lock is empty - nothing to verify"
        return 0
    }

    $problems = 0
    foreach ($name in ($lock.skills.Keys | Sort-Object)) {
        $entry = $lock.skills[$name]
        $hash = Get-SkillHash (Join-Path $skillsDir $name)

        if (-not $hash) {
            Write-Err "$name missing (.agents\skills\$name\SKILL.md)"
            $problems++
        }
        elseif ($entry.hash -and $hash -ne $entry.hash) {
            Write-Err "$name modified (hash mismatch)"
            $problems++
        }
        else {
            Write-Ok $name
        }
    }

    if ($problems -gt 0) {
        Write-Err "$problems skill(s) failed verification"
        return 1
    }

    Write-Ok "all $($lock.skills.Count) skills verified"
    return 0
}

function Invoke-Save {
    param([string]$Name, [string]$TargetPath)

    if (-not $Name) { throw "Use -SkillName <name>" }

    $TargetPath = Resolve-Target $TargetPath
    $source = Join-Path (Join-Path $TargetPath ".agents\skills") $Name
    if (-not (Test-Path (Join-Path $source "SKILL.md"))) {
        throw "No skill '$Name' in $TargetPath\.agents\skills"
    }

    $dest = Join-Path $LocalSkillsDir $Name
    if ((Test-Path $dest) -and -not $Force) {
        throw "skills\$Name already exists (use -Force to overwrite)"
    }

    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $LocalSkillsDir -Force | Out-Null
    Copy-Item $source $dest -Recurse -Force

    Write-Ok "saved skills\$Name"
    Write-Warn "add '$Name' to a collection in registry.json to make it installable"
}

# ------------------------------------------------------------------ doctor

function Invoke-Doctor {
    param($Reg, [string]$TargetPath)

    $errors = @(Test-Registry -Reg $Reg)
    if ($errors.Count -gt 0) {
        foreach ($errorMessage in $errors) { Write-Err $errorMessage }
        Write-Err "registry: $($errors.Count) problem(s)"
        return 1
    }

    $collectionCount = @($Reg.collections.PSObject.Properties).Count
    $sourceCount = @($Reg.sources.PSObject.Properties).Count
    $skillCount = @($Reg.skills.PSObject.Properties).Count
    Write-Ok "registry: $sourceCount sources, $skillCount skills, $collectionCount collections"

    $resolved = Resolve-Target $TargetPath
    $lock = Read-Lock $resolved
    $skillsDir = Join-Path $resolved ".agents\skills"

    if (-not (Test-Path $skillsDir)) {
        Write-Ok "no .agents\skills in target"
        return 0
    }

    $orphans = @()
    foreach ($dir in Get-ChildItem $skillsDir -Directory) {
        if (-not $lock.skills.ContainsKey($dir.Name)) { $orphans += $dir.Name }
    }

    foreach ($name in $orphans) { Write-Warn "orphan skill not in lock: $name" }
    Write-Ok "target: $($lock.skills.Count) tracked, $($orphans.Count) orphan(s)"
    return 0
}

# -------------------------------------------------------------------- main

function Show-List {
    param($Reg, [string]$CollectionName)

    if ($CollectionName) {
        $names = Resolve-Collection -Reg $Reg -Name $CollectionName
        Write-Host "Collection '$CollectionName' ($($names.Count) skills)"
        foreach ($name in $names) { Write-Host "  $name" }
        return
    }

    Write-Host "Collections"
    foreach ($p in $Reg.collections.PSObject.Properties) {
        $count = @(Resolve-Collection -Reg $Reg -Name $p.Name).Count
        $description = ""
        if ($p.Value.description) { $description = " - $($p.Value.description)" }
        Write-Host ("  {0,-14} {1,3} skills{2}" -f $p.Name, $count, $description)
    }
}

function Show-Help {
    Write-Host @"
GG_Skills

Simplest use:
  gg core        install the 'core' collection into the current project
  gg list        show collections
  gg sync        sync a project to its skills.json

Commands:
  gg list    [-Collection name]
  gg install -Collections a,b [-Skills x,y] [-Target path] [-Force]
  gg init    -Collections a,b [-Skills x,y] [-Target path] [-Force]
  gg sync    [-Target path] [-Force]
  gg save    -SkillName name [-Target path] [-Force]
  gg verify  [-Target path]
  gg doctor  [-Target path]

Or type a collection name instead of 'install'.
"@
}

try {
    if ($Command -eq "") {
        Show-Help
        exit 0
    }

    $reg = Get-Registry

    if ($Command.ToLower() -ne "doctor") {
        $registryErrors = @(Test-Registry -Reg $reg)
        if ($registryErrors.Count -gt 0) {
            foreach ($errorMessage in $registryErrors) { Write-Err $errorMessage }
            exit 1
        }
    }

    # Shortcut: "gg core" means "gg install -Collections core"
    $verb = $Command.ToLower()
    $verbs = @("list", "install", "init", "sync", "save", "verify", "doctor", "help")
    if ($verbs -notcontains $verb) {
        if ($reg.collections.PSObject.Properties[$Command]) {
            $Collections = @($Command)
            $verb = "install"
        }
    }

    switch ($verb) {
        "list" {
            Show-List -Reg $reg -CollectionName $Collection
            exit 0
        }
        "install" {
            Invoke-Install -Reg $reg -CollectionNames (Split-List $Collections) -SkillNames (Split-List $Skills) -TargetPath $Target
            exit 0
        }
        "init" {
            Invoke-Init -Reg $reg -CollectionNames (Split-List $Collections) -SkillNames (Split-List $Skills) -TargetPath $Target
            exit 0
        }
        "sync" {
            Invoke-Sync -Reg $reg -TargetPath $Target
            exit 0
        }
        "save" {
            Invoke-Save -Name $SkillName -TargetPath $Target
            exit 0
        }
        "verify" {
            exit (Invoke-Verify -TargetPath $Target)
        }
        "doctor" {
            exit (Invoke-Doctor -Reg $reg -TargetPath $Target)
        }
        "help" {
            Show-Help
            exit 0
        }
        default {
            Write-Err "Unknown command '$Command'"
            Show-Help
            exit 1
        }
    }
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
