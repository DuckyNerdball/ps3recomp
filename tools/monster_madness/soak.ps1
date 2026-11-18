# Soak / fuzz harness for Zack's House.
#   .\soak.ps1 -runs 20 -secs 300 -seedStart 1 [-seeds 3,7,11] [-skipIntro] [-noBuild] [-batch name]
# Per seed: build_rel, muted, scripted autopad to gameplay, then MM_AUTOPAD_FUZZ=<seed> (deterministic input from
# the moment gameplay is live). Logs -> logs\soak\<seed>\, one row per run -> logs\soak\results.csv,
# batch summary at the end. Real controllers are ignored (cellPad unfocused-pad rule) unless PAD_BACKGROUND is set.
param([int]$runs = 20, [int]$secs = 300, [int]$seedStart = 1, [int[]]$seeds = @(), [switch]$skipIntro,
      [switch]$noBuild, [string]$batch = '', [string]$extraEnv = '')
$ErrorActionPreference = 'Continue'
$wd = 'E:\Projects\MonsterDigger'; $proj = 'E:\Projects\ps3recomp\templates\project'
$root = "$wd\logs\soak"; New-Item -ItemType Directory -Force $root | Out-Null
$csv = "$root\results.csv"; $sigdb = "$root\signatures.txt"
if (-not $batch) { $batch = Get-Date -Format 'yyyyMMdd-HHmm' }
if (-not $seeds.Count) { $seeds = $seedStart..($seedStart + $runs - 1) }

if (-not $noBuild) {
    $vs = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath
    & "$vs\Common7\Tools\Launch-VsDevShell.ps1" -Arch amd64 -SkipAutomaticLocation 2>$null | Out-Null
    cmake --build "$proj\build_rel" -j 8 > "$root\build.txt" 2>&1
    if ($LASTEXITCODE -ne 0) { "BUILD FAILED (see $root\build.txt)"; exit 1 }
}

# Scripted route to gameplay: title -> menu -> Adventure -> character -> difficulty, X on chapter select and
# level card. The X at 112 s lands 2-3 s into the comic intro (SkippableMovies) -- only with -skipIntro.
$pad = if ($skipIntro) { '75-95/5:S,100-140/4:X' } else { '75-95/5:S,100-106/6:X' }   # skip: X until the comic is surely open

$knownSigs = @{}; if (Test-Path $sigdb) { Get-Content $sigdb | ForEach-Object { $knownSigs[$_] = 1 } }
if (-not (Test-Path $csv)) {
    'batch,seed,secs,skip_intro,reached_level,reached_s,flips_last15s,exit_code,hang,hang_lr,hang_s,fps_gameplay_avg,fps_gameplay_p5,longest_frame_ms,fps_worst_window,audio_silent_pct,audio_underruns,strobe,unknown_rsx_methods,new_log_signatures,buckets' |
        Out-File $csv -Encoding ascii
}
$sigRe = '(?i)\berror\b|fail|unknown|unimpl|abort|exception|assert|stall|overflow|bad branch|not taken|invalid|timed? ?out|deadlock'
$noiseRe = '^\[(WAIT|WAKE|evt|sys_memory|sem|SYS|THREAD|fs|sys_fs|LUMA|FRAMESTAT|CLOCK|FLIPSTAT|PERF|audio-rate|mm-autopad|mm-fuzz|DUMPT|D3D12\] dumped)'

function Get-Norm([string]$l) { ($l -replace '0x[0-9A-Fa-f]+', 'X' -replace '\b\d+(\.\d+)?\b', 'N' -replace '\s+', ' ').Trim() }

$rows = @()
foreach ($seed in $seeds) {
    $dir = "$root\$seed"; Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force "$dir\frames" | Out-Null
    $tag = "soak_$seed"
    # --- environment (set/clear every switch explicitly) ---
    $clear = 'CELLMARK_DUMP_EVERY','RENDERDOC_DLL','RENDERDOC_DIR','RENDERDOC_MAX','FP_DUMP','MM_RTFP','MM_RTFP_QUAD',
             'MM_BG_ALPHA0','MM_CLEAR_DBG','MM_NO_BLOOM','MM_SHARPEN','MM_SHOWRT','MM_COLLAPSE_DBG','MM_HWWATCH','FP_PICK',
             'MM_PADLOG','MM_RTTEX_DBG','MM_BGQ_DBG','MM_INLINE_LOG','MM_NO_TEXGAMMA','PAD_BACKGROUND','MM_STROBE_RDOC',
             'FP_CONSTBUF','SCREEN_AS_TEX','PS3_SAMPLE','MM_FMOD_LIFT'
    foreach ($k in $clear) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
    $env:MM_BUILD_DIR = 'build_rel'; $env:MM_VOLUME = '0'; $env:MM_FLIPSTAT = '1'; $env:PERF = '1'; $env:AUDIO_RATE = '1'
    $env:MM_WATCHDOG = '30'; $env:MM_FRAMESTAT = '1'; $env:MM_LUMALOG = '250:2'; $env:MM_REFWAIT = '0016FBE4'
    $env:SPU_FLOAT_RZ = '1'; $env:MM_USLEEP_CAP = '01230DA4:300'; $env:MM_CLOCK_SLEEP_MS = '1'
    $env:MM_PM_MASK = '3'; $env:MM_PM1_SKIP = 'A70,C40,1C04-1C57'; $env:MM_NO_PM_LIFT = ''
    $env:MM_AUTOPAD = $pad; $env:MM_AUTOPAD_FUZZ = "$seed"
    $env:CELLMARK_DUMP = '1'; $env:CELLMARK_DUMP_SKIP = '999999'; $env:MM_DUMP_PERIOD_MS = '10000'
    $env:CELLMARK_DUMP_MINDRAWS = '1'; $env:CELLMARK_DUMP_DIR = "$dir\frames"
    foreach ($kv in ($extraEnv -split ';')) { if ($kv -match '^([^=]+)=(.*)$') { Set-Item "env:$($matches[1])" $matches[2] } }

    $res = & "$wd\_run\common_run.ps1" -tag $tag -secs $secs
    Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
    # the killed process (and the redirect handles) take a moment to let go of the logs
    for ($w = 0; $w -lt 30 -and (Get-Process MyGameRecomp -ErrorAction SilentlyContinue); $w++) { Start-Sleep -Milliseconds 500 }
    foreach ($p in @(@("$tag.err.txt", 'err.txt'), @("$tag.out.txt", 'out.txt'))) {
        for ($w = 0; $w -lt 20; $w++) { try { Move-Item "$wd\logs\$($p[0])" "$dir\$($p[1])" -Force -ErrorAction Stop; break } catch { Start-Sleep -Milliseconds 500 } } }
    $exit = 'timeout'; foreach ($r in @($res)) { if ("$r" -match 'EXITED after \d+ s code (-?\d+)') { $exit = $matches[1] } }
    ($res | Out-String) | Out-File "$dir\run.txt"

    # --- parse ---
    $L = Get-Content "$dir\err.txt"
    $clock = @(); $liveIdx = -1; $lastFrameIdx = -1; $fs = @(); $aud = @(); $luma = @(); $lr = ''; $unk = @{}; $refwait = $false
    $nClock = 0
    foreach ($l in $L) {
        if ($l -match '^\[CLOCK\] flips \+(\d+)') { $clock += [int]$matches[1]; $nClock++; continue }
        if ($l -match '^\[mm-fuzz\] gameplay live') { $liveIdx = $nClock; continue }
        if ($l -match '^\[FRAMESTAT\] frames=(\d+) mean=([\d.]+)ms p95=([\d.]+)ms max=([\d.]+)ms') {
            $fs += [pscustomobject]@{ i = $nClock; n = [int]$matches[1]; mean = [double]$matches[2]; p95 = [double]$matches[3]; max = [double]$matches[4] }
            $lastFrameIdx = $nClock; continue }
        if ($l -match '^\[audio-rate\] [\d.]+ blocks/s .*silent ([\d.]+)%.*underruns (\d+)') {
            $aud += [pscustomobject]@{ i = $nClock; s = [double]$matches[1]; u = [int]$matches[2] }; continue }
        if ($l -match '^\[LUMA\] t=(\d+) draws=\d+ l=([\d,]+)') { $v = $matches[2] -split ','
            $luma += [pscustomobject]@{ t = [long]$matches[1]; d = [math]::Abs([double]$v[0] - [double]$v[-1]) }; continue }
        if ($l -match 'guest-tid 1 +lr=(0x[0-9A-F]+)') { $lr = $matches[1]; continue }
        if ($l -match '^\[REFWAIT\]') { $refwait = $true; continue }
        if ($l -match 'unknown method (0x[0-9A-F]+)') { $unk[$matches[1]] = 1 }
    }
    $reached = $liveIdx -ge 0
    $reachedS = if ($reached) { [math]::Max(0, ($liveIdx - 1) * 5) } else { '' }
    $flipsEnd = ($clock | Select-Object -Last 3 | Measure-Object -Sum).Sum
    # hang: no rendered frame (>= 1 draw) during the last 20 s of a run that lasted, or a stuck ref-wait
    $hang = ($nClock -ge 6 -and ($lastFrameIdx -lt 0 -or $nClock - $lastFrameIdx -ge 4)) -or $refwait
    $hangS = if ($hang) { [math]::Max(0, $lastFrameIdx) * 5 } else { '' }
    $g = @($fs | Where-Object { $reached -and $_.i -gt $liveIdx })
    $fpsAvg = ''; $fpsP5 = ''; $longest = ''; $worstWin = ''
    if ($g.Count) {
        $fr = ($g | Measure-Object n -Sum).Sum; $tm = ($g | ForEach-Object { $_.n * $_.mean } | Measure-Object -Sum).Sum
        $fpsAvg = [math]::Round(1000 * $fr / $tm, 1)
        $p95 = ($g | ForEach-Object { $_.n * $_.p95 } | Measure-Object -Sum).Sum / $fr
        $fpsP5 = [math]::Round(1000 / $p95, 1)
        $longest = [math]::Round(($g | Measure-Object max -Maximum).Maximum, 0)
        $worstWin = [math]::Round((($g | ForEach-Object { 1000 / $_.mean }) | Measure-Object -Minimum).Minimum, 1)
    }
    $ga = @($aud | Where-Object { if ($reached) { $_.i -gt $liveIdx } else { $true } })
    $sil = if ($ga.Count) { [math]::Round(($ga | Measure-Object s -Average).Average, 1) } else { '' }
    $und = ($ga | Measure-Object u -Sum).Sum
    # strobe: consecutive-frame luma pairs that differ by > 40, sustained for > 2 s
    $strobe = $false; $runStart = -1
    for ($i = 0; $i -lt $luma.Count; $i++) {
        if ($luma[$i].d -gt 40) { if ($runStart -lt 0) { $runStart = $i }
            if ($luma[$i].t - $luma[$runStart].t -gt 2000) { $strobe = $true } }
        else { $runStart = -1 }
    }
    # new log signatures (stderr + stdout: printf-based messages land in out.txt)
    $LO = Get-Content "$dir\out.txt"
    foreach ($l in $LO) { if ($l -match 'unknown method (0x[0-9A-F]+)') { $unk[$matches[1]] = 1 } }
    $new = @{}
    foreach ($l in ($L + $LO)) { if ($l -match $sigRe -and $l -notmatch $noiseRe) { $n = Get-Norm $l
        if ($n.Length -gt 200) { $n = $n.Substring(0, 200) }
        if (-not $knownSigs.ContainsKey($n)) { $new[$n] = 1 } } }
    if ($new.Count) { $new.Keys | Out-File "$dir\new_signatures.txt"; $new.Keys | Add-Content $sigdb; foreach ($k in $new.Keys) { $knownSigs[$k] = 1 } }

    $buckets = @()
    if ($hang) { $buckets += "hang:$lr" }
    if ($exit -ne 'timeout') { $buckets += "exit:$exit" }
    if (-not $reached -and -not $hang) { $buckets += 'not_reached' }
    if ($strobe) { $buckets += 'strobe' }
    if ($longest -ne '' -and $longest -ge 3000) { $buckets += 'stall' }
    if ($g.Count -ge 4) { $med = @($g | ForEach-Object { 1000 / $_.mean } | Sort-Object)[[int]($g.Count / 2)]
        if ($worstWin -lt 0.8 * $med) { $buckets += 'low_fps' } }
    if ($sil -ne '' -and $sil -gt 5) { $buckets += 'high_silence' }
    $fail = $buckets.Count -gt 0

    # frames: failure -> last 10 as PNG; clean -> last 1 as PNG; BMPs always deleted
    Add-Type -AssemblyName System.Drawing
    $bmps = @(Get-ChildItem "$dir\frames" -Filter *.bmp | Sort-Object Name)
    $keep = if ($fail) { 10 } else { 1 }
    foreach ($b in ($bmps | Select-Object -Last $keep)) { $im = [System.Drawing.Bitmap]::FromFile($b.FullName)
        $im.Save(($b.FullName -replace '\.bmp$', '.png'), [System.Drawing.Imaging.ImageFormat]::Png); $im.Dispose() }
    $bmps | Remove-Item -Force
    if (-not $fail) { Remove-Item "$dir\err.txt", "$dir\out.txt" -Force }

    $row = [pscustomobject]@{ batch = $batch; seed = $seed; secs = $secs; skip_intro = [int][bool]$skipIntro
        reached_level = $(if ($reached) {'Y'} else {'N'}); reached_s = $reachedS; flips_last15s = $flipsEnd; exit_code = $exit
        hang = $(if ($hang) {'Y'} else {'N'}); hang_lr = $(if ($hang) {$lr} else {''}); hang_s = $hangS
        fps_gameplay_avg = $fpsAvg; fps_gameplay_p5 = $fpsP5; longest_frame_ms = $longest; fps_worst_window = $worstWin
        audio_silent_pct = $sil; audio_underruns = $und; strobe = $(if ($strobe) {'Y'} else {'N'})
        unknown_rsx_methods = $unk.Count; new_log_signatures = $new.Count; buckets = ($buckets -join ' ') }
    ($row | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1) | Add-Content $csv
    $rows += $row
    "seed {0,-6} reached={1}{2,-5} fps={3,-5} p5={4,-5} max={5,-5}ms sil={6,-5}% hang={7} {8}" -f $seed, $row.reached_level,
        $row.reached_s, $fpsAvg, $fpsP5, $longest, $sil, $row.hang, ($buckets -join ' ')
}
Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force

# --- summary ---
"`n=== batch $batch : $($rows.Count) runs x $secs s (skipIntro=$([bool]$skipIntro)) ==="
$clean = @($rows | Where-Object { -not $_.buckets }); "clean: $($clean.Count)"
$bk = @{}; foreach ($r in $rows) { foreach ($b in ($r.buckets -split ' ' | Where-Object { $_ })) { if (-not $bk[$b]) { $bk[$b] = @() }; $bk[$b] += $r.seed } }
foreach ($k in ($bk.Keys | Sort-Object { -$bk[$_].Count })) { "{0,-28} {1,3}  seeds: {2}" -f $k, $bk[$k].Count, ($bk[$k] -join ',') }
$gr = @($rows | Where-Object { $_.fps_gameplay_avg -ne '' })
if ($gr.Count) {
    "gameplay fps avg (mean of runs): {0:N1}   p5: {1:N1}   worst longest frame: {2} ms   silent% mean: {3:N1}" -f `
        ($gr | Measure-Object fps_gameplay_avg -Average).Average, ($gr | Measure-Object fps_gameplay_p5 -Average).Average,
        ($gr | Measure-Object longest_frame_ms -Maximum).Maximum,
        (@($rows | Where-Object { $_.audio_silent_pct -ne '' }) | Measure-Object audio_silent_pct -Average).Average }
