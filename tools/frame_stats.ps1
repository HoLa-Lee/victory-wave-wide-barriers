# Compares configurations from the logs the runs already left behind.
#
#   .\frame_stats.ps1 -Logs cardworld9,cardskip2,carddw3
#
# Reads vlogs\<tag>.err.log, takes every frame line
#   0.4 fps, 2333.8 ms/frame (1008.6 preparing: copies 50.0 ms 162.6 MB, textures 917.4 ms 278.5 MB; ...), 5684 draws/frame
# and reports per tag: how many frames were logged, the median and best frame time,
# the median of the textures ms and MB, and the median draws — the numbers that can be
# compared between configurations whose phases differ.
param([string[]]$Logs, [int]$MinDraws = 500, [string]$Root = "C:\Users\admin\Documents\deepseek-harness\default-workspace\vlogs")

$rows = @()
foreach ($tag in $Logs) {
  $path = Join-Path $Root "$tag.err.log"
  if (-not (Test-Path $path)) { Write-Output ("{0}: no log" -f $tag); continue }
  $ms = @(); $tex = @(); $texMb = @(); $draws = @()
  foreach ($line in (Select-String -Path $path -Pattern 'ms/frame' | ForEach-Object { $_.Line })) {
    # Menus log tens of draws a frame and would drown the story: only frames
    # with a story's worth of draws count (see -MinDraws).
    $d = 0
    if ($line -match '([\d]+) draws/frame') { $d = [int]$matches[1] }
    if ($d -lt $MinDraws) { continue }
    if ($line -match '([\d.]+) ms/frame') { $ms += [double]$matches[1] }
    if ($line -match 'textures ([\d.]+) ms ([\d.]+) MB') { $tex += [double]$matches[1]; $texMb += [double]$matches[2] }
    if ($line -match '([\d]+) draws/frame') { $draws += [double]$matches[1] }
  }
  function Med($a) { if ($a.Count -eq 0) { return 0 }; $s = $a | Sort-Object; $s[[int]($s.Count / 2)] }
  $rows += [pscustomobject]@{
    Tag      = $tag
    Frames   = $ms.Count
    MedianMs = [math]::Round((Med $ms), 1)
    BestMs   = if ($ms.Count) { [math]::Round(($ms | Measure-Object -Minimum).Minimum, 1) } else { 0 }
    TexMs    = [math]::Round((Med $tex), 1)
    TexMB    = [math]::Round((Med $texMb), 1)
    Draws    = [math]::Round((Med $draws), 0)
    TexPer1k = if ((Med $draws) -gt 0) { [math]::Round(1000 * (Med $tex) / (Med $draws), 2) } else { 0 }
  }
}
$rows | Format-Table -AutoSize
