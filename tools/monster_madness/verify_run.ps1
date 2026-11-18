# Unattended build_rel run with run_good.ps1's speed/audio defaults. Extra env vars: pass -set "K=V;K2=V2".
# Clears the debug switches it knows about first so a PowerShell session can't leak them between runs.
param([string]$tag, [int]$secs = 120, [string]$set = '', [string]$pad = '75-95/5:S')
$clear = 'CELLMARK_DUMP','CELLMARK_DUMP_EVERY','CELLMARK_DUMP_SKIP','CELLMARK_DUMP_MINDRAWS','CELLMARK_DUMP_DIR',
         'MM_DUMP_PERIOD_MS','RENDERDOC_DLL','RENDERDOC_DIR','RENDERDOC_MAX','FP_DUMP','MM_RTFP','MM_RTFP_QUAD',
         'MM_BG_ALPHA0','MM_CLEAR_DBG','MM_NO_BLOOM','MM_SHARPEN','MM_SHOWRT','MM_COLLAPSE_DBG','MM_HWWATCH','FP_PICK'
foreach ($k in $clear) { Remove-Item "env:$k" -ErrorAction SilentlyContinue }
$env:MM_BUILD_DIR = 'build_rel'; $env:MM_VOLUME = '0.1'; $env:MM_FLIPSTAT = '1'
$env:SPU_FLOAT_RZ = '1'; $env:MM_USLEEP_CAP = '01230DA4:300'; $env:MM_CLOCK_SLEEP_MS = '1'
$env:MM_PM_MASK = '3'; $env:MM_PM1_SKIP = 'A70,C40,1C04-1C57'; $env:MM_NO_PM_LIFT = ''; $env:MM_WATCHDOG = '60'
$env:MM_AUTOPAD = $pad
foreach ($kv in ($set -split ';')) { if ($kv -match '^([^=]+)=(.*)$') { Set-Item "env:$($matches[1])" $matches[2] } }
if ($env:CELLMARK_DUMP_DIR) { New-Item -ItemType Directory -Force $env:CELLMARK_DUMP_DIR | Out-Null }
if ($env:RENDERDOC_DIR) { New-Item -ItemType Directory -Force $env:RENDERDOC_DIR | Out-Null }
& "$PSScriptRoot\common_run.ps1" -tag $tag -secs $secs
Get-Process MyGameRecomp -ErrorAction SilentlyContinue | Stop-Process -Force
