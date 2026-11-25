# The world dies about a hundred seconds in

Everything this branch knows about it, in one place, as of 2026-11-25 13:30. Every run below is
the same build, the same dump, `diag` profile, a fresh data folder whose only content is an empty
`Z:\settings\settings.xml`.

## The reproduction

```powershell
$dir = "$env:TEMP\vworld"; Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$dir\7952987A\storage\settings" | Out-Null
New-Item -ItemType File -Path "$dir\7952987A\storage\settings\settings.xml" | Out-Null
$env:VICTORY_DATA_DIR = $dir
$env:VICTORY_D3D12_WARP = "1"          # the world is reachable on WARP; the card's menus ignore scripted keys
$env:VICTORY_D3D12_DRED  = "1"
# Up, Enter, Up, Enter, Down, Down, Enter every 14 s from 60 s: the menus, then the story
$seq = @(); for ($t = 60; $t -le 240; $t += 14) {
  $seq += "$t`:Up"; $seq += ("{0}:Enter" -f ($t+0.8)); $seq += ("{0}:Up" -f ($t+1.6))
  $seq += ("{0}:Enter" -f ($t+2.4)); $seq += ("{0}:Down" -f ($t+3.2)); $seq += ("{0}:Down" -f ($t+4.0))
  $seq += ("{0}:Enter" -f ($t+4.8)) }
$env:VICTORY_KEYS = ($seq -join ",")
& .\target\diag\victory.exe run "<dump>\game_scarlett_master.exe" --execute
```

The story's packs (`pack\story000\story000.rpf` and `story000_script.rpf`) open about **16 s**
after the keys start; the device goes **80–320 s after launch**, on WARP, every time it is given
the chance.

## What has been excluded, with the run that excluded it

| candidate | evidence |
|---|---|
| the heap pass | sliced 96 s, whole heap 94 s without a death — other session's arms |
| `VICTORY_RELAY` | `VICTORY_RELAY=0` moves the death line to "a submission of 8 lists", not the moment |
| the texture sweep | `VICTORY_TEXTURE_SWEEP=0` 98 s, no change |
| an API misuse | debug layer installed (`Tools.Graphics.DirectX`), **zero `D3D12 ERROR`**, and the failure text's own `log_messages()` has nothing |
| the empty indirect record | `VICTORY_SKIP_EMPTY_INDIRECT=1` removes the *device removal* (2 arms of 2) and the title then crashes instead — at `+0x23cf683`, writing `0x0`, twice at the same address |
| the arguments being copied too early | `VICTORY_INDIRECT_ARGS_AT_SUBMIT=1` refreshes them from title memory just before the list runs: still dies, still `args [0, 0, 0, 0, 0]` |
| one command | six deaths named six different last commands — indirect mesh with zero arguments (three), a BC1 texture upload, **zero lists** (`0x887A0005`), a direct mesh — and one run died with **no indirect op at all** |

## What does not move

- **The moment**: ~100 s into the world, whenever the run is given long enough.
- **The shape of the work**: mesh passes against a 2560×1440 `f19` (`R32G8X24_TYPELESS`) depth
  target, in every arm that named a command.
- **The silence**: empty DRED breadcrumbs even with DRED forced on, no debug-layer message, and
  `GetDeviceRemovedReason` answering `0x887A0005` ("the GPU device instance has been suspended")
  when it answers at all.

## The hypothesis that fits the most runs

A resource running out rather than a bad call. The other session's memory line one second before
a death reads **986 MB in 991,228 blocks, 153 MB of them in 977,282 blocks under 4 KiB**, and the
allocation that fails at the removal is **4 MB** — a million tiny host resources is what running
out of a per-process resource looks like, and it explains every other observation: the moment is
a hundred seconds in whatever the scene is, the last command differs, and no validation layer has
anything to say.

The change that follows from it is already in their hands: those small uploads should come out of
a few large buffers, so the block count stops tracking the number of small copies. If a run with
that in place reaches the world and stays, this document is the record of what it took.

## Instruments this branch added for it

`VICTORY_PRESENT_TRACE` (present fences, picture digest, both resource pointers, texture and
buffer refresh counters), `VICTORY_PRESENT_FENCE`, `VICTORY_SKIP_EMPTY_INDIRECT`,
`VICTORY_INDIRECT_ARGS_AT_SUBMIT`, `VICTORY_KEY_HOLD`, `VICTORY_PAD_TRACE`, the indirect record's
five argument words with its neighbourhood, and the `d3d12_probe` example. All off by default
except the two pad/present traces' dependencies, and each documented in
`fork-wave-wide-barriers.md` with the run that motivated it.

## How repeatable it is

Eight runs of the recipe above, timed from the first log line:

| run | story packs open | device removed | or |
|---|---|---|---|
| `keys2` | 178 s | 221 s | |
| `args` | 178 s | 215 s | |
| `argsub` | 178 s | 219 s | |
| `around` | 178 s | 227 s | |
| `dbg3` | 178 s | 211 s | |
| `post310` | 178 s | 219 s | |
| `skip2` | 178 s | — | title crash |
| `skipind` | 178 s | — | title crash |

The story opens at **178 s in all eight**, and the device goes **33–49 s later** in every run
that is not given `VICTORY_SKIP_EMPTY_INDIRECT=1` — a spread of 16 s over six runs. A fault that
depends on what a frame contains would not be this regular; one that depends on how much has
accumulated by then would.
