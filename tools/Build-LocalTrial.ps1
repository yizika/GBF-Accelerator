[CmdletBinding()]
param([string]$GoExecutable = 'go')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $root 'engine'
$versionMatch = [regex]::Match([IO.File]::ReadAllText((Join-Path $engine 'config/config.go')), 'const AppVersion\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) { throw 'AppVersion not found' }
$version = $versionMatch.Groups[1].Value
$go = (Get-Command $GoExecutable -ErrorAction Stop).Source
$utf8 = New-Object Text.UTF8Encoding($false)
$buildId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$output = Join-Path $root ('release/local-safety-' + $version + '-' + $buildId)
$package = Join-Path $output 'package'
New-Item -ItemType Directory -Path $package -Force | Out-Null

Push-Location (Join-Path $root 'web')
try {
    & npm.cmd test
    if ($LASTEXITCODE -ne 0) { throw 'Frontend tests failed' }
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed' }
} finally { Pop-Location }

# Mirror only generated assets, after confirming the destination stays in this repo.
$assets = [IO.Path]::GetFullPath((Join-Path $engine 'ui/dist/assets'))
$expected = [IO.Path]::GetFullPath((Join-Path $root 'engine/ui/dist/assets'))
if ($assets -ne $expected -or -not $assets.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unexpected asset directory' }
if (Test-Path -LiteralPath $assets) { Remove-Item -LiteralPath $assets -Recurse -Force }
Copy-Item -Path (Join-Path $root 'web/dist/*') -Destination (Join-Path $engine 'ui/dist') -Recurse -Force

$previousCGO = $env:CGO_ENABLED
$previousOS = $env:GOOS
$previousArch = $env:GOARCH
Push-Location $engine
try {
    $env:CGO_ENABLED = '0'
    $env:GOOS = 'windows'
    $env:GOARCH = 'amd64'
    & $go build -trimpath -ldflags '-s -w -H=windowsgui' -o (Join-Path $package 'GBF_Accelerator.exe') .
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
} finally {
    Pop-Location
    $env:CGO_ENABLED = $previousCGO
    $env:GOOS = $previousOS
    $env:GOARCH = $previousArch
}

Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $package
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Import-ACGPCache.ps1') -Destination $package
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'local-trial-guide.txt') -Destination (Join-Path $package 'Trial-Guide.txt')
$config = @{
    listen_host='127.0.0.1'; listen_port=8124; control_port=8125; allow_lan=$false
    upstream_proxy='http://127.0.0.1:7897'; direct_mode=$false; verify_upstream_tls=$true
    shimakaze_mode=$false; auto_system_proxy=$false; auto_start=$false
    auto_check_update=$false; clean_zombies=$false; cache_dir='cache/gbf/https'; enable_prefetch=$true
}
[IO.File]::WriteAllText((Join-Path $package 'config.json'), ($config | ConvertTo-Json), $utf8)
[IO.File]::WriteAllLines((Join-Path $package 'Start-Trial.cmd'), @('@echo off','cd /d "%~dp0"','start "" "%~dp0GBF_Accelerator.exe" -base-dir "%~dp0."'), [Text.Encoding]::ASCII)
Push-Location $root
try {
    $revision = & git rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source revision' }
    $branch = & git branch --show-current
    & git diff --quiet HEAD --
    if ($LASTEXITCODE -gt 1) { throw 'Cannot inspect source changes' }
    $dirty = $LASTEXITCODE -eq 1
    $untracked = & git ls-files --others --exclude-standard
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect untracked sources' }
    $dirty = $dirty -or [bool]$untracked
    $compiler = & $go version
} finally { Pop-Location }
$metadata = "Custom build based on upstream $version`nBranch: $branch`nCommit: $revision`nWorktree changes: $([bool]$dirty)`nCompiler: $compiler`nThis package retains local safety patches. Official auto-update replaces these patches.`n"
[IO.File]::WriteAllText((Join-Path $package 'BUILD-INFO.txt'), $metadata, $utf8)
$zip = Join-Path $output ('GBF_Accelerator_v' + $version + '_GUI.zip')
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip
$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
[IO.File]::WriteAllText(($zip + '.sha256'), "$hash  $([IO.Path]::GetFileName($zip))`n", $utf8)
Write-Output "PACKAGE=$zip"
