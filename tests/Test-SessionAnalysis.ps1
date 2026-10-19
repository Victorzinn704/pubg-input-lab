[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-Equal($Actual, $Expected, [string]$Label) {
    if ($Actual -ne $Expected) { throw "$Label : esperado '$Expected', obtido '$Actual'." }
    $script:assertions++
}
function Assert-Near([double]$Actual, [double]$Expected, [string]$Label) {
    if ([math]::Abs($Actual - $Expected) -gt 0.000001) { throw "$Label : esperado $Expected, obtido $Actual." }
    $script:assertions++
}
$fixture = Join-Path $PSScriptRoot ('artifacts\analysis-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$script:fixtureRows = New-Object 'System.Collections.Generic.List[object]'
function Add-Row([string]$Event, [long]$Ticks, [long]$Burst = 0, [string]$Mode = 'real_input', [string]$Profile = 'M416', [long]$Dy = 0, [int]$Attempted = 0, [string]$Accepted = '', [string]$Reason = '') {
    $seq = $script:fixtureRows.Count + 1
    $script:fixtureRows.Add([pscustomobject][ordered]@{
        seq = $seq; utc = ([DateTimeOffset]'2026-10-15T12:00:00Z').AddMilliseconds($Ticks / 1000.0).ToString('o')
        qpc_ticks = $Ticks; session_ms = $Ticks / 1000.0; event = $Event; mode = $Mode; profile = $Profile
        generation = 1; burst = $Burst; elapsed_ms = 0; due_ms = 0; lag_ms = 0
        raw_dx = 0; raw_dy = $Dy; planned_dx = 0; planned_dy = $Dy
        requested_dx = 0; requested_dy = if ($Attempted) { $Dy } else { 0 }
        input_attempted = $Attempted; send_call_qpc_ticks = if ($Attempted) { [string]$Ticks } else { '' }
        send_return_qpc_ticks = if ($Attempted) { [string]($Ticks + 1) } else { '' }
        os_inserted_count = $Accepted; reason = $Reason; target_focused = 1; lmb_physical = 1; rmb_physical = 1
    })
}
Add-Row -Event configuration -Ticks 0
Add-Row -Event burst_start -Ticks 1000000 -Burst 1
Add-Row -Event move -Ticks 1000000 -Burst 1 -Dy 3 -Attempted 1 -Accepted 1
Add-Row -Event move -Ticks 1020000 -Burst 1 -Dy 3 -Attempted 1 -Accepted 1
Add-Row -Event move -Ticks 1050000 -Burst 1 -Dy 3 -Attempted 1 -Accepted 0
Add-Row -Event burst_stop -Ticks 1090000 -Burst 1 -Reason 'button_released'
# Repeated burst/generation counters must not produce an interval across runs.
Add-Row -Event burst_start -Ticks 2000000 -Burst 1
Add-Row -Event move -Ticks 2000000 -Burst 1 -Dy 4 -Attempted 1 -Accepted 1
Add-Row -Event move -Ticks 2020000 -Burst 1 -Dy 4 -Attempted 1 -Accepted 1
Add-Row -Event burst_stop -Ticks 2050000 -Burst 1 -Reason "<img src=x onerror=alert(1)>, `"quoted`"`nsecond line"
Add-Row -Event burst_start -Ticks 3000000 -Burst 2 -Mode dry_run
Add-Row -Event move -Ticks 3000000 -Burst 2 -Mode dry_run -Dy 7
Add-Row -Event burst_stop -Ticks 3020000 -Burst 2 -Mode dry_run -Reason burst_limit
Add-Row -Event probe_start -Ticks 4000000 -Profile InputProbe
Add-Row -Event probe_move -Ticks 4000000 -Profile InputProbe -Dy 10 -Attempted 1 -Accepted 1
Add-Row -Event probe_move -Ticks 4020000 -Profile InputProbe -Dy 10 -Attempted 1 -Accepted 1
Add-Row -Event probe_end -Ticks 4050000 -Profile InputProbe -Reason completed
Add-Row -Event session_expired -Ticks 4500000 -Reason session_limit
Add-Row -Event session_end -Ticks 5000000 -Profile '' -Mode '' -Reason exit
$csv = Join-Path $fixture 'events.csv'
$manifest = Join-Path $fixture 'manifest.txt'
$fixtureRows | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
[IO.File]::AppendAllText($csv, '20,"incomplete', (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($manifest, "session_id=deterministic-fixture`nqpc_frequency_hz=1000000`n", (New-Object Text.UTF8Encoding($false)))
$beforeHash = (Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash
$result = & (Join-Path $PSScriptRoot '..\Analisar-Sessao.ps1') -SessionPath $fixture
$summary = Get-Content -LiteralPath $result.SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$html = Get-Content -LiteralPath $result.ReportPath -Raw -Encoding UTF8
$real = @($summary.profiles | Where-Object { $_.profile -eq 'M416' -and $_.mode -eq 'real_input' })[0]
$dry = @($summary.profiles | Where-Object { $_.mode -eq 'dry_run' })[0]
$probe = @($summary.profiles | Where-Object { $_.kind -eq 'probe' })[0]
Assert-Equal $summary.snapshot.records 19 'Complete rows'
Assert-Equal $summary.snapshot.cutoff_seq 19 'Cutoff sequence'
Assert-Equal $summary.snapshot.incomplete_tail_bytes 14 'Incomplete tail bytes'
Assert-Equal $summary.snapshot.sequence_gaps 0 'Sequence gaps'
Assert-Equal $summary.snapshot.duplicate_sequences.Count 0 'Duplicate sequences'
Assert-Equal $summary.bursts.Count 3 'Real plus dry runs'
Assert-Equal $summary.probes.Count 1 'Separated probes'
Assert-Near $summary.bursts[0].observed_duration_ms 90 'Burst duration from QPC'
Assert-Near $summary.probes[0].observed_duration_ms 50 'Probe duration from QPC'
Assert-Equal $real.runs 2 'Repeated counters remain separate'
Assert-Equal $real.metrics.calls 5 'Real calls'
Assert-Equal $real.metrics.accepted_windows 4 'Accepted calls'
Assert-Equal $real.metrics.rejected_windows 1 'Rejected calls'
Assert-Equal $real.metrics.unknown_call_results 0 'Unknown calls'
Assert-Equal $real.metrics.requested_dy_sum 17 'Requested Y'
Assert-Equal $real.metrics.accepted_argument_dy_sum 14 'Accepted argument Y'
Assert-Equal $real.call_intervals.count 3 'Only intraburst intervals'
Assert-Near $real.call_intervals.mean_ms 23.333333 'Mean interval'
Assert-Near $real.call_intervals.p95_ms 30 'Nearest-rank P95'
Assert-Near $real.call_intervals.max_ms 30 'Maximum interval'
Assert-Equal $dry.metrics.calls 0 'Dry run never becomes a call'
Assert-Equal $dry.metrics.planned_dy_sum 7 'Dry planned Y'
Assert-Equal $dry.metrics.requested_dy_sum 0 'Dry requested Y'
Assert-Equal $probe.metrics.calls 2 'Probe calls'
Assert-Equal $probe.metrics.requested_dy_sum 20 'Probe requested Y'
Assert-Equal ($html.Contains('<img src=x')) $false 'HTML injection escaped'
Assert-Equal ($html.Contains('&lt;img src=x')) $true 'Escaped evidence retained'
Assert-Equal $summary.bursts[1].stop_reason "<img src=x onerror=alert(1)>, `"quoted`"`nsecond line" 'Multiline CSV reason'
Assert-Equal (Get-FileHash -LiteralPath $csv -Algorithm SHA256).Hash $beforeHash 'Raw log unchanged'
Assert-Equal $summary.snapshot.csv_sha256 $beforeHash.ToLowerInvariant() 'Snapshot SHA256'
Assert-Equal $summary.last_control_event.event 'session_end' 'Last control event'
Assert-Equal @($summary.stops | Where-Object { $_.value -eq 'session_limit' })[0].count 1 'Session expiration included in stops'
$columns = @($fixtureRows[0].PSObject.Properties.Name)
$quotedHeader = ($columns | ForEach-Object { '"' + $_.Replace('"', '""') + '"' }) -join ','
$emptyCases = @(
    @{ Name = 'empty-plain'; Header = $columns -join ','; Bom = $false },
    @{ Name = 'empty-quoted-bom'; Header = $quotedHeader + ',"extra,column"'; Bom = $true }
)
foreach ($case in $emptyCases) {
    $emptyFixture = Join-Path $fixture $case.Name
    [void][IO.Directory]::CreateDirectory($emptyFixture)
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $emptyFixture 'manifest.txt')
    $emptyCsv = Join-Path $emptyFixture 'events.csv'
    [IO.File]::WriteAllText($emptyCsv, ($case.Header + "`r`n"), (New-Object Text.UTF8Encoding($case.Bom)))
    $emptyHash = (Get-FileHash -LiteralPath $emptyCsv -Algorithm SHA256).Hash
    $emptyResult = & (Join-Path $PSScriptRoot '..\Analisar-Sessao.ps1') -SessionPath $emptyFixture
    $emptySummary = Get-Content -LiteralPath $emptyResult.SummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal $emptySummary.snapshot.records 0 ($case.Name + ': no synthetic event')
    Assert-Equal $emptySummary.snapshot.cutoff_seq $null ($case.Name + ': no cutoff sequence')
    Assert-Equal (Get-FileHash -LiteralPath $emptyCsv -Algorithm SHA256).Hash $emptyHash ($case.Name + ': raw log unchanged')
}
$invalidCases = @(
    @{ Name = 'invalid-header'; Header = 'wrong,header'; Bom = $false },
    @{ Name = 'invalid-header-quoted-bom'; Header = '"wrong","header"'; Bom = $true }
)
foreach ($case in $invalidCases) {
    $invalidFixture = Join-Path $fixture $case.Name
    [void][IO.Directory]::CreateDirectory($invalidFixture)
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $invalidFixture 'manifest.txt')
    [IO.File]::WriteAllText((Join-Path $invalidFixture 'events.csv'), ($case.Header + "`r`n"), (New-Object Text.UTF8Encoding($case.Bom)))
    $failure = ''
    try { & (Join-Path $PSScriptRoot '..\Analisar-Sessao.ps1') -SessionPath $invalidFixture | Out-Null }
    catch { $failure = $_.Exception.Message }
    Assert-Equal $failure 'Coluna ausente no CSV: seq.' ($case.Name + ': schema rejected without rows')
    Assert-Equal (Test-Path -LiteralPath (Join-Path $invalidFixture 'analysis')) $false ($case.Name + ': no report generated')
}
Write-Output "PASS: $script:assertions assertions. Fixture: $fixture"
