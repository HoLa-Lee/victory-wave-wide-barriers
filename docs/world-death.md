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

## Three different switches, one crash

`VICTORY_COPY_MODE=none` (no per-frame title-memory copies), 330 s, same recipe: story packs open
**earlier** (150 s, the copies are the wait), **no device removal**, and the title takes the same
`0xc0000005` at **`+0x23cf683`, writing `0x0`** that both `VICTORY_SKIP_EMPTY_INDIRECT` arms took.

| arm | story | device | title |
|---|---|---|---|
| default | 178 s | removed 211–227 s | — |
| `SKIP_EMPTY_INDIRECT=1` (×2) | 178 s | none | `+0x23cf683` write `0x0` |
| `COPY_MODE=none` | 150 s | none | `+0x23cf683` write `0x0` |

Three unrelated switches abolish the device removal and land on **the same instruction** in the
title's own image. That is the shape of a title-side null dereference which, on the default path,
the GPU reaches first — the card faults on what the title was about to touch, and the removal is
the symptom rather than the fault.

Which turns the next step around: the address is the thing to look at. `+0x23cf683` in
`victory-image-b99f876b74d4a77f.dll` (the cached image of the title's executable) is a fixed
offset; the crash log already gives the registers (`rax 0x0 rbx 0x0 rcx 0xd0024c348 rdX 0x1 …`),
and a disassembly of the 32 bytes around it would name the field the title expected and did not
get — from an HLE call, most likely.

## What is at `+0x23cf683`: a deliberate trap, not a null field

Mapped the crash offset through the cached image's PE headers and read the bytes
(`victory-image-b99f876b74d4a77f.dll`, `.text`, file offset 0x23cea83):

```
23cf663: ed 89 c2 e8 e5 62 e4 ff 80 7c 24 34 01 75 11 48
23cf673: c7 c0 f4 ff ff ff c6 44 04 41 00 48 ff c0 75 f6
23cf683: c7 04 25 00 00 00 00 21 d4      <- mov dword ptr [0], 0xd421
```

So the instruction the title dies on is **`mov dword ptr ds:[0], 0xd421`** — a store to absolute
address zero with the magic `0xd421`. That is a **deliberate trap**: the title decides something
is unrecoverable and writes a marker where it knows the fault will be taken (the idiom a title
uses where a console would have printed and stopped). It is not a null field being dereferenced.

The stack it came from says the same: `#0 +0x23cf683 → #1 +0x2215c35 → #2 +0x2215eca →
KERNEL32 → ntdll`, i.e. a **worker thread** whose entry point is `+0x2215eca`; the trap was reached
from a call at `+0x23cf655` (`call …` at 0x23cf666 into a helper) inside it. `rax` and `rbx` are
both zero at the trap, which is consistent with "a call returned null and the caller took its
error branch".

Next: disassemble the caller `+0x2215c35` and the thread entry `+0x2215eca` — the branch before
the trap is where the title formats whatever it was unhappy about, and a string reference there
names the missing thing far more cheaply than another GPU-side run.
