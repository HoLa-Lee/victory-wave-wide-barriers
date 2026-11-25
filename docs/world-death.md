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

## How to read the title's crash sites

`tools/disasm_rva.py <rva-hex> [count]` disassembles the cached image at an RVA (mapping it
through the PE section table, starting from the nearest `cc cc` padding) and prints every
RIP-relative reference with the string it points at. It needs `capstone`
(`python -m pip install capstone`).

What it shows around this crash:

```
0x2215ea0  push rsi / sub rsp,0x20 / mov rax,[rcx+0x10]
0x2215ebf  call 0x43a42e0
0x2215ec4  mov  rcx,[rsi+8]
0x2215ec8  call qword ptr [rsi]        <- the crashing work is reached through a function pointer
0x2215eca  ...                          (frame #2: the return address of that call)
```

and frame #1 (`0x2215c35`) sits in a routine that begins `c7 04 25 00 00 00 00 00 00 00 00 cc` —
the same "write to address zero, then `int3`" idiom as the trap itself. So the stack does not pass
through a formatter that names its complaint: the title goes from a function pointer straight into
its fatal path.

`0xd421` is the marker the fatal path stores. Finding the branch that reaches it is a matter of
following the function pointer at `[rsi]` and the two calls the thread entry makes
(`0x22160b0`, `0x2216160`), which is the next disassembly job rather than another run.

## The fatal path formats `ALERT_ERROR_SUPPORT_0x%x`

Following the trap back with `tools/disasm_rva.py`:

```
0x23cf620  sub rsp,0x48 ; call 0x2483ea0
0x23cf629  lea rdx,[rsp+0x28] ; movabs rcx,0x1b5d6844174b453b ; mov r8d,0xc
0x23cf63e  mov [rdx],rcx ; … ; mov byte [rdx+0xc],1
0x23cf651  loop: mov byte [rdx+0xd],[rdx]+0xc ; inc rdx ; dec r8 ; jne     (an obfuscated 13-byte blob)
0x23cf666  call 0x2215950                                                 (decodes / reports it)
0x23cf66b  cmp byte [rsp+0x34],1
0x23cf670  jne 0x23cf683                                                  (not 1 -> the trap)
0x23cf683  mov dword ptr [0],0x4d8bd421
```

and `0x2215950 → 0x2215980` builds its message from a string table at `0x6778eed`, one entry of
which is **`ALERT_ERROR_SUPPORT_0x%x`** (`0x6778ed3`).

So the world does not die of a bad draw: it dies because the title reports an **unsupported
feature alert** (`ALERT_ERROR_SUPPORT_0x…`) and this build's alert path ends in the trap. That
explains the three unrelated switches landing on the same instruction, the empty breadcrumbs,
and the silence of the validation layer — nothing is wrong with the GPU commands.

The next step is the alert's **id**: the code around 0x23cf620 (and the callers of it) determine
which branch of `ALERT_ERROR_SUPPORT` ran, and there are only so many "support" branches a title
has (`ALERT_ERROR_SUPPORT_0x…` with a numeric class). Reading the 13 obfuscated bytes as data —
0x3b 0x45 0x4b 0x17 0x44 0x68 0x5d 0x1b 0x4f 0x66 0x65 0xff 0x01, each plus 0x0c — gives a
candidate id and, with it, the feature the title wants.

## The two failure modes are not the same failure

Counting `0x8007000E` (`E_OUTOFMEMORY`, "not enough memory resources") in every arm:

| arm | `E_OUTOFMEMORY` lines | outcome |
|---|---|---|
| `keys2`, `args`, `argsub`, `around`, `post310` (default switches) | **0** | **device removed** |
| `skipind`, `copy_mode=none` | **3,827–3,843** | **the title's trap** |

So the trap is preceded by thousands of failed 256 KiB upload allocations, and **no arm that
ended in a device removal logged a single one**. The trap is therefore a *second* bug: the
switches that suppress work (`VICTORY_SKIP_EMPTY_INDIRECT`, `VICTORY_COPY_MODE=none`) let
something in this layer grow until the host refuses allocations, the title's render path starts
failing (`host pipeline refused 0x80070057`), and it takes its `ALERT_ERROR_SUPPORT` trap.

That corrects the last section's reading: the trap is not the world's death seen from another
angle — it is what those switches cause. The world's own death remains the **device removal with
zero `E_OUTOFMEMORY`**, an empty DRED report and a silent validation layer, which is why the
"resource running out" hypothesis needed this count before it could be believed.

Two things follow. Whoever pursues the memory angle should first check which arm their numbers
came from — the million small blocks the other session measured may be the same artefact. And
the world's removal still has no explanation that fits: no API error, no page fault reported, no
allocation failure, and a moment that repeats to within sixteen seconds.

## The sweep is not it either, and the removal comes after 4.6 s of an empty queue

`VICTORY_SWEEP=0` (the idle sweep that lets host copies go — the run before a default removal
shows it freeing 449 copies / 121 MB, then 315 / 435 MB) kept everything, and the death did not
move:

```
SWEEP=0: story_at=178 s  removal_at=213 s  trap=0  E_OUTOFMEMORY=0
```

against a default 211–227 s. So the sweep is not freeing something the card still reads.

What a default run logs in the seconds before the removal:

```
the card's clock per frame: nothing of ours queued 4629.7 ms (the card about 18% busy by this count)
ERROR host GPU device removed … of 0 lists
```

**4.6 seconds in which our queue held nothing**, then a removal with nothing in flight — and no
`slow host submission` line anywhere in that run, so it was not one long submission of ours. The
device goes while this layer is idle, which is why every "what was the last command" reading has
been a different answer: there is no last command.

That points at the frame's own CPU side (the title between submissions) or at the driver. The next
probe is what the title thread was doing for those 4.6 s — the frame line already prints the
frame's own time, and `VICTORY_LOG` can raise the title's own logging if it has any.

## It is memory: 18.4 GB of working set in the last thirty seconds

Sampled free RAM and the process's working set every ten seconds through one default run
(`VICTORY_D3D12_DRED` off, everything else default):

```
t=160s free=17.81GB ws= 5.55GB
t=170s free=17.12GB ws= 6.08GB
t=180s free=13.93GB ws= 8.39GB
t=190s free= 7.53GB ws=14.55GB
t=200s free= 4.78GB ws=18.37GB
t=210s EXITED        (host GPU device removed)
```

**Six gigabytes to eighteen in thirty seconds.** The layer's own memory line one second before
the removal says what it is:

```
memory: 18983 MB private (18705 MB of it in memory; the PC has 5023 MB free …)
host copies of title memory: 10 alive 206 MB
staging of textures: 615 alive 285 MB
host textures: 23962 alive 10012 MB, 24871 placed in title memory
made so far: 26167 upload buffers 8972 MB, 11 shared buffers 207 MB, 60 card buffers 430 MB
```

**23,962 host textures holding 10 GB**, plus 26,167 upload buffers made so far (8.97 GB). The
story phase asks for tens of thousands of textures, this layer gives every one a host copy, and
on WARP those copies are system RAM. The device does not fault on a command: it is suspended
because the host runs out of memory (`0x887A0005`, "the GPU device instance has been suspended").

That closes the investigation this document opened: the fixed moment, the empty breadcrumbs, the
silent validation layer and the "no last command" are all the same fact — the allocation spike
comes when the story's assets arrive, and the card dies of the host's memory, not of anything it
was asked to draw.

The change that follows: the idle sweep already exists (`resource::let_go_idle`, every second,
threshold `ram_idle_ms`: 10 s normally, 5 s below 4 GiB, 2 s below 2 GiB) and it cannot keep up —
at 5 GB free it is still using the 10-second window. Dropping the thresholds earlier (or capping
the host copies' bytes outright) is the experiment: the world should then survive past 210 s.

## Evicting sooner does not help — it only moves the memory into staging

`VICTORY_IDLE_MS=1000` (a new switch: the idle window for letting host copies go, instead of the
`ram_idle_ms` thresholds) through the same run:

```
story_at=178 s  removal_at=212 s   (default: 211–227 s)
max working set 15.0 GB (default 18.4), min free RAM 7.2 GB
memory at the removal: 21995 MB private, the PC has 1029 MB free
  staging of textures: 11110 alive 4277 MB      (default: 615 alive 285 MB)
  host textures: 19280 alive 855x MB            (default: 23962 alive 10012 MB)
```

Host copies went down by 2 GB and **staging went up by 4 GB** — the copies are simply uploaded
again — and the process still ends with **1 GB of free RAM** and the same 212 s removal. So the
wall is the host's memory, and eviction alone only changes which allocator holds it.

What that rules out and what it leaves: it is not one bad command, not the sweep, not the idle
policy, not the clamp, not the relay — it is the total footprint of this layer during the story
load. A fix has to **reduce** the bytes (a cap on host copies, sharing between textures that come
from one memory, or not staging what will not be read this frame), not reschedule them.

## The measurement, as a tool

`tools/world_ram.ps1 -Tag mem1 -Seconds 340 [-IdleMs 1000] [-Warp]` runs the route above and
samples free RAM and the process's working set every ten seconds, printing the layer's last
memory line and where the run failed. Every number in this document that mentions gigabytes came
from that loop or from the `memory:` line it prints at the end; anyone re-running the
investigation should start there rather than at the disassembly.

## The ten gigabytes are not waste — they are the story's textures, duplicated by design

The memory line at the removal, read in full:

```
host textures: 23962 alive 10012 MB, 24871 placed in title memory
made so far: 26167 upload buffers 8972 MB, 11 shared buffers 207 MB, 60 card buffers 430 MB
```

**24,871 of the title's textures are *placed* in its own memory** — and this layer gives each of
them a host texture of the same size, because a placed texture's texels live in the title's
address space and the card cannot sample that. So the 10 GB is the story's texture set, copied
once, not a leak: 24k textures of a 208 GB pack arrive in three minutes and each one needs a
GPU-visible twin.

That is why every cheaper idea failed. Sharing between textures cannot help (`sharing one 0` on
the card, and there is nothing to share when each placed texture has its own memory). Eviction
cannot help while the set is being *used* (the `VICTORY_IDLE_MS` run freed 2 GB of copies and
paid 4 GB in re-staged uploads). The layer has no budget and no streaming: it makes a copy when a
texture is first used and keeps it until the texture is released or idle for ten seconds.

So the world needs what a PC port of this title would need anyway: **a budgeted texture cache
with streaming** — a cap on host copies' bytes, least-recently-used eviction under that cap, and a
re-upload path that does not double the cost when it fires (the staging it re-creates is the
4.3 GB the idle experiment measured). That is a piece of work, not a patch, and it is the honest
answer to "why does the world die at 212 seconds".

On the card the same duplicate would land in 16 GB of VRAM — which is the number to watch when
that path is measured next.

## A hard cap on host copies: it sheds what is idle, not what is in use

`VICTORY_HOST_TEXTURE_CAP_MB` (new switch) makes `resource::let_go_idle` let a copy go as soon as
nothing holds it once the alive bytes pass the budget, instead of waiting out the idle window.
With 5,000 MB, same run:

```
story_at=178 s   removal_at=215 s   (default 211–227 s)   max working set 15.6 GB (18.4 before)
memory at the removal: 16303 MB private, 6791 MB free
  staging of textures: 15 alive 6 MB        (default 615 alive 285 MB — the cap does clear these)
  host textures: 16792 alive 7452 MB        (still above the 5 GB budget)
```

Two readings. The cap works on what it can reach — staging went from 285 MB to 6 MB, and the
process's peak fell by 3 GB. And it **cannot** reach the rest: 16,792 copies holding 7.4 GB are
held by lists and slots (`Arc::strong_count == 1 && references == 1` is the only condition under
which a copy may go), so the budget is a floor, not a ceiling, and the removal stays at 215 s.

Together with the earlier arms this settles the shape of the problem: at that moment the world
*needs* on the order of ten gigabytes of texture copies plus nine of upload buffers, and this
machine on WARP cannot give it (16–19 GB private, 1–7 GB free, then `0x887A0005`). The card has
16 GB of VRAM — the one path that might fit — and its menus cannot yet be driven by scripted keys
(see the input section above).
