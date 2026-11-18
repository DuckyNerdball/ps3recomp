# Summarise logs\soak\results.csv. -batches a,b: rows from those batches (later batch wins per seed).
# Buckets are recomputed from the row so old batches get the current rules (stall = a frame >= 3 s).
param([string[]]$batches = @(), [int[]]$seeds = @())
$rows = Import-Csv 'E:\Projects\MonsterDigger\logs\soak\results.csv'
if ($batches.Count) { $rows = $rows | Where-Object { $batches -contains $_.batch } }
if ($seeds.Count) { $rows = $rows | Where-Object { $seeds -contains [int]$_.seed } }
$last = @{}; foreach ($r in $rows) { $last[$r.seed] = $r }
$rows = @($last.Values | Sort-Object { [int]$_.seed })
foreach ($r in $rows) {
    $b = @($r.buckets -split ' ' | Where-Object { $_ -and $_ -ne 'stall' })
    if ($r.longest_frame_ms -ne '' -and [double]$r.longest_frame_ms -ge 3000) { $b += 'stall' }
    $r | Add-Member -NotePropertyName bk -NotePropertyValue $b -Force
}
$n = $rows.Count
"runs: $n   clean: $(@($rows | Where-Object { -not $_.bk.Count }).Count)"
$bk = @{}; foreach ($r in $rows) { foreach ($x in $r.bk) { $k = $x; if (-not $bk[$k]) { $bk[$k] = @() }; $bk[$k] += $r.seed } }
"{0,-26} {1,5} {2,6}  {3}" -f 'bucket', 'runs', 'rate', 'seeds'
foreach ($k in ($bk.Keys | Sort-Object { -$bk[$_].Count })) { "{0,-26} {1,5} {2,5:P0}  {3}" -f $k, $bk[$k].Count, ($bk[$k].Count / $n), ($bk[$k] -join ',') }
$g = @($rows | Where-Object { $_.fps_gameplay_avg -ne '' })
function M($a, $p) { $v = @($a | ForEach-Object { [double]$_.$p }); if ($v.Count) { ($v | Measure-Object -Average).Average } else { 0 } }
"reached gameplay: {0}/{1}" -f $g.Count, $n
if ($g.Count) {
    "gameplay fps avg {0:N1} | p5 {1:N1} | worst 5s window {2:N1} | longest frame median {3:N0} ms, max {4:N0} ms | silent {5:N1}% | underruns {6}" -f `
        (M $g fps_gameplay_avg), (M $g fps_gameplay_p5), (M $g fps_worst_window),
        (@($g | ForEach-Object { [double]$_.longest_frame_ms } | Sort-Object)[[int]($g.Count / 2)]),
        (($g | ForEach-Object { [double]$_.longest_frame_ms }) | Measure-Object -Maximum).Maximum,
        (M $g audio_silent_pct), (($g | ForEach-Object { [int]$_.audio_underruns }) | Measure-Object -Sum).Sum }
