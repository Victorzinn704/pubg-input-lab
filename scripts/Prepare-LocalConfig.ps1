[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($config in @(
    @{Name='profiles.ini'; Example='profiles.example.ini'},
    @{Name='hotkeys.ini'; Example='hotkeys.example.ini'},
    @{Name='presets.local.ini'; Example='presets.example.ini'}
)) {
    $destination = Join-Path $projectRoot $config.Name
    $example = Join-Path $projectRoot $config.Example
    if (-not (Test-Path -LiteralPath $destination)) {
        if (-not (Test-Path -LiteralPath $example)) { throw "Exemplo ausente: $example" }
        [IO.File]::Copy($example, $destination, $false)
        Write-Output "Criado: $($config.Name)"
    } else {
        Write-Output "Preservado: $($config.Name)"
    }
}
