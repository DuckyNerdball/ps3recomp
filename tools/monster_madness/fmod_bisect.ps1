# Bisect which lifted FMOD ph1 function (LS 0x20080-0x364A0) stalls the game when MM_FMOD_LIFT=1.
# Each probe: an 80 s boot with MM_FMOD_SKIP=<interpreted ranges>; stalled = the last 3 [CLOCK] windows had 0 flips.
# Needs the local MM_FMOD_GUARD edit in spu_pm\mmfmod_recomp.c. Log: logs\fmodbis.txt
param([int]$lo = 0x20080, [int]$hi = 0x364A0, [int]$secs = 80)
$log = 'E:\Projects\MonsterDigger\logs\fmodbis.txt'
function Test-Stall([string]$skip, [string]$tag) {
    & "$PSScriptRoot\verify_run.ps1" -tag $tag -secs $secs -pad '' -set "MM_FMOD_LIFT=1;MM_FMOD_SKIP=$skip;MM_FLIPSTAT=1;MM_VOLUME=0" | Out-Null
    Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
    $f = "E:\Projects\MonsterDigger\logs\$tag.err.txt"
    $c = @(Select-String -Path $f -Pattern '\[CLOCK\] flips \+(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
    $stall = ($c.Count -ge 6) -and (($c | Select-Object -Last 3 | Measure-Object -Sum).Sum -eq 0)
    $line = "{0} skip={1,-24} stalled={2} clock={3}" -f (Get-Date -Format HH:mm:ss), $skip, $stall, ($c -join ',')
    Add-Content $log $line
    Remove-Item "E:\Projects\MonsterDigger\logs\$tag.*" -ErrorAction SilentlyContinue
    return $stall
}
function ConvertTo-Hx([int]$v) { '{0:X}' -f $v }
Add-Content $log "=== bisect $(Get-Date) range $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"
if (Test-Stall "$(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)" 'fb_all') { Add-Content $log 'skip-all still stalls: culprit is not in this range'; return }
if (-not (Test-Stall '1-1' 'fb_none')) { Add-Content $log 'no stall with nothing skipped: not reproducible'; return }
# Invariant: skipping [lo,hi] fixes; culprit inside.
while ($hi - $lo -gt 0x10) {
    $mid = ($lo + [int](($hi - $lo) / 2)) -band 0xFFFFFFF0
    if (-not (Test-Stall "$(ConvertTo-Hx $lo)-$(ConvertTo-Hx ($mid - 1))" "fb_$(ConvertTo-Hx $lo)")) { $hi = $mid - 1 }
    elseif (-not (Test-Stall "$(ConvertTo-Hx $mid)-$(ConvertTo-Hx $hi)" "fb_$(ConvertTo-Hx $mid)")) { $lo = $mid }
    else { Add-Content $log "neither half alone fixes it: more than one culprit in $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"; break }
}
Add-Content $log "RESULT: culprit range $(ConvertTo-Hx $lo)-$(ConvertTo-Hx $hi)"
