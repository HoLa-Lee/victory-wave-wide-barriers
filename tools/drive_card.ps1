# Drives the title with REAL keystrokes (SendInput), not the scripted pad.
#
#   .\drive_card.ps1 -Tag card1 -Seconds 300 [-Seed] [-Warp] [-Script "60:Enter,80:Down,82:Down,84:Enter"]
#
# Why this exists: `VICTORY_KEYS` keys are produced (scripted() is polled ~120x a
# second) but on the card the menus do not move with them, while real key events
# do - measured 2026-11-25: a run with Down, Down, Enter sent by SendInput at
# 50 s advanced from the loading screen to the LANGUAGE page, which no scripted
# run ever did. So the card is driven by tapping it, and this script is the
# tapper.
param(
  [string]$Tag = "drive",
  [int]$Seconds = 300,
  [switch]$Seed,
  [switch]$Warp,
  [string]$Script = ""
)

$root = "C:\Users\admin\Documents\deepseek-harness\default-workspace"
$logs = Join-Path $root "vlogs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$dir = Join-Path $logs "data-$Tag"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }

if ($Seed) {
  New-Item -ItemType Directory -Force -Path "$dir\7952987A\storage\settings" | Out-Null
  $src = Join-Path $logs "data-seed2\7952987A\storage\settings\settings.xml"
  if (Test-Path $src) { Copy-Item $src "$dir\7952987A\storage\settings\settings.xml" -Force }
  else { New-Item -ItemType File -Path "$dir\7952987A\storage\settings\settings.xml" -Force | Out-Null }
}

foreach ($n in @('VICTORY_KEYS','VICTORY_D3D12_WARP','VICTORY_IDLE_MS','VICTORY_HOST_TEXTURE_CAP_MB')) {
  Remove-Item "Env:$n" -ErrorAction SilentlyContinue
}
$env:VICTORY_DATA_DIR = $dir
$env:VICTORY_LOG = 'info'
if ($Warp) { $env:VICTORY_D3D12_WARP = '1' }

Add-Type @'
using System; using System.Runtime.InteropServices;
public class Drive {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr extra);
  public static void Tap(int vk) { keybd_event((byte)vk, 0, 0, UIntPtr.Zero); System.Threading.Thread.Sleep(60); keybd_event((byte)vk, 0, 2, UIntPtr.Zero); System.Threading.Thread.Sleep(220); }
}
'@
$map = @{ 'Enter' = 0x0D; 'Down' = 0x28; 'Up' = 0x26; 'Left' = 0x25; 'Right' = 0x27; 'Esc' = 0x1B; 'Back' = 0x08 }

$plan = @()
if ($Script -ne "") {
  foreach ($entry in $Script.Split(',')) {
    $parts = $entry.Split(':')
    if ($parts.Count -eq 2 -and $map.ContainsKey($parts[1].Trim())) {
      $plan += [pscustomobject]@{ At = [double]$parts[0]; Vk = $map[$parts[1].Trim()] }
    }
  }
}
$plan = $plan | Sort-Object At

$exe = 'F:\迅雷云盘\GTA6-Cyberleek官网文件\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe'
$bin = Join-Path $root "victory-fork\target-b\diag\victory.exe"
$out = Join-Path $logs "$Tag.out.log"; $err = Join-Path $logs "$Tag.err.log"
Remove-Item $out, $err -ErrorAction SilentlyContinue

$p = Start-Process -FilePath $bin -ArgumentList @('run', $exe, '--execute') -PassThru -NoNewWindow `
  -RedirectStandardOutput $out -RedirectStandardError $err
$started = Get-Date
$i = 0
while (((Get-Date) - $started).TotalSeconds -lt $Seconds) {
  Start-Sleep -Milliseconds 250
  if ($p.HasExited) { break }
  $t = ((Get-Date) - $started).TotalSeconds
  while ($i -lt $plan.Count -and $plan[$i].At -le $t) {
    $p.Refresh()
    if (-not $p.HasExited) { [Drive]::SetForegroundWindow($p.MainWindowHandle) | Out-Null }
    [Drive]::Tap($plan[$i].Vk)
    Write-Output ("t={0:N0}s sent vk=0x{1:x}" -f $t, $plan[$i].Vk)
    $i++
  }
}
$alive = -not $p.HasExited
if ($alive) { $p.Kill(); Start-Sleep -Seconds 3 }
Write-Output ("alive={0} story_packs={1} world_packs={2}" -f $alive,
  (Select-String -Path $err -Pattern 'story000' -ErrorAction SilentlyContinue | Measure-Object).Count,
  (Select-String -Path $err -Pattern 'core_restofworld' -ErrorAction SilentlyContinue | Measure-Object).Count)
$fail = Select-String -Path $err -Pattern "device removed after|unhandled exception" | Select-Object -First 1
if ($fail) { Write-Output ("failure: " + $fail.Line.Substring(0, [Math]::Min(200, $fail.Line.Length))) }
