[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SessionPath,
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$warnings = New-Object 'System.Collections.Generic.List[string]'

function Read-Snapshot([string]$Path) {
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        if ($stream.Length -gt [int]::MaxValue) { throw 'Arquivo maior que o limite de leitura desta ferramenta (2 GB).' }
        $buffer = New-Object byte[] ([int]$stream.Length)
        $read = 0
        while ($read -lt $buffer.Length) {
            $count = $stream.Read($buffer, $read, $buffer.Length - $read)
            if ($count -eq 0) { throw 'O arquivo diminuiu durante a leitura; tente novamente.' }
            $read += $count
        }
        return ,$buffer
    } finally { $stream.Dispose() }
}

function Get-Hash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-Number([string]$Value, [string]$Field, [bool]$Optional = $false) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($Optional) { return $null }
        throw "Campo numerico vazio: $Field."
    }
    $number = 0.0
    if (![double]::TryParse($Value, [Globalization.NumberStyles]::Float, $invariant, [ref]$number) -or
        [double]::IsNaN($number) -or [double]::IsInfinity($number)) { throw "Campo numerico invalido: $Field." }
    return $number
}

function Read-Integer([string]$Value, [string]$Field, [bool]$Optional = $false) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        if ($Optional) { return $null }
        throw "Campo inteiro vazio: $Field."
    }
    $number = [long]0
    if (![long]::TryParse($Value, [Globalization.NumberStyles]::Integer, $invariant, [ref]$number)) {
        throw "Campo inteiro invalido: $Field."
    }
    return $number
}

function Measure-Intervals($Values) {
    $sorted = @($Values | Sort-Object)
    if ($sorted.Count -eq 0) {
        return [pscustomobject]@{ count = 0; mean_ms = $null; p95_ms = $null; max_ms = $null; percentile_method = 'nearest_rank' }
    }
    return [pscustomobject]@{
        count = $sorted.Count
        mean_ms = [math]::Round(($sorted | Measure-Object -Average).Average, 6)
        p95_ms = [math]::Round($sorted[[int][math]::Ceiling($sorted.Count * 0.95) - 1], 6)
        max_ms = [math]::Round($sorted[-1], 6)
        percentile_method = 'nearest_rank'
    }
}

function Sum-Field($Rows, [string]$Field) {
    $sum = [long]0
    foreach ($row in $Rows) { $sum += $row.$Field }
    return $sum
}

function Measure-Moves($Rows) {
    $moves = @($Rows | Where-Object { $_.event -eq 'move' -or $_.event -eq 'probe_move' })
    $calls = @($moves | Where-Object { $_.input_attempted })
    $accepted = @($calls | Where-Object { $null -ne $_.os_inserted_count -and $_.os_inserted_count -eq 1 })
    $rejected = @($calls | Where-Object { $null -ne $_.os_inserted_count -and $_.os_inserted_count -eq 0 })
    return [pscustomobject]@{
        move_records = $moves.Count; calls = $calls.Count
        accepted_windows = $accepted.Count; rejected_windows = $rejected.Count
        unknown_call_results = $calls.Count - $accepted.Count - $rejected.Count
        planned_dx_sum = Sum-Field $moves 'planned_dx'; planned_dy_sum = Sum-Field $moves 'planned_dy'
        requested_dx_sum = Sum-Field $calls 'requested_dx'; requested_dy_sum = Sum-Field $calls 'requested_dy'
        accepted_argument_dx_sum = Sum-Field $accepted 'requested_dx'
        accepted_argument_dy_sum = Sum-Field $accepted 'requested_dy'
    }
}

function Get-Counts($Rows, [string]$Field) {
    return @($Rows | Group-Object -Property $Field | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ value = $_.Name; count = $_.Count }
    })
}

function Escape-Html($Value) { return [Net.WebUtility]::HtmlEncode([string]$Value) }
function Format-Number($Value) {
    if ($null -eq $Value) { return '&#8212;' }
    return Escape-Html ([string]::Format([Globalization.CultureInfo]::GetCultureInfo('pt-BR'), '{0:N3}', $Value))
}

$session = (Resolve-Path -LiteralPath $SessionPath).ProviderPath
if (!(Test-Path -LiteralPath $session -PathType Container)) { throw 'SessionPath deve ser uma pasta de sessao.' }
$csvPath = Join-Path $session 'events.csv'
$manifestPath = Join-Path $session 'manifest.txt'
$csvBytes = Read-Snapshot $csvPath
$manifestBytes = Read-Snapshot $manifestPath
$snapshotUtc = [DateTimeOffset]::UtcNow.ToString('o')
$manifest = [ordered]@{}
foreach ($line in ([Text.Encoding]::UTF8.GetString($manifestBytes) -split "`r?`n")) {
    if ($line -match '^([^=]+)=(.*)$') { $manifest[$matches[1].TrimStart([char]0xFEFF)] = $matches[2] }
}
if (!$manifest.Contains('qpc_frequency_hz')) { throw 'manifest.txt nao informa qpc_frequency_hz.' }
$frequency = Read-Integer $manifest['qpc_frequency_hz'] 'qpc_frequency_hz'
if ($frequency -le 0) { throw 'qpc_frequency_hz deve ser positivo.' }

# A leitura usa o tamanho inicial do arquivo. Descartamos somente uma cauda CSV
# incompleta, inclusive campos multilinha, sem escrever nada nos logs originais.
$lastLf = [Array]::LastIndexOf($csvBytes, [byte]10)
if ($lastLf -lt 0) { throw 'CSV sem uma linha completa.' }
$utf8 = New-Object Text.UTF8Encoding($false, $true)
$csvText = $utf8.GetString($csvBytes, 0, $lastLf + 1)
$inQuotes = $false
$headerEnd = 0
$completeEnd = 0
for ($i = 0; $i -lt $csvText.Length; $i++) {
    if ($csvText[$i] -eq '"') {
        if ($inQuotes -and $i + 1 -lt $csvText.Length -and $csvText[$i + 1] -eq '"') { $i++ }
        else { $inQuotes = !$inQuotes }
    } elseif ($csvText[$i] -eq "`n" -and !$inQuotes) {
        $completeEnd = $i + 1
        if ($headerEnd -eq 0) { $headerEnd = $completeEnd }
    }
}
if ($completeEnd -eq 0) { throw 'CSV sem cabecalho completo.' }
$completeText = $csvText.Substring(0, $completeEnd)
$usedBytes = $utf8.GetByteCount($completeText)
$omittedBytes = $csvBytes.Length - $usedBytes
if ($omittedBytes -gt 0) { $warnings.Add("Cauda incompleta omitida: $omittedBytes bytes. Os dados brutos foram preservados.") }
$required = @('seq', 'utc', 'qpc_ticks', 'event', 'mode', 'profile', 'generation', 'burst', 'elapsed_ms', 'planned_dx', 'planned_dy', 'requested_dx', 'requested_dy', 'input_attempted', 'send_call_qpc_ticks', 'os_inserted_count', 'reason')
# A linha auxiliar materializa somente o esquema, mesmo quando nao ha eventos.
$headerText = $completeText.Substring(0, $headerEnd).TrimStart([char]0xFEFF)
$header = ($headerText + "0`n") | ConvertFrom-Csv
foreach ($field in $required) { if ($header.PSObject.Properties.Name -notcontains $field) { throw "Coluna ausente no CSV: $field." } }
$parsed = @($completeText.TrimStart([char]0xFEFF) | ConvertFrom-Csv)
$rows = New-Object 'System.Collections.Generic.List[object]'
$duplicates = New-Object 'System.Collections.Generic.List[long]'
$seen = New-Object 'System.Collections.Generic.HashSet[long]'
$gapCount = 0
$outOfOrder = 0
$previousSeq = [long]0
foreach ($raw in $parsed) {
    $seq = Read-Integer $raw.seq 'seq'
    if ($seq -le 0) { throw 'seq deve ser positivo.' }
    $timestamp = [DateTimeOffset]::Parse($raw.utc, $invariant, [Globalization.DateTimeStyles]::AssumeUniversal)
    if (!$seen.Add($seq)) { $duplicates.Add($seq) }
    if ($previousSeq -gt 0 -and $seq -gt $previousSeq + 1) { $gapCount += $seq - $previousSeq - 1 }
    if ($previousSeq -gt 0 -and $seq -le $previousSeq) { $outOfOrder++ }
    $previousSeq = $seq
    $attempted = Read-Integer $raw.input_attempted 'input_attempted'
    if ($attempted -ne 0 -and $attempted -ne 1) { throw 'input_attempted deve ser 0 ou 1.' }
    $kind = if ($raw.event -like 'probe_*' -or $raw.profile -eq 'InputProbe') { 'probe' } elseif ($raw.mode -eq 'dry_run') { 'dry_run' } else { 'compensation' }
    $rows.Add([pscustomobject]@{
        seq = $seq; utc = $timestamp.ToUniversalTime().ToString('o'); event = [string]$raw.event
        profile = [string]$raw.profile; mode = [string]$raw.mode; kind = $kind; reason = [string]$raw.reason
        qpc_ticks = Read-Integer $raw.qpc_ticks 'qpc_ticks'
        generation = Read-Integer $raw.generation 'generation'; burst = Read-Integer $raw.burst 'burst'
        elapsed_ms = Read-Number $raw.elapsed_ms 'elapsed_ms'
        planned_dx = Read-Integer $raw.planned_dx 'planned_dx'; planned_dy = Read-Integer $raw.planned_dy 'planned_dy'
        requested_dx = Read-Integer $raw.requested_dx 'requested_dx'; requested_dy = Read-Integer $raw.requested_dy 'requested_dy'
        input_attempted = [bool]$attempted
        send_call_qpc_ticks = Read-Integer $raw.send_call_qpc_ticks 'send_call_qpc_ticks' $true
        os_inserted_count = Read-Integer $raw.os_inserted_count 'os_inserted_count' $true
    })
}
if ($duplicates.Count) { $warnings.Add('Existem sequencias duplicadas; os totais incluem todos os registros, sem deduplicacao.') }
if ($gapCount -gt 0 -or $outOfOrder -gt 0) { $warnings.Add('Ha lacunas ou sequencias fora de ordem; confira os logs brutos.') }
if (@($rows | Where-Object { $_.mode -eq 'dry_run' -and $_.input_attempted }).Count) { $warnings.Add('Anomalia: dry_run contem tentativa de entrada. Ela permanece separada da compensacao real.') }

$runs = New-Object 'System.Collections.Generic.List[object]'
$active = $null
foreach ($row in $rows) {
    $isStart = $row.event -eq 'burst_start' -or $row.event -eq 'probe_start'
    $isMove = $row.event -eq 'move' -or $row.event -eq 'probe_move'
    $sameRun = $null -ne $active -and $active.profile -eq $row.profile -and $active.mode -eq $row.mode -and $active.kind -eq $row.kind -and $active.burst -eq $row.burst -and $active.generation -eq $row.generation
    if ($isStart -or ($isMove -and !$sameRun)) {
        $active = [pscustomobject]@{
            id = $row.seq; kind = $row.kind; profile = $row.profile; mode = $row.mode; generation = $row.generation; burst = $row.burst
            start_seq = if ($isStart) { $row.seq } else { $null }; start_utc = if ($isStart) { $row.utc } else { $null }
            start_qpc_ticks = if ($isStart) { $row.qpc_ticks } else { $null }
            end_seq = $null; end_utc = $null; end_qpc_ticks = $null; stop_reason = $null; stop_elapsed_ms = $null
            rows = New-Object 'System.Collections.Generic.List[object]'
        }
        $runs.Add($active)
        if (!$isStart) { $warnings.Add("Movimento sem inicio correspondente: seq=$($row.seq).") }
    }
    if ($isMove) { $active.rows.Add($row) }
    if (($row.event -eq 'burst_stop' -or $row.event -eq 'probe_end') -and $null -ne $active -and
        $active.profile -eq $row.profile -and $active.mode -eq $row.mode -and $active.kind -eq $row.kind -and $active.burst -eq $row.burst) {
        $active.end_seq = $row.seq; $active.end_utc = $row.utc; $active.end_qpc_ticks = $row.qpc_ticks
        $active.stop_reason = $row.reason; $active.stop_elapsed_ms = $row.elapsed_ms
        $active = $null
    }
}
$runSummaries = New-Object 'System.Collections.Generic.List[object]'
$intervalsByRun = @{}
foreach ($run in $runs) {
    $calls = @($run.rows | Where-Object { $_.input_attempted })
    $intervals = New-Object 'System.Collections.Generic.List[double]'
    for ($i = 1; $i -lt $calls.Count; $i++) {
        if ($null -ne $calls[$i].send_call_qpc_ticks -and $null -ne $calls[$i - 1].send_call_qpc_ticks) {
            $delta = $calls[$i].send_call_qpc_ticks - $calls[$i - 1].send_call_qpc_ticks
            if ($delta -ge 0) { $intervals.Add($delta * 1000.0 / $frequency) }
            else { $warnings.Add("QPC regressivo entre chamadas na rajada id=$($run.id); intervalo omitido.") }
        }
    }
    $intervalsByRun[[string]$run.id] = $intervals.ToArray()
    $runSummaries.Add([pscustomobject]@{
        id = $run.id; kind = $run.kind; profile = $run.profile; mode = $run.mode; generation = $run.generation; burst = $run.burst
        start_seq = $run.start_seq; start_utc = $run.start_utc; end_seq = $run.end_seq; end_utc = $run.end_utc
        start_qpc_ticks = $run.start_qpc_ticks; end_qpc_ticks = $run.end_qpc_ticks
        observed_duration_ms = if ($null -ne $run.start_qpc_ticks -and $null -ne $run.end_qpc_ticks) { [math]::Round(($run.end_qpc_ticks - $run.start_qpc_ticks) * 1000.0 / $frequency, 6) } else { $null }
        stop_reason = $run.stop_reason; stop_elapsed_ms = $run.stop_elapsed_ms
        metrics = Measure-Moves $run.rows; call_intervals = Measure-Intervals $intervals
    })
}
$profiles = New-Object 'System.Collections.Generic.List[object]'
foreach ($group in ($rows | Where-Object { $_.profile -ne '' } | Group-Object profile, mode, kind)) {
    $sample = $group.Group[0]
    $matchingRuns = @($runSummaries | Where-Object { $_.profile -eq $sample.profile -and $_.mode -eq $sample.mode -and $_.kind -eq $sample.kind })
    $intervals = @(foreach ($run in $matchingRuns) { $intervalsByRun[[string]$run.id] })
    $profiles.Add([pscustomobject]@{
        profile = $sample.profile; mode = $sample.mode; kind = $sample.kind; records = $group.Count; runs = $matchingRuns.Count
        metrics = Measure-Moves $group.Group; call_intervals = Measure-Intervals $intervals
        stop_reasons = @(Get-Counts @($group.Group | Where-Object { $_.event -eq 'burst_stop' -or $_.event -eq 'probe_end' }) 'reason')
    })
}
$lastRow = if ($rows.Count) { $rows[$rows.Count - 1] } else { $null }
$lastState = @($rows | Where-Object { $_.event -notin @('move', 'probe_move') } | Select-Object -Last 1)
$summary = [ordered]@{
    schema_version = 1; generated_utc = [DateTimeOffset]::UtcNow.ToString('o'); session_path = $session
    snapshot = [ordered]@{
        read_utc = $snapshotUtc; csv_sha256 = Get-Hash $csvBytes; manifest_sha256 = Get-Hash $manifestBytes
        csv_hash_scope = 'SHA256 dos primeiros bytes_read bytes lidos; inclui a cauda parcial, quando houver.'
        bytes_read = $csvBytes.Length; complete_csv_bytes = $usedBytes; incomplete_tail_bytes = $omittedBytes
        records = $rows.Count; cutoff_utc = if ($null -ne $lastRow) { $lastRow.utc } else { $null }
        cutoff_seq = if ($null -ne $lastRow) { $lastRow.seq } else { $null }
        sequence_gaps = $gapCount; duplicate_sequences = $duplicates.ToArray(); out_of_order_sequences = $outOfOrder
    }
    manifest = $manifest
    evidence_scope = 'Aceitacao pelo Windows nao comprova recepcao no jogo, eficacia do spray, deteccao ou ausencia de ban. Unidades sao argumentos de movimento do Windows, nao pixels medidos no jogo.'
    interval_scope = 'Intervalos entre chamadas tentadas adjacentes dentro da mesma rajada/probe, usando send_call_qpc_ticks. Sem intervalos entre rajadas. Nao sao intervalos de tiros.'
    warnings = $warnings.ToArray()
    profiles = $profiles.ToArray()
    bursts = @($runSummaries | Where-Object { $_.kind -ne 'probe' })
    probes = @($runSummaries | Where-Object { $_.kind -eq 'probe' })
    event_counts = @(Get-Counts $rows 'event')
    stops = @(Get-Counts @($rows | Where-Object { $_.event -eq 'burst_stop' -or $_.event -eq 'disarmed' -or $_.event -eq 'session_expired' -or $_.event -eq 'probe_end' }) 'reason')
    last_control_event = if ($lastState.Count) { $lastState[0] } else { $null }
}

$profileHtml = New-Object Text.StringBuilder
foreach ($profile in $profiles) {
    $m = $profile.metrics; $t = $profile.call_intervals
    [void]$profileHtml.AppendLine("<tr><td>$(Escape-Html $profile.profile)</td><td>$(Escape-Html $profile.mode)</td><td>$(Escape-Html $profile.kind)</td><td>$($m.move_records)</td><td>$($m.calls)</td><td>$($m.accepted_windows)</td><td>$($m.rejected_windows)</td><td>$($m.unknown_call_results)</td><td>$($m.planned_dx_sum) / $($m.planned_dy_sum)</td><td>$($m.requested_dx_sum) / $($m.requested_dy_sum)</td><td>$(Format-Number $t.mean_ms)</td><td>$(Format-Number $t.p95_ms)</td><td>$(Format-Number $t.max_ms)</td></tr>")
}
function Make-RunRows($Items) {
    $html = New-Object Text.StringBuilder
    foreach ($run in $Items) {
        $m = $run.metrics; $t = $run.call_intervals
        [void]$html.AppendLine("<tr><td>$($run.id)</td><td>$(Escape-Html $run.profile)</td><td>$(Escape-Html $run.mode)</td><td>$($run.burst)</td><td>$(Escape-Html $run.start_utc)</td><td>$(Escape-Html $run.end_utc)</td><td>$(Escape-Html $run.stop_reason)</td><td>$(Format-Number $run.observed_duration_ms)</td><td>$($m.calls) / $($m.accepted_windows) / $($m.rejected_windows) / $($m.unknown_call_results)</td><td>$($m.requested_dx_sum) / $($m.requested_dy_sum)</td><td>$(Format-Number $t.mean_ms) / $(Format-Number $t.p95_ms) / $(Format-Number $t.max_ms)</td></tr>")
    }
    return $html.ToString()
}
$burstHtml = Make-RunRows $summary.bursts
$probeHtml = Make-RunRows $summary.probes
$stopHtml = ($summary.stops | ForEach-Object { "<li>$(Escape-Html $_.value): $($_.count)</li>" }) -join "`n"
$warningHtml = if ($warnings.Count) { ($warnings | ForEach-Object { "<li>$(Escape-Html $_)</li>" }) -join "`n" } else { '<li>Nenhuma anomalia estrutural identificada no snapshot.</li>' }
$stateHtml = if ($lastState.Count) { "$(Escape-Html $lastState[0].event) / $(Escape-Html $lastState[0].reason) em $(Escape-Html $lastState[0].utc)" } else { 'Sem eventos.' }
$runHeader = '<tr><th>ID (seq inicial)</th><th>Perfil</th><th>Modo</th><th>Rajada</th><th>Inicio UTC</th><th>Fim UTC</th><th>Motivo da parada</th><th>Duracao observada (QPC ms)</th><th>Chamadas / aceitas / rejeitadas / desconhecidas</th><th>Soma solicitada X / Y</th><th>Media / p95 / max (ms)</th></tr>'
$html = @"
<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'"><title>Auditoria da sessao &#8212; Recoil Lab</title>
<style>body{font:15px/1.5 system-ui,sans-serif;background:#f4f6f8;color:#172b3a;margin:0;padding:28px}main{max-width:1600px;margin:auto}h1{font-size:28px}h2{margin-top:28px}section,.notice{background:white;padding:18px;border-radius:8px;margin:16px 0;border:1px solid #d9e1e8}.notice{border-left:5px solid #d38a19}code{overflow-wrap:anywhere}table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:9px;border-bottom:1px solid #dce3e8;vertical-align:top}th{background:#e9eff4}td{font-variant-numeric:tabular-nums}.scroll{overflow:auto}.muted{color:#526574}dt{font-weight:600}dd{margin:0 0 10px;overflow-wrap:anywhere}@media print{body{padding:0;background:white}section{break-inside:avoid}table{font-size:9px}}</style></head>
<body><main><h1>Auditoria da sessao</h1><p class="muted">Relatorio local, sem rede. Data e hora sempre em UTC. Snapshot de uma unica sessao.</p>
<div class="notice">$(Escape-Html $summary.evidence_scope)<br>$(Escape-Html $summary.interval_scope)</div>
<section><h2>Corte e integridade</h2><dl><dt>Sessao</dt><dd>$(Escape-Html $session)</dd><dt>Corte dos eventos</dt><dd>$(Escape-Html $summary.snapshot.cutoff_utc) &#8212; seq $(Escape-Html $summary.snapshot.cutoff_seq); $($rows.Count) registros</dd><dt>Leitura</dt><dd>$(Escape-Html $snapshotUtc)</dd><dt>SHA256 do CSV lido</dt><dd><code>$(Escape-Html $summary.snapshot.csv_sha256)</code></dd><dt>Ultimo evento de controle registrado</dt><dd>$stateHtml</dd></dl><ul>$warningHtml</ul><p>A sessao pode continuar depois deste corte. O ultimo evento nao e uma consulta ao estado atual do processo. Arquivo JSON: <code>summary.json</code>.</p></section>
<section><h2>Perfis e modos</h2><p>Compensacao real, simulacao (dry_run) e probes ficam em linhas separadas. Planejado nao significa enviado. Soma solicitada inclui apenas tentativas; valores negativos podem cancelar positivos na soma.</p><div class="scroll"><table><thead><tr><th>Perfil</th><th>Modo</th><th>Tipo</th><th>Moves</th><th>Chamadas</th><th>Aceitas Windows</th><th>Rejeitadas Windows</th><th>Resultado desconhecido</th><th>Soma planejada X / Y</th><th>Soma solicitada X / Y</th><th>Media (ms)</th><th>P95 (ms)</th><th>Max (ms)</th></tr></thead><tbody>$profileHtml</tbody></table></div></section>
<section><h2>Rajadas</h2><p>ID usa a sequencia de inicio; nomes/numero de rajada repetidos nao unem intervalos entre execucoes. Fim vazio significa que a parada nao apareceu no corte. P95 usa o metodo nearest rank.</p><div class="scroll"><table><thead>$runHeader</thead><tbody>$burstHtml</tbody></table></div></section>
<section><h2>Probes de entrada</h2><p>Testes de entrada sao contabilizados separadamente, sem interpreta-los como compensacao de recuo.</p><div class="scroll"><table><thead>$runHeader</thead><tbody>$probeHtml</tbody></table></div></section>
<section><h2>Paradas e desarmes registrados</h2><ul>$stopHtml</ul><p>Os motivos sao eventos registrados, sem inferir limites a partir do tempo transcorrido ou recepcao do movimento pelo jogo.</p></section>
</main></body></html>
"@
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $OutputDirectory = Join-Path $session 'analysis' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if ([string]::Equals($output.TrimEnd('\'), $session.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputDirectory deve ser diferente da pasta dos logs brutos.' }
[void][IO.Directory]::CreateDirectory($output)
$jsonPath = Join-Path $output 'summary.json'
$htmlPath = Join-Path $output 'report.html'
[IO.File]::WriteAllText($jsonPath, ($summary | ConvertTo-Json -Depth 14), (New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
[pscustomobject]@{ SummaryPath = $jsonPath; ReportPath = $htmlPath; CutoffUtc = $summary.snapshot.cutoff_utc; CutoffSeq = $summary.snapshot.cutoff_seq; Records = $rows.Count }
