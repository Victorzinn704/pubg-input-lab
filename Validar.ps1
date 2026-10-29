$ErrorActionPreference = 'Stop'
$labExe = Join-Path $PSScriptRoot 'runtime\AutoHotkey64.exe'
$labScript = Join-Path $PSScriptRoot 'RecoilLab.ahk'
$reportRoot = Join-Path $PSScriptRoot 'tests\artifacts'
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
foreach ($testMode in @('self-test', 'smoke-test', 'config-dependency', 'instance', 'overlay', 'hotkeys', 'presets', 'workflow')) {
    $outputPath = Join-Path $reportRoot ($testMode + '.stdout.txt')
    $errorPath = Join-Path $reportRoot ($testMode + '.stderr.txt')
    $testArguments = if ($testMode -eq 'config-dependency') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\ConfigDependencyTest.ahk') + '"'))
    } elseif ($testMode -eq 'instance') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\InstanceTests.ahk') + '"'))
    } elseif ($testMode -eq 'overlay') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\OverlayTests.ahk') + '"'))
    } elseif ($testMode -eq 'hotkeys') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\HotkeyTests.ahk') + '"'))
    } elseif ($testMode -eq 'presets') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\PresetTests.ahk') + '"'))
    } elseif ($testMode -eq 'workflow') {
        @('/ErrorStdOut=utf-8', ('"' + (Join-Path $PSScriptRoot 'tests\WorkflowTests.ahk') + '"'))
    } else {
        @('/ErrorStdOut=utf-8', ('"' + $labScript + '"'), ('--' + $testMode))
    }
    $process = Start-Process -FilePath $labExe -ArgumentList $testArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
    if (-not $process.WaitForExit(15000)) {
        Stop-Process -Id $process.Id
        throw "Teste $testMode excedeu 15 segundos."
    }
    $testOutput = Get-Content -LiteralPath $outputPath -Raw
    $testError = Get-Content -LiteralPath $errorPath -Raw
    Write-Output $testOutput
    if ($process.ExitCode -ne 0 -or $testError -or $testOutput -notmatch '^PASS:') {
        throw "Teste $testMode falhou (exit=$($process.ExitCode)). $testError"
    }
}
& (Join-Path $PSScriptRoot 'tests\Test-SessionAnalysis.ps1')
Write-Output 'Validacao concluida sem instalar hooks nem enviar entradas ao jogo.'
