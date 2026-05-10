# c1-vega-plen install script for Windows.
# Usage:
#   $env:C1_VEGA_LICENSE_KEY="C1V-..."; irm https://raw.githubusercontent.com/copernicusone/homebrew-vega/main/install.ps1 | iex
# Modes (mutually exclusive): default install, -Upgrade, -Uninstall.
# Composable: -Version <tag>, -DryRun.

[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Upgrade')]
    [switch]$Upgrade,

    [Parameter(ParameterSetName = 'Uninstall')]
    [switch]$Uninstall,

    [string]$Version,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- constants ----------------------------------------------------------------

$Repo        = "copernicusone/homebrew-vega"
$InstallDir  = Join-Path $env:USERPROFILE ".c1-vega"
$BinDir      = Join-Path $InstallDir "bin"
$BinPath     = Join-Path $BinDir "c1-vega-plen.exe"
$InstallJson = Join-Path $InstallDir "var\install.json"
$LicenseKeyPepper = "c1-vega-install-v1"

# --- helpers ------------------------------------------------------------------

function Write-Step  { param([string]$Msg) Write-Host "  $Msg" }
function Write-Ok    { param([string]$Msg) Write-Host "`n$([char]0x2713) $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "error: $Msg" -ForegroundColor Red }

function Get-LicenseKeyHash {
    param([string]$Key)
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [Text.Encoding]::UTF8.GetBytes($LicenseKeyPepper)
    $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($Key))
    "sha256:$(-join ($hash | ForEach-Object { '{0:x2}' -f $_ }))"
}

function Read-InstallJson {
    if (-not (Test-Path $InstallJson)) { return $null }
    Get-Content $InstallJson -Raw | ConvertFrom-Json
}

function Write-InstallJson {
    param(
        [string]$Ver,
        [string]$Tag,
        [string]$Arch,
        [string]$KeyHash,
        [string]$BinarySha256
    )
    $dir = Split-Path $InstallJson -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{
        version          = $Ver
        tag              = $Tag
        arch             = $Arch
        installed_at     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        license_key_hash = $KeyHash
        binary_sha256    = $BinarySha256
    }
    $obj | ConvertTo-Json -Depth 4 | Set-Content $InstallJson -Encoding UTF8
}

# --- preflight ----------------------------------------------------------------

function Assert-Preflight {
    # PowerShell 5.1+
    if ($PSVersionTable.PSVersion.Major -lt 5 -or
       ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
        throw "PowerShell 5.1 or later required (have $($PSVersionTable.PSVersion))."
    }

    # Windows 10 1803+ (build 17134)
    $build = [Environment]::OSVersion.Version.Build
    if ($build -lt 17134) {
        throw "Windows 10 version 1803 (build 17134) or later required (have build $build)."
    }

    if ($Upgrade) {
        if (-not (Test-Path $InstallJson)) {
            throw "Not installed (no $InstallJson). Run without -Upgrade to install."
        }
    }
    elseif ($Uninstall) {
        if (-not (Test-Path $InstallJson)) {
            Write-Host "Nothing to uninstall (no $InstallJson)."
            return $false
        }
    }
    else {
        # Install mode
        if ([string]::IsNullOrWhiteSpace($env:C1_VEGA_LICENSE_KEY)) {
            throw "C1_VEGA_LICENSE_KEY env var required.`nRun: `$env:C1_VEGA_LICENSE_KEY=`"C1V-...`"; irm <url> | iex"
        }
        if (Test-Path $InstallJson) {
            throw "c1-vega-plen already installed at $InstallDir. Use -Upgrade or -Uninstall."
        }
    }
    return $true
}

# --- arch detection -----------------------------------------------------------

function Get-TargetTriple {
    $arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch) {
        'X64' { return "x86_64-pc-windows-msvc" }
        default { throw "Unsupported architecture: $arch. Only x86_64 is supported." }
    }
}

# --- release resolution -------------------------------------------------------

function Resolve-ReleaseTag {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version
    }
    $uri = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{ 'User-Agent' = 'c1-vega-installer/1.0' }
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 30
    }
    catch {
        throw "Failed to query latest release from GitHub: $_"
    }
    if ([string]::IsNullOrWhiteSpace($resp.tag_name)) {
        throw "Could not determine latest release tag."
    }
    return $resp.tag_name
}

# --- download + verify --------------------------------------------------------

function Get-ReleaseArtifacts {
    param([string]$Tag, [string]$Triple, [string]$WorkDir)
    $ver = $Tag.TrimStart('v')
    $archive = "c1-vega-plen-${ver}-${Triple}.tar.gz"
    $base = "https://github.com/$Repo/releases/download/$Tag"

    Write-Step "Downloading $archive ..."
    Invoke-WebRequest -Uri "$base/$archive" -OutFile (Join-Path $WorkDir $archive) -UseBasicParsing
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile (Join-Path $WorkDir "SHA256SUMS") -UseBasicParsing
    return $archive
}

function Assert-Checksum {
    param([string]$WorkDir, [string]$Archive)
    $expected = Get-Content (Join-Path $WorkDir "SHA256SUMS") |
        Where-Object { $_ -match $Archive } |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($expected)) {
        throw "Archive $Archive not found in SHA256SUMS."
    }

    $actual = (Get-FileHash -Algorithm SHA256 -Path (Join-Path $WorkDir $Archive)).Hash.ToLower()
    if ($actual -ne $expected.ToLower()) {
        throw "Checksum mismatch for $Archive.`nExpected: $expected`nActual:   $actual"
    }
    Write-Step "Checksum verified."
}

# --- extract ------------------------------------------------------------------

function Expand-Binary {
    param([string]$ArchivePath)
    $extractDir = Join-Path $env:TEMP "c1vega-extract-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    # tar is built-in on Windows 10 1803+
    tar -xzf $ArchivePath -C $extractDir 2>$null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        throw "Failed to extract archive."
    }

    $found = Get-ChildItem -Path $extractDir -Recurse -Filter "c1-vega-plen*" -File |
        Where-Object { $_.Name -match '^c1-vega-plen(\.exe)?$' } |
        Select-Object -First 1

    if (-not $found) {
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        throw "c1-vega-plen binary not found in archive."
    }

    # Ensure install directories exist
    foreach ($d in @($BinDir, (Join-Path $InstallDir "var\logs"), (Join-Path $InstallDir "etc"))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }

    $dest = $BinPath
    Copy-Item $found.FullName -Destination $dest -Force

    # Rename if extracted without .exe extension
    if ($found.Name -eq "c1-vega-plen" -and -not $dest.EndsWith(".exe")) {
        Rename-Item $dest "$dest.exe"
    }

    Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "Binary installed to $BinPath"
}

# --- license activation -------------------------------------------------------

function Invoke-Activate {
    param([string]$Key)
    Write-Step "Activating license ..."
    & $BinPath activate $Key
    if ($LASTEXITCODE -ne 0) {
        throw "License activation failed."
    }
}

# --- PATH modification --------------------------------------------------------

function Add-BinToPath {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -split ';' -contains $BinDir) {
        Write-Step "PATH already contains $BinDir"
        return
    }
    $newPath = "$BinDir;$currentPath"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    # Also update current session
    $env:PATH = "$BinDir;$env:PATH"
    Write-Step "Added $BinDir to user PATH."
}

function Remove-BinFromPath {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $parts = ($currentPath -split ';') | Where-Object { $_ -ne $BinDir -and $_ -ne "" }
    $newPath = $parts -join ';'
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    Write-Step "Removed $BinDir from user PATH."
}

# --- claude/codex wrappers ----------------------------------------------------

function Install-ClaudeWrapper {
    $cmd = Join-Path $BinDir "claude.cmd"
    Set-Content -Path $cmd -Value '@c1-vega-plen.exe run --client anthropic -- claude %*' -Encoding ASCII
    Write-Step "Created claude.cmd wrapper."
}

function Install-CodexWrapper {
    $cmd = Join-Path $BinDir "codex.cmd"
    Set-Content -Path $cmd -Value '@c1-vega-plen.exe run --client codex --codex-auth chatgpt -- codex %*' -Encoding ASCII
    Write-Step "Created codex.cmd wrapper."
}

# --- claude code slash commands -----------------------------------------------

function Install-ClaudeCommands {
    $target = Join-Path $env:USERPROFILE ".claude\commands"
    # Try the local repo source first (for dev installs), then the install subdir
    # next to this script.
    $source = $null
    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    foreach ($candidate in @(
        (Join-Path $scriptDir "install\claude-commands"),
        (Join-Path $scriptDir "..\install\claude-commands")
    )) {
        if (Test-Path $candidate) { $source = $candidate; break }
    }
    if (-not $source) { return }
    if (-not (Test-Path (Join-Path $env:USERPROFILE ".claude"))) { return }
    if (-not (Test-Path $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }
    Get-ChildItem -Path $source -Filter "c1-vega-*.md" | ForEach-Object {
        Copy-Item $_.FullName -Destination (Join-Path $target $_.Name) -Force
    }
    Write-Step "Installed Claude Code slash commands."
}

function Remove-ClaudeCommands {
    $target = Join-Path $env:USERPROFILE ".claude\commands"
    if (-not (Test-Path $target)) { return }
    Get-ChildItem -Path $target -Filter "c1-vega-*.md" -ErrorAction SilentlyContinue |
        Remove-Item -Force
    Write-Step "Removed Claude Code slash commands."
}

# --- main flows ---------------------------------------------------------------

function Invoke-Install {
    Write-Host "`nInstalling c1-vega-plen ...`n"

    $triple  = Get-TargetTriple
    $tag     = Resolve-ReleaseTag
    $ver     = $tag.TrimStart('v')
    $workDir = Join-Path $env:TEMP "c1vega-install-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        $archive = Get-ReleaseArtifacts -Tag $tag -Triple $triple -WorkDir $workDir
        Assert-Checksum -WorkDir $workDir -Archive $archive
        Expand-Binary -ArchivePath (Join-Path $workDir $archive)

        $binSha = (Get-FileHash -Algorithm SHA256 -Path $BinPath).Hash.ToLower()

        try {
            Invoke-Activate -Key $env:C1_VEGA_LICENSE_KEY
        }
        catch {
            # Clean up on activation failure
            Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
            throw
        }

        $keyHash = Get-LicenseKeyHash -Key $env:C1_VEGA_LICENSE_KEY
        Write-InstallJson -Ver $ver -Tag $tag -Arch $triple -KeyHash $keyHash -BinarySha256 $binSha

        Add-BinToPath
        Install-ClaudeWrapper
        Install-CodexWrapper
        Install-ClaudeCommands

        Write-Ok "c1-vega-plen v$ver installed."
        Write-Host @"
Open a new terminal and run ``claude`` or ``codex`` -- the c1-vega proxy starts
on demand and routes AI client traffic through it.

The ``codex`` wrapper uses ChatGPT auth by default. API-key mode remains
available via ``c1-vega-plen.exe run --client codex --codex-auth api -- codex``.

Inside [PERSON_3] Code, /c1-vega-help lists the in-chat directives.
"@
    }
    finally {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Upgrade {
    Write-Host "`nUpgrading c1-vega-plen ...`n"

    $existing = Read-InstallJson
    $triple   = Get-TargetTriple
    $tag      = Resolve-ReleaseTag
    $ver      = $tag.TrimStart('v')
    $workDir  = Join-Path $env:TEMP "c1vega-upgrade-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    try {
        $archive = Get-ReleaseArtifacts -Tag $tag -Triple $triple -WorkDir $workDir
        Assert-Checksum -WorkDir $workDir -Archive $archive
        Expand-Binary -ArchivePath (Join-Path $workDir $archive)

        $binSha = (Get-FileHash -Algorithm SHA256 -Path $BinPath).Hash.ToLower()

        # Re-activate only if a new license key is provided and differs
        $keyHash = $existing.license_key_hash
        if (-not [string]::IsNullOrWhiteSpace($env:C1_VEGA_LICENSE_KEY)) {
            $newHash = Get-LicenseKeyHash -Key $env:C1_VEGA_LICENSE_KEY
            if ($newHash -ne $keyHash) {
                Invoke-Activate -Key $env:C1_VEGA_LICENSE_KEY
                $keyHash = $newHash
            }
        }

        Write-InstallJson -Ver $ver -Tag $tag -Arch $triple -KeyHash $keyHash -BinarySha256 $binSha

        Install-ClaudeWrapper
        Install-CodexWrapper
        Install-ClaudeCommands

        Write-Ok "Upgraded c1-vega-plen to v$ver."
    }
    finally {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Uninstall {
    Write-Host "`nUninstalling c1-vega-plen ...`n"

    Remove-ClaudeCommands
    Remove-BinFromPath

    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Step "Removed $InstallDir"

    Write-Ok "Removed binary, PATH entry, claude/codex wrappers, Claude Code slash commands, and config."
    Write-Host @"

Note: If c1-vega stored any data in %LOCALAPPDATA%\c1-vega, it was left
intact. Delete it manually for a clean slate.
"@
}

# --- entry point --------------------------------------------------------------

$canContinue = Assert-Preflight
if ($canContinue -eq $false) { return }

if ($DryRun) {
    if ($Uninstall) {
        Write-Host "[DRY-RUN] would: remove Claude Code slash commands, remove $BinDir from PATH, rm -rf $InstallDir including claude/codex wrappers"
    }
    elseif ($Upgrade) {
        Write-Host "[DRY-RUN] would: download new release, replace $BinPath, refresh claude/codex wrappers and slash commands"
    }
    else {
        Write-Host "[DRY-RUN] would: detect arch, resolve latest release, download tarball + SHA256SUMS, verify checksum, extract to $BinDir, run activate, write $InstallJson, add $BinDir to PATH, create claude.cmd and codex.cmd wrappers, install Claude Code slash commands"
    }
    return
}

if ($Uninstall) {
    Invoke-Uninstall
}
elseif ($Upgrade) {
    Invoke-Upgrade
}
else {
    Invoke-Install
}
