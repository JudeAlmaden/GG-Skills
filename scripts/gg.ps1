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
    [string]$Repo = "",
    [string]$Ref = "",
    [string]$Source = "",
    [string]$Target = ".",
    [switch]$Force,
    [switch]$AllowBranch,
    [switch]$Write
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
    Write-Warn "add '$Name' to a collection in registry.json to install it with -Collections or sync"
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

# --------------------------------------------------------------- add-source

function Get-SkillFrontmatterName {
    param([string]$Path)

    $lines = @(Get-Content $Path -TotalCount 30 -Encoding UTF8)
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne "---") { return $null }

    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "---") { break }
        if ($lines[$i] -match '^name:\s*(.+?)\s*$') {
            $value = $matches[1].Trim().Trim('"', "'")
            if ($value) { return $value }
        }
    }
    return $null
}

function Add-JsonBlock {
    param([string]$Text, [string]$Key, [string]$Block)

    $newline = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($Text -split "`r?`n")) { $lines.Add($line) }

    $openIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('^\s*"' + [regex]::Escape($Key) + '"\s*:\s*\{\s*$')) { $openIndex = $i; break }
    }
    if ($openIndex -lt 0) { throw "registry.json: cannot find the `"$Key`" object" }

    $depth = 0
    $closeIndex = -1
    for ($i = $openIndex; $i -lt $lines.Count; $i++) {
        $depth += ([regex]::Matches($lines[$i], '\{')).Count
        $depth -= ([regex]::Matches($lines[$i], '\}')).Count
        if ($i -gt $openIndex -and $depth -le 0) { $closeIndex = $i; break }
    }
    if ($closeIndex -lt 0) { throw "registry.json: cannot find the end of the `"$Key`" object" }

    $previous = $closeIndex - 1
    while ($previous -gt $openIndex -and $lines[$previous].Trim() -eq "") { $previous-- }
    if ($previous -gt $openIndex -and -not $lines[$previous].TrimEnd().EndsWith(",")) {
        $lines[$previous] = $lines[$previous].TrimEnd() + ","
    }

    $lines.InsertRange($closeIndex, [string[]]@($Block -split "`r?`n"))
    return ($lines -join $newline)
}

function Invoke-AddSource {
    param($Reg, [string]$Repo, [string]$Ref, [string]$SourceName, [switch]$Write)

    if (-not $Repo) { throw "Use -Repo owner/name" }

    $Repo = $Repo.Trim()
    $Repo = $Repo -replace '^https?://github\.com/', ''
    $Repo = $Repo -replace '\.git$', ''
    $Repo = $Repo.Trim('/')

    $parts = @($Repo -split '/')
    if ($parts.Count -ne 2 -or -not $parts[0] -or -not $parts[1]) {
        throw "Use -Repo owner/name (got '$Repo')"
    }

    $scanDir = Join-Path $CacheDir ("add-source_" + (($parts -join "_") -replace '[^a-zA-Z0-9._-]', "_"))
    if (Test-Path $scanDir) { Remove-Item $scanDir -Recurse -Force }
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null

    Write-Step "Cloning $Repo"
    $clone = Invoke-Git @("clone", "--quiet", "https://github.com/$Repo.git", $scanDir)
    if ($clone.Code -ne 0) { throw "git clone failed for ${Repo}: $($clone.Output -join ' ')" }

    if ($Ref) {
        Write-Step "Checking out $Ref"
        $checkout = Invoke-Git @("-C", $scanDir, "checkout", "--quiet", "--force", $Ref)
        if ($checkout.Code -ne 0) { throw "Cannot check out '$Ref' in ${Repo}: $($checkout.Output -join ' ')" }
    }

    $revParse = Invoke-Git @("-C", $scanDir, "rev-parse", "HEAD")
    if ($revParse.Code -ne 0) { throw "git rev-parse failed in $Repo" }
    $commit = ($revParse.Output | Out-String).Trim()
    if ($commit -notmatch '^[0-9a-f]{40}$') { throw "Could not resolve a commit SHA for $Repo (got '$commit')" }

    $sourceName = if ($SourceName) { $SourceName } else { $parts[1] }
    $sourceName = $sourceName.ToLower() -replace '[^a-z0-9-]+', '-'
    $sourceName = $sourceName.Trim('-')
    if (-not $sourceName) { throw "Cannot derive a source name; pass -Source <name>" }
    if ($Reg.sources.PSObject.Properties[$sourceName]) { throw "Source '$sourceName' is already in registry.json" }

    $fallbackName = $parts[1]
    $found = @()
    foreach ($file in Get-ChildItem $scanDir -Recurse -Filter "SKILL.md" -File) {
        if ($file.FullName -match '[\\/]\.git[\\/]') { continue }

        $relative = $file.Directory.FullName.Substring($scanDir.Length).TrimStart('\', '/') -replace '\\', '/'
        if (-not $relative) { $relative = "." }

        $name = Get-SkillFrontmatterName -Path $file.FullName
        if (-not $name) { $name = if ($relative -eq ".") { $fallbackName } else { Split-Path $relative -Leaf } }

        $found += [pscustomobject]@{ Name = $name; Path = $relative }
    }

    if ($found.Count -eq 0) { throw "No SKILL.md found in $Repo@$commit" }

    $kept = @()
    $seen = @{}
    foreach ($item in ($found | Sort-Object Path)) {
        if ($seen.ContainsKey($item.Name)) {
            Write-Warn "duplicate skill name '$($item.Name)' at $($item.Path) (ignored)"
            continue
        }
        if ($Reg.skills.PSObject.Properties[$item.Name]) {
            Write-Warn "skill '$($item.Name)' is already in the registry (ignored)"
            continue
        }
        $seen[$item.Name] = $true
        $kept += $item
    }
    if ($kept.Count -eq 0) { throw "No new skills to add from $Repo@$commit" }

    Write-Host ""
    Write-Host "$Repo @ $commit"
    Write-Host "source: $sourceName"
    foreach ($item in $kept) {
        Write-Host ("  {0,-34} {1}" -f $item.Name, $item.Path)
    }
    Write-Host ""

    $sourceBlock = "    `"$sourceName`": {`n      `"repo`": `"$Repo`",`n      `"commit`": `"$commit`"`n    }"

    $skillLines = @()
    for ($i = 0; $i -lt $kept.Count; $i++) {
        $item = $kept[$i]
        if ($item.Path -eq "skills/$($item.Name)") {
            $entry = "    `"$($item.Name)`": { `"source`": `"$sourceName`" }"
        }
        else {
            $entry = "    `"$($item.Name)`": { `"source`": `"$sourceName`", `"path`": `"$($item.Path)`" }"
        }
        if ($i -lt ($kept.Count - 1)) { $entry += "," }
        $skillLines += $entry
    }
    $skillsBlock = ($skillLines -join "`n")

    if (-not $Write) {
        Write-Host "Add to the `"sources`" block of registry.json:"
        Write-Host ""
        Write-Host ($sourceBlock + ",")
        Write-Host ""
        Write-Host "Add to the `"skills`" block of registry.json:"
        Write-Host ""
        Write-Host $skillsBlock
        Write-Host ""
        Write-Host "Then add the names to a collection to make them installable by name:"
        Write-Host "  gg install -Skills $($kept.Name -join ',')"
        Write-Host ""
        Write-Host "Or re-run with -Write to edit registry.json for you."
        return
    }

    $original = [System.IO.File]::ReadAllText($RegistryPath)
    $updated = Add-JsonBlock -Text $original -Key "sources" -Block $sourceBlock
    $updated = Add-JsonBlock -Text $updated -Key "skills" -Block $skillsBlock

    try { $candidate = $updated | ConvertFrom-Json }
    catch { throw "Refusing to write registry.json: the generated file is not valid JSON. $_" }

    $registryErrors = @(Test-Registry -Reg $candidate)
    if ($registryErrors.Count -gt 0) {
        foreach ($errorMessage in $registryErrors) { Write-Err $errorMessage }
        throw "Refusing to write registry.json: $($registryErrors.Count) registry problem(s)"
    }

    [System.IO.File]::WriteAllText($RegistryPath, $updated, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok "wrote $sourceName -> registry.json ($($kept.Count) skill(s))"
    Write-Warn "add the names to a collection in registry.json to install them with -Collections or sync"
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

  gg                      pick skills from a checklist (easiest)
  gg list                 show collections
  gg install -Collections a,b   install specific collections
  gg add-source -Repo owner/name  pin a repo and add its skills
  gg init -Collections a,b      write skills.json for this project
  gg sync                 install + prune to match skills.json
  gg save -SkillName name copy a project skill into the library
  gg verify               check installed files
  gg doctor               check the registry

All commands act on the current folder unless you add -Target path.
"@
}

function Get-InstalledSkillNames {
    param([string]$TargetPath)

    $skillsDir = Join-Path $TargetPath ".agents\skills"
    $names = @()
    if (Test-Path $skillsDir) {
        foreach ($dir in Get-ChildItem $skillsDir -Directory) {
            if (Test-Path (Join-Path $dir.FullName "SKILL.md")) { $names += $dir.Name }
        }
    }
    return $names
}

function Get-PickerRows {
    param($Reg, [string]$TargetPath)

    $installed = Get-InstalledSkillNames -TargetPath $TargetPath

    $bySource = [ordered]@{}
    foreach ($p in $Reg.sources.PSObject.Properties) { $bySource[$p.Name] = @() }
    if (-not $bySource.Contains("local")) { $bySource["local"] = @() }

    foreach ($p in $Reg.skills.PSObject.Properties) { $bySource[$p.Value.source] += $p.Name }

    if (Test-Path $LocalSkillsDir) {
        foreach ($dir in Get-ChildItem $LocalSkillsDir -Directory) {
            if (-not (Test-Path (Join-Path $dir.FullName "SKILL.md"))) { continue }
            if ($Reg.skills.PSObject.Properties[$dir.Name]) { continue }
            $bySource["local"] += $dir.Name
        }
    }

    # A collection that is exactly one source group would just duplicate its header.
    $sourceSets = @()
    foreach ($groupName in @($bySource.Keys)) {
        $members = @($bySource[$groupName])
        if ($members.Count -gt 0) { $sourceSets += (($members | Sort-Object) -join "|") }
    }

    $rows = @()

    $shownCollections = 0
    foreach ($p in $Reg.collections.PSObject.Properties) {
        $members = @(Resolve-Collection -Reg $Reg -Name $p.Name)
        if ($members.Count -eq 0) { continue }
        if ($sourceSets -contains (($members | Sort-Object) -join "|")) { continue }
        if ($shownCollections -eq 0) {
            $rows += [pscustomobject]@{ Kind = "header"; Label = "collections"; Name = $null; Members = @(); Installed = $false }
        }
        $rows += [pscustomobject]@{
            Kind      = "group"
            Label     = $p.Name
            Name      = $null
            Members   = $members
            Installed = $false
        }
        $shownCollections++
    }

    foreach ($groupName in @($bySource.Keys)) {
        $members = @($bySource[$groupName])
        if ($members.Count -eq 0) { continue }
        $rows += [pscustomobject]@{ Kind = "group"; Label = $groupName; Name = $null; Members = $members; Installed = $false }
        foreach ($member in $members) {
            $rows += [pscustomobject]@{
                Kind      = "skill"
                Label     = $member
                Name      = $member
                Members   = @()
                Installed = ($installed -contains $member)
            }
        }
    }
    return $rows
}

function Write-PickerLine {
    param([string]$Text, [int]$Width, [string]$Color = "")

    if ($null -eq $Text) { $Text = "" }
    if ($Text.Length -ge $Width) { $Text = $Text.Substring(0, $Width) }
    else { $Text = $Text.PadRight($Width) }

    if ($Color) { Write-Host $Text -ForegroundColor $Color }
    else { Write-Host $Text }
}

function Start-Picker {
    param($Reg)

    if ([Console]::IsInputRedirected) {
        throw "No interactive terminal. Use 'gg list' or 'gg install -Collections <name>' instead."
    }

    $target = (Get-Location).Path
    $rows = @(Get-PickerRows -Reg $Reg -TargetPath $target)
    if ($rows.Count -eq 0) { Write-Warn "registry has no skills to pick from"; return @() }

    $nav = @()
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($rows[$i].Kind -ne "header") { $nav += $i }
    }
    $skillRows = @($nav | Where-Object { $rows[$_].Kind -eq "skill" })
    if ($skillRows.Count -eq 0) { Write-Warn "registry has no skills to pick from"; return @() }

    $ticked = @{}
    foreach ($i in $skillRows) { $ticked[$rows[$i].Name] = [bool]$rows[$i].Installed }

    $cursor = 0
    $offset = 0
    $notice = ""
    $drawn = $false

    $width = 78
    $bodyHeight = 20
    try {
        $width = [Math]::Min([Math]::Max([Console]::WindowWidth - 1, 20), 100)
        $bodyHeight = [Math]::Max(4, [Console]::WindowHeight - 6)
    }
    catch { }

    while ($true) {
        if ($cursor -lt $offset) { $offset = $cursor }
        if ($cursor -gt ($offset + $bodyHeight - 1)) { $offset = $cursor - $bodyHeight + 1 }
        $maxOffset = [Math]::Max(0, $rows.Count - $bodyHeight)
        if ($offset -gt $maxOffset) { $offset = $maxOffset }
        if ($offset -lt 0) { $offset = 0 }

        if ($drawn) { [Console]::SetCursorPosition(0, 0) }
        else { [Console]::Clear(); $drawn = $true }

        $selectedCount = 0
        foreach ($i in $skillRows) { if ($ticked[$rows[$i].Name]) { $selectedCount++ } }

        Write-PickerLine "GG_Skills - $target" $width "Cyan"
        Write-PickerLine "" $width

        $cursorRow = $nav[$cursor]

        $bodyLines = 0
        $last = [Math]::Min($offset + $bodyHeight, $rows.Count)
        for ($r = $offset; $r -lt $last; $r++) {
            $row = $rows[$r]
            $prefix = if ($r -eq $cursorRow) { "> " } else { "  " }
            $color = if ($r -eq $cursorRow) { "Yellow" } else { "" }

            if ($row.Kind -eq "header") {
                Write-PickerLine ("  " + $row.Label) $width "Cyan"
            }
            elseif ($row.Kind -eq "group") {
                $count = @($row.Members).Count
                $on = 0
                foreach ($member in $row.Members) { if ($ticked[$member]) { $on++ } }
                $box = if ($on -eq 0) { "[ ]" } elseif ($on -eq $count) { "[x]" } else { "[-]" }
                Write-PickerLine ("  $prefix$box $($row.Label) ($count)") $width $color
            }
            else {
                $box = if ($ticked[$row.Name]) { "[x]" } else { "[ ]" }
                Write-PickerLine ("    $prefix$box " + $row.Name) $width $color
            }
            $bodyLines++
        }
        while ($bodyLines -lt $bodyHeight) {
            Write-PickerLine "" $width
            $bodyLines++
        }

        Write-PickerLine "" $width
        if ($notice) {
            Write-PickerLine ("  " + $notice) $width "Red"
        }
        else {
            Write-PickerLine ("  $selectedCount/$($skillRows.Count) checked   space toggle | a all | enter apply | q quit") $width "DarkGray"
        }

        $key = [Console]::ReadKey($true)
        $notice = ""

        switch ($key.Key) {
            "UpArrow" {
                if ($cursor -gt 0) { $cursor-- }
            }
            "DownArrow" {
                if ($cursor -lt ($nav.Count - 1)) { $cursor++ }
            }
            "Spacebar" {
                $row = $rows[$nav[$cursor]]
                if ($row.Kind -eq "skill") {
                    $ticked[$row.Name] = -not $ticked[$row.Name]
                }
                else {
                    $allOn = $true
                    foreach ($member in $row.Members) { if (-not $ticked[$member]) { $allOn = $false } }
                    foreach ($member in $row.Members) { $ticked[$member] = -not $allOn }
                }
            }
            "Enter" {
                $chosen = @()
                foreach ($i in $skillRows) {
                    if ($ticked[$rows[$i].Name]) { $chosen += $rows[$i].Name }
                }
                if ($chosen.Count -eq 0) {
                    $notice = "Pick at least one skill."
                }
                else {
                    [Console]::SetCursorPosition(0, 0)
                    [Console]::Clear()
                    return $chosen
                }
            }
            "Escape" {
                [Console]::SetCursorPosition(0, 0)
                [Console]::Clear()
                return @()
            }
            default {
                $char = $key.KeyChar.ToString().ToLower()
                if ($char -eq 'q') {
                    [Console]::SetCursorPosition(0, 0)
                    [Console]::Clear()
                    return @()
                }
                if ($char -eq 'a') {
                    $anyOff = $false
                    foreach ($i in $skillRows) { if (-not $ticked[$rows[$i].Name]) { $anyOff = $true } }
                    foreach ($i in $skillRows) { $ticked[$rows[$i].Name] = $anyOff }
                }
            }
        }
    }
}

function Invoke-PickerApply {
    param($Reg, [string[]]$Chosen, [string]$TargetPath)

    $TargetPath = Resolve-Target $TargetPath
    $lock = Read-Lock $TargetPath
    $skillsDir = Join-Path $TargetPath ".agents\skills"

    $pruned = @()
    foreach ($name in @($lock.skills.Keys)) {
        if ($Chosen -notcontains $name) {
            $dest = Join-Path $skillsDir $name
            if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            $lock.skills.Remove($name)
            $pruned += $name
        }
    }
    foreach ($name in $pruned) { Write-Skip "removed $name" }

    Write-Host "Applying $($Chosen.Count) skills to $TargetPath"
    foreach ($name in $Chosen) {
        Install-One -Reg $Reg -Skill (Resolve-Skill -Reg $Reg -Name $name) -TargetPath $TargetPath -Lock $lock
    }

    Write-Lock -TargetPath $TargetPath -Lock $lock
    Write-Ok "lock: $($lock.skills.Count) skills tracked"
}

# Dot-sourcing (tests) loads the functions without running the command line.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
    $reg = Get-Registry

    if ($Command.ToLower() -ne "doctor") {
        $registryErrors = @(Test-Registry -Reg $reg)
        if ($registryErrors.Count -gt 0) {
            foreach ($errorMessage in $registryErrors) { Write-Err $errorMessage }
            exit 1
        }
    }

    if ($Command -eq "") {
        $chosen = @(Start-Picker -Reg $reg)
        if ($chosen.Count -eq 0) {
            Write-Host "Nothing changed."
        }
        else {
            Invoke-PickerApply -Reg $reg -Chosen $chosen -TargetPath "."
            Write-Host ""
            Write-Host "Run 'gg' again to change your selection."
        }
        exit 0
    }

    switch ($Command.ToLower()) {
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
        "add-source" {
            Invoke-AddSource -Reg $reg -Repo $Repo -Ref $Ref -SourceName $Source -Write:$Write
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
