<# Copies only passive media into a NEW cache directory; never modifies the source.
   Scripts, styles, WASM, SVG, HTML and unknown formats are deliberately not imported.
   Run with -Source pointing to the old gbf/https directory. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path -LiteralPath $Source).Path.TrimEnd('\', '/')
$destinationRoot = [IO.Path]::GetFullPath($Destination).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw 'Source must be a directory' }
if (Test-Path -LiteralPath $destinationRoot) { throw 'Destination must be a new directory' }
if ($destinationRoot.StartsWith($sourceRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Destination must be outside the source' }
if ((Get-Item -LiteralPath $sourceRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source cannot be a link' }
$allowed = @('.png','.jpg','.jpeg','.webp','.gif','.mp3','.wav','.ogg','.m4a','.mp4','.webm','.woff','.woff2','.ttf','.otf','.ico')
New-Item -ItemType Directory -Path $destinationRoot | Out-Null
$copied = 0
$pending = New-Object 'System.Collections.Generic.Stack[string]'
$pending.Push($sourceRoot)
while ($pending.Count -gt 0) {
    foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($item.PSIsContainer) { $pending.Push($item.FullName); continue }
        if ($allowed -notcontains $item.Extension.ToLowerInvariant() -or $item.Length -eq 0) { continue }
        $relative = $item.FullName.Substring($sourceRoot.Length + 1)
        $target = [IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
        if (-not $target.StartsWith($destinationRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped destination' }
        New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($target)) | Out-Null
        Copy-Item -LiteralPath $item.FullName -Destination $target
        $metadata = $item.FullName + '.ext'
        if (Test-Path -LiteralPath $metadata -PathType Leaf) {
            $metaItem = Get-Item -LiteralPath $metadata -Force
            if (-not ($metaItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                # Keep encoding metadata; clear prior validation claims when JSON is used.
                $raw = [IO.File]::ReadAllText($metadata)
                try {
                    $meta = $raw | ConvertFrom-Json
                    if ($meta -is [pscustomobject]) {
                        foreach ($key in @('verified','size','mtime')) { $meta.PSObject.Properties.Remove($key) }
                        $raw = $meta | ConvertTo-Json -Depth 20 -Compress
                    }
                } catch { }
                [IO.File]::WriteAllText($target + '.ext', $raw, (New-Object Text.UTF8Encoding($false)))
            }
        }
        $copied++
    }
}
Write-Output "Imported $copied media files into $destinationRoot. Source unchanged. Code resources will download on demand. Run the application's cache audit before use; imported media is not authenticated against CDN originals."
