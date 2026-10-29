#Requires -Version 5.1
[CmdletBinding()]
param([string]$Version = '1.4.1')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid version.' }
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$worktreeState = git -C $projectRoot status --porcelain
if ($LASTEXITCODE -ne 0 -or $worktreeState) { throw 'Commit changes before packaging; the source tree must be clean.' }
$revision = git -C $projectRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve release commit.' }
$buildRoot = Join-Path $projectRoot ('.artifacts\release-' + [Guid]::NewGuid().ToString('N'))
$packageName = 'PUBG-Input-Lab-' + $Version
$staging = Join-Path $buildRoot $packageName
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$sourceArchive = Join-Path $buildRoot 'source.zip'
git -C $projectRoot archive --format=zip --output=$sourceArchive HEAD
if ($LASTEXITCODE -ne 0) { throw 'Source archive failed.' }
Expand-Archive -LiteralPath $sourceArchive -DestinationPath $staging
$entrypoint = Get-Content -LiteralPath (Join-Path $staging 'RecoilLab.ahk') -Raw
if (-not $entrypoint.Contains('versao ' + $Version)) { throw 'Version differs from the committed application.' }
& (Join-Path $staging 'scripts\Setup-Runtime.ps1')
foreach ($privateFile in @('profiles.ini', 'calibrations.ini', 'hotkeys.ini', 'presets.local.ini', 'display.local.ini', 'logs')) {
    if (Test-Path -LiteralPath (Join-Path $staging $privateFile)) { throw "Private data found in package: $privateFile" }
}
if (-not (Test-Path -LiteralPath (Join-Path $staging 'runtime\LICENSE.txt'))) { throw 'Runtime license missing.' }
$revision | Set-Content -LiteralPath (Join-Path $staging 'SOURCE_COMMIT.txt') -Encoding ascii
$archive = Join-Path $buildRoot ($packageName + '-windows-x64.zip')
Compress-Archive -LiteralPath $staging -DestinationPath $archive -CompressionLevel Optimal
$digest = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumFile = Join-Path $buildRoot 'SHA256SUMS.txt'
($digest + '  ' + [IO.Path]::GetFileName($archive)) | Set-Content -LiteralPath $checksumFile -Encoding ascii
[pscustomobject]@{ Version = $Version; Commit = $revision; Archive = $archive; Sha256 = $digest; Checksums = $checksumFile }
