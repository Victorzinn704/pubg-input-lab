#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitOperatingSystem) {
    throw 'This runtime requires 64-bit Windows.'
}

$runtimeVersion = '2.0.30'
$archiveUrl = 'https://github.com/AutoHotkey/AutoHotkey/releases/download/v2.0.30/AutoHotkey_2.0.30.zip'
# Published in the official release body and the GitHub release asset digest.
$archiveSha256 = '1E0ECE7ECB2D5646E55758150472677996A57F9DB5C83D2996D8B47B9E2F31A4'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtimeRoot = Join-Path $projectRoot 'runtime'
$stagingPath = Join-Path $runtimeRoot ('.setup-' + [Guid]::NewGuid().ToString('N'))

function Assert-WorkspacePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath($Path)
    $rootPrefix = $projectRoot.TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the project: $fullPath"
    }
    $currentPath = $fullPath
    while ($currentPath -ne $projectRoot) {
        if (Test-Path -LiteralPath $currentPath) {
            $item = Get-Item -LiteralPath $currentPath -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing a symbolic link or junction: $currentPath"
            }
        }
        $currentPath = [IO.Path]::GetDirectoryName($currentPath)
    }
}

Assert-WorkspacePath -Path $runtimeRoot
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
Assert-WorkspacePath -Path $stagingPath
New-Item -ItemType Directory -Path $stagingPath | Out-Null
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $archivePath = Join-Path $stagingPath 'AutoHotkey.zip'
    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 60
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne $archiveSha256) {
        throw "AutoHotkey archive checksum mismatch. Expected $archiveSha256; received $actualHash. Runtime unchanged."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    $runtimeFiles = @('AutoHotkey64.exe', 'license.txt')
    try {
        foreach ($fileName in $runtimeFiles) {
            $entry = $archive.GetEntry($fileName)
            if ($null -eq $entry -or $entry.Length -eq 0) {
                throw "The verified archive does not contain $fileName."
            }
            # Extract only these fixed names; archive paths are never destinations.
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $stagingPath $fileName))
        }
    } finally {
        $archive.Dispose()
    }

    $extractedExe = Join-Path $stagingPath 'AutoHotkey64.exe'
    $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($extractedExe).FileVersion
    if ($fileVersion -ne $runtimeVersion) {
        throw "Unexpected runtime version: $fileVersion. Runtime unchanged."
    }

    # Check both destinations before changing either one.
    foreach ($fileName in $runtimeFiles) {
        Assert-WorkspacePath -Path (Join-Path $runtimeRoot $fileName)
    }
    foreach ($fileName in $runtimeFiles) {
        $sourcePath = Join-Path $stagingPath $fileName
        $destinationPath = Join-Path $runtimeRoot $fileName
        $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
        if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and
            (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash -eq $sourceHash) {
            Write-Output "Already verified: runtime/$fileName"
            continue
        }
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        if ((Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash -ne $sourceHash) {
            throw "Runtime copy verification failed: $destinationPath"
        }
        Write-Output "Installed: runtime/$fileName"
    }
    Write-Output "AutoHotkey $runtimeVersion x64 is ready. No executable was launched."
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
    if (Test-Path -LiteralPath $stagingPath -PathType Container) {
        Assert-WorkspacePath -Path $stagingPath
        $resolvedStagingPath = (Resolve-Path -LiteralPath $stagingPath).ProviderPath
        if ($resolvedStagingPath -ne [IO.Path]::GetFullPath($stagingPath)) {
            throw 'Refusing cleanup: the staging directory resolved to an unexpected path.'
        }
        Remove-Item -LiteralPath $resolvedStagingPath -Recurse -Force
    }
}
