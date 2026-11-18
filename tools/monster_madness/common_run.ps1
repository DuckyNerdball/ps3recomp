param([string]$tag, [int]$secs = 240)
$ErrorActionPreference = 'Continue'
$wd = 'E:\Projects\MonsterDigger'; $proj = 'E:\Projects\ps3recomp\templates\project'
Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
if (-not $env:MM_VOLUME) { $env:MM_VOLUME = '0' }   # unattended test runs are muted
$env:GCM_SUBCH1_2D = '1'   # libgcm sub 1 = NV0039 copy engine (UE3 texture moves)
$env:PS3_HDD0_ROOT = 'E:/Projects/MonsterDigger/gamedata/dev_hdd0'; $env:D3D12_NO_DBG = '1'; $env:SPU_INTERP_UNLIFTED = '1'; $env:PS3_USRDIR_BASE = 'E:/Projects/MonsterDigger/disc/PS3_GAME'; $env:PS3_DEV_FLASH = 'E:/Projects/MonsterDigger/rpcs3/dev_flash'; if (-not $env:GCM_PARK_GRACE_MS) { $env:GCM_PARK_GRACE_MS = '30000' }
if (-not $env:MM_WATCHDOG) { $env:MM_WATCHDOG = '60' }
$t0 = Get-Date
$bdir = if ($env:MM_BUILD_DIR) { $env:MM_BUILD_DIR } else { 'build' }
$p = Start-Process "$proj\$bdir\MyGameRecomp.exe" -ArgumentList "$wd\disc\PS3_GAME\USRDIR\EBOOT.elf" -WorkingDirectory $wd -RedirectStandardOutput "$wd\logs\$tag.out.txt" -RedirectStandardError "$wd\logs\$tag.err.txt" -PassThru
while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt $secs) { Start-Sleep 5 }
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; "$tag stopped after $secs s" } else {
  "$tag EXITED after $([int]((Get-Date)-$t0).TotalSeconds) s code $($p.ExitCode)"
  Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001,1026; StartTime=$t0} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'MyGameRecomp' } | ForEach-Object { $_.Message } }
Start-Sleep 3
