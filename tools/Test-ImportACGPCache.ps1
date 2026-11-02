$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('gbf-import-test-'+[guid]::NewGuid())
$source=Join-Path $root 'source'
$dest=Join-Path $root 'destination'
New-Item -ItemType Directory -Path (Join-Path $source 'assets') -Force | Out-Null
foreach ($name in @('image.png','sound.mp3','code.js','module.wasm','style.css','image.svg')) {
    [IO.File]::WriteAllText((Join-Path $source ('assets/'+$name)), 'fixture')
}
[IO.File]::WriteAllText((Join-Path $source 'assets/image.png.ext'), '{"ct":"image/png","verified":true,"mtime":123,"size":7}')
& (Join-Path $PSScriptRoot 'Import-ACGPCache.ps1') -Source $source -Destination $dest
foreach($name in @('image.png','sound.mp3')) { if (-not (Test-Path -LiteralPath (Join-Path $dest ('assets/'+$name)))) { throw "Missing $name" } }
foreach($name in @('code.js','module.wasm','style.css','image.svg')) { if (Test-Path -LiteralPath (Join-Path $dest ('assets/'+$name))) { throw "Imported code $name" } }
if ((Get-Content -LiteralPath (Join-Path $dest 'assets/image.png.ext') -Raw) -match 'verified|mtime|size') { throw 'Stale validation copied' }
if ((Get-Content -LiteralPath (Join-Path $source 'assets/code.js') -Raw) -ne 'fixture') { throw 'Source changed' }
$rejected=$false
try { & (Join-Path $PSScriptRoot 'Import-ACGPCache.ps1') -Source $source -Destination $dest } catch { $rejected=$true }
if (-not $rejected) { throw 'Existing destination accepted' }
Write-Output "PASS: media import, code exclusion, metadata reset, source preservation, destination protection. Fixtures: $root"
