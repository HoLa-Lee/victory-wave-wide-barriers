# Runs the seeded world route and samples the host's memory every ten seconds.
#
#   .\world_ram.ps1 -Tag mem1 -Seconds 340 [-IdleMs 1000] [-Warp $false]
#
# The route is the one docs/world-death.md records: an empty
# Z:\settings\settings.xml skips the setup pages, and seven keys every 14 s
# walk the menus ("A" is Enter). Prints one line per sample (free RAM, working
# set) and, at the end, where the run failed.
param(
  [string]$Tag = "mem",
  [int]$Seconds = 340,
  [string]$IdleMs = "",
  [switch]$Warp = $false,
  [string]$Tree = "victory-fork"
)

$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
$root = "C:\Users\admin\Documents\deepseek-harness\default-workspace"
$logs = Join-Path $root "vlogs"
New-Item -ItemType Directory -Force -Path $logs | Out-Null

$dir = Join-Path $logs "data-$Tag"
if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
New-Item -ItemType Directory -Force -Path "$dir\7952987A\storage\settings" | Out-Null
New-Item -ItemType File -Path "$dir\7952987A\storage\settings\settings.xml" -Force | Out-Null

$seq = @()
for ($t = 60; $t -le ($Seconds - 20); $t += 14) {
  $seq += "$t`:Up"; $seq += ("{0}:Enter" -f ($t + 0.8)); $seq += ("{0}:Up" -f ($t + 1.6))
  $seq += ("{0}:Enter" -f ($t + 2.4)); $seq += ("{0}:Down" -f ($t + 3.2)); $seq += ("{0}:Down" -f ($t + 4.0))
  $seq += ("{0}:Enter" -f ($t + 4.8))
}

foreach ($n in @('VICTORY_D3D12_WARP','VICTORY_IDLE_MS','VICTORY_SKIP_EMPTY_INDIRECT',
                 'VICTORY_COPY_MODE','VICTORY_D3D12_DEBUG','VICTORY_D3D12_DRED','VICTORY_SWEEP')) {
  Remove-Item "Env:$n" -ErrorAction SilentlyContinue
}
$env:VICTORY_DATA_DIR = $dir
$env:VICTORY_LOG = 'info'
$env:VICTORY_KEYS = ($seq -join ',')
if ($Warp) { $env:VICTORY_D3D12_WARP = '1' }
if ($IdleMs -ne "") { $env:VICTORY_IDLE_MS = $IdleMs }

$exe = 'F:\迅雷云盘\GTA6-Cyberleek官网文件\GTA6.Xbox.v1.0.2.1-CYBERLEEK\game_scarlett_master.exe'
$bin = Join-Path $root "$Tree\target-b\diag\victory.exe"
$out = Join-Path $logs "$Tag.out.log"
$err = Join-Path $logs "$Tag.err.log"
Remove-Item $out, $err -ErrorAction SilentlyContinue

$p = Start-Process -FilePath $bin -ArgumentList @('run', $exe, '--execute') -PassThru -NoNewWindow `
  -RedirectStandardOutput $out -RedirectStandardError $err

$maxWs = 0.0; $minFree = 999.0
for ($i = 0; $i * 10 -lt $Seconds; $i++) {
  Start-Sleep -Seconds 10
  if ($p.HasExited) { Write-Output ("t={0}s EXITED" -f ($i * 10)); break }
  $free = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 2)
  $ws = [math]::Round((Get-Process -Id $p.Id).WorkingSet64 / 1GB, 2)
  if ($ws -gt $maxWs) { $maxWs = $ws }
  if ($free -lt $minFree) { $minFree = $free }
  Write-Output ("t={0}s free={1}GB ws={2}GB" -f ($i * 10), $free, $ws)
}
$alive = -not $p.HasExited
if ($alive) { $p.Kill(); Start-Sleep -Seconds 3 }

$mem = (Select-String -Path $err -Pattern "memory: [0-9]+ MB private" | Select-Object -Last 1)
if ($mem) { Write-Output ("last memory line: " + ($mem.Line -replace '^.*copystat: ', '')) }
$fail = (Select-String -Path $err -Pattern "device removed after|unhandled exception" | Select-Object -First 1)
if ($fail) { Write-Output ("failure: " + $fail.Line.Substring(0, [Math]::Min(200, $fail.Line.Length))) }
Write-Output ("max working set {0} GB, min free {1} GB" -f $maxWs, $minFree)
