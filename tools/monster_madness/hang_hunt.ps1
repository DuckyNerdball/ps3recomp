# Repeated short boots to catch the 1-in-20 pre-title hang (main thread parked at lr 0x0016FBE4).
# Stops at the first run whose log shows [REFWAIT] (or a watchdog line with that lr). Logs: logs\hh_<n>.*
param([int]$runs = 25, [int]$secs = 50)
for ($i = 1; $i -le $runs; $i++) {
    & "$PSScriptRoot\verify_run.ps1" -tag "hh_$i" -secs $secs -pad '' -set 'MM_REFWAIT=0016FBE4' | Out-Null
    $f = "E:\Projects\MonsterDigger\logs\hh_$i.err.txt"
    $hit = Select-String -Path $f -Pattern '\[REFWAIT\]|guest-tid 1 +lr=0x0016FBE4' -Quiet
    "run $i : $(if ($hit) {'HANG'} else {'ok'})"
    if ($hit) { break }
    Remove-Item "E:\Projects\MonsterDigger\logs\hh_$i.*"
}
Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
