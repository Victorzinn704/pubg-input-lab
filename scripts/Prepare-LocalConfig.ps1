[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
foreach ($name in @('profiles', 'hotkeys')) {
    $destination = Join-Path $projectRoot ($name + '.ini')
    $example = Join-Path $projectRoot ($name + '.example.ini')
    if (-not (Test-Path -LiteralPath $destination)) {
        if (-not (Test-Path -LiteralPath $example)) { throw "Exemplo ausente: $example" }
        [IO.File]::Copy($example, $destination, $false)
        Write-Output "Criado: $name.ini"
    } else {
        Write-Output "Preservado: $name.ini"
    }
}
