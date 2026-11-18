# Smallest lifted FMOD ph1 range that still stalls: only [lo,hi] lifted, the rest of 0x20080-0x364A0 interpreted.
# Invariant: lifting only [lo,hi] stalls. Log: logs\fmodbis2.txt
param([int]$lo = 0x20080, [int]$hi = 0x364A0, [int]$secs = 80)
$log = 'E:\Projects\MonsterDigger\logs\fmodbis2.txt'
$L0 = 0x20080; $H0 = 0x364A0
function ConvertTo-Hx([int]$v) { '{0:X}' -f $v }
function Get-SkipFor([int]$a, [int]$b) {
    $r = @(); if ($a -gt $L0) { $r += "$(ConvertTo-Hx $L0)-$(ConvertTo-Hx ($a - 1))" }
    if ($b -lt $H0) { $r += "$(ConvertTo-Hx ($b + 1))-$(ConvertTo-Hx $H0)" }
    if (-not $r.Count) { return '1-1' }; return ($r -join ',')
}
function Test-Lifted([int]$a, [int]$b) {
    $skip = Get-SkipFor $a $b; $tag = "fb2_$(ConvertTo-Hx $a)"
    & "$PSScriptRoot\verify_run.ps1" -tag $tag -secs $secs -pad '' -set "MM_FMOD_LIFT=1;MM_FMOD_SKIP=$skip;MM_FLIPSTAT=1;MM_VOLUME=0" | Out-Null
    Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
    $c = @(Select-String -Path "E:\Projects\MonsterDigger\logs\$tag.err.txt" -Pattern '\[CLOCK\] flips \+(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
    $stall = ($c.Count -ge 6) -and (($c | Select-Object -Last 3 | Measure-Object -Sum).Sum -eq 0)
    Add-Content $log ("{0} lifted={1}-{2} stalled={3} clock={4}" -f (Get-Date -Format HH:mm:ss), (ConvertTo-Hx $a), (ConvertTo-Hx $b), $stall, ($c -join ','))
    Remove-Item "E:\Projects\MonsterDigger\logs\$tag.*" -ErrorAction SilentlyContinue
    return $stall
}
Add-Content $log "=== bisect2 $(Get-Date) range $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"
while ($hi - $lo -gt 0x10) {
    $mid = ($lo + [int](($hi - $lo) / 2)) -band 0xFFFFFFF0
    if (Test-Lifted $lo ($mid - 1)) { $hi = $mid - 1 }
    elseif (Test-Lifted $mid $hi) { $lo = $mid }
    else { Add-Content $log "neither half alone stalls: needs code from both halves of $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"; break }
}
Add-Content $log "RESULT: smallest stalling lifted range $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"
