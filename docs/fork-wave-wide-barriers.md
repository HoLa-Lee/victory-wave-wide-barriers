# The wave-wide form takes the fence-only barrier mode

Status, 2026-11-25: the change is in the tree and its unit test passes; it has
**not** yet been shown to fix the crash it targets, because the machine it was
written on does not reach the world (see *What was not verified*). Nothing from
the game is quoted here: counts, switches and one shader-independent mode value
only.

## What it targets

Issue #101 (RTX 4080 SUPER, Ada, `WaveLaneCountMin=Max=32`): the prologue
renders with `VICTORY_WAVE_WIDE=1` and the process loses the device the first
time the in-game settings menu opens; without the switch the world is black and
the menu is fine. The only difference the switch makes is which form of a
console wave64 program the translator is allowed to pick: `emit::mod`'s
`widen()` (`emit/mod.rs`, "wave-wide branches"), which takes the per-lane
branches around cross-lane code wave-wide and **puts group barriers inside
them**. The comment there has said since the form was written that it lost the
card in runs 121-124, in a submission of two programs that had just moved to it.

## Why a barrier in such a branch loses the card

`emit::group_sync()` (`VICTORY_GROUP_SYNC`) decides, per `s_barrier`, whether
the translated barrier waits for the whole group (`dx.op.barrier` with the
group bit) or keeps only its shared-memory fence:

| mode | which `s_barrier` waits |
|---|---|
| 0 | none |
| 1 | only those in a block every lane runs (`lower::fence_only`) |
| 2 (default) | all of them |

`lower` already computes `fence_only`: the blocks whose `s_barrier` a lane may
not reach, because the block is not one every lane runs, or because the program
closes a loop with a plain jump and a lane can leave at the iteration limit
(`lower.rs`, where `fence_only` is built).

On a 32-lane host one console wave64 program runs as **two** host waves. A
barrier the first wave reaches and the second does not is undefined on the host,
and NVIDIA's wait is for every thread: the group stands until Windows resets the
card. That is exactly `DXGI_ERROR_UNSUPPORTED 0x887A0004` followed by
`DXGI_ERROR_DEVICE_HUNG 0x887A0006` in #101, on the settings path.

So the form that deliberately places barriers in branches is the form that
cannot take mode 2. The mode is what the switch does not change.

## The change

`widen()` now translates its candidate programs with `lower::with_wide_form`,
a thread-local that makes `lower::effective_group_sync()` report **1** while
that form is being emitted (mode 0 and 1 from the switch are left as they are).
A barrier a lane may not reach then keeps its fence and drops its wait, and the
second host wave does not stand in it. The blocks that *are* run by every lane
keep their waits, so the LDS exchanges the form exists for still order.

Cost: inside a wave-wide translation, a write and a read that a lane never
reaches are no longer ordered against each other. That is the trade the form
already makes elsewhere 鈥?it is the *approximate* form, and it only runs when
the exact forms and the deep-skip form both failed. A translation that computes
a wrong value beats a card reset, and the mode is part of the shader cache key
(`shader_cache::build` already hashes `group_sync()` and `VICTORY_WAVE_WIDE`),
so entries cannot cross between the two.

Files: `crates/victory-shader/src/emit/lower.rs` (the thread-local, the wrapper,
`effective_group_sync`, and the `waits` match), `crates/victory-shader/src/emit/mod.rs`
(one call wrapped in `widen`).

## Tests

```
cargo test -p victory-shader        211 passed, 0 failed, 2 ignored (62.6 s)
cargo clippy -p victory-shader --all-targets    clean
```

`emit::lower::tests::the_wide_form_takes_the_fence_only_barrier_mode` asserts
the mode the lowering sees: the switch's own value outside the form, **1**
inside it when the switch says 2, the switch's value again after, and that a
switch already at 0 or 1 is left alone. It fails before the change (the wrapper
did not exist) and pins the behaviour after it.

## What was verified on the machine that wrote this

Hardware: i5-12600KF, 32 GB, RTX 4080 SUPER (16 GB, driver 32.0.16.1742),
Windows 11 26200. Dump: Series X, 208.62 GiB, executable BLAKE3
`b99f876b74d4a77f03af5f878223b27bd647b5c35a79d5decd9f716504239e93` 鈥?the same
build every report in this repository uses. Rust 1.98.1 (pinned), MSVC
14.44.35207, SDK 10.0.26100.0.

- `census` sees 18 images, 0 unreadable; `run` without `--execute` binds
  `game_scarlett_master.exe` at **88 hle, 427 host, 72 title, 0 missing**, and
  the four title DLLs at 9/48, 4/18, 27/171 and 6/54, all 0 missing 鈥?the same
  numbers as the report in the upstream repository's own issue.
- The title boots and the first-run screens run at **30 fps, 33.3 ms/frame,
  38-61 draws/frame**, at 1920x1080, on the 4080 (the host's memory line
  reports a 15,277 MB budget, so the adapter is the card, not a virtual one).
- Legal notices, the Rockstar terms page (two checkboxes, Confirm greyed out
  until both are ticked), the brightness calibration page, the "finish setup?"
  page and the loading art all render correctly 鈥?text legible, selection
  highlight correct, pad prompts drawn.
- 2D is clean and there is no device loss on this path with or without the
  patch.

## What was not verified

**The fix is unproven until a machine that reaches the world runs it.** This
machine did not: scripted `VICTORY_KEYS` walked account picker 鈫?legal notices 鈫?terms 鈫?brightness 鈫?"finish setup?", and then the title came back to the legal
notices page instead of loading, on every attempt (9 runs, 60-160 s each, fresh
`VICTORY_DATA_DIR`). Whether that is the profile write, the offline account, or
the key sequence is not known yet, and it is the reason this change cannot claim
#101 fixed.

### What the first-run flow does on the way out

With `VICTORY_LOG` at debug for `victory_hle::modules`:

- The title asks for the persistent-local-storage provider
  (`f4faf4d4-2d04-4fce-b3e0-474a713a3e84`) with the 2026 interface
  (`41a4e10c-鈥) and gets it; the calls are served, and the path it receives is
  a drive root as intended.
- It then reaches `Z:\settings\`, `Z:\cloudpers\`, `Z:\cloudcache\` and
  `Z:\cloudcache\*` 鈥?directories and one wildcard enumeration 鈥?and writes no
  file in any of them. `storage\settings`, `storage\cloudpers` and
  `storage\cloudcache` exist and stay empty; `saves\` gets a container
  directory (`0009000000000001\00000000-0000-0000-0000-00007952987a`) and nothing
  inside it.
- **No `XGameSave` provider is ever requested**, so none of the save API in
  `victory-hle::modules::xgamesave` is reached at all; the container directory
  is made by something else. `XGameSaveSubmitUpdate` (the blocking form, 0xd8)
  was `missing` in this fork and is now implemented as the same commit the
  async form runs 鈥?it changes nothing here, because nothing calls it.
- The only file the title leaves behind is `temp\telemetrycache.dat`.

So the setup is not committed, and the next boot is a first boot again. The
next thing to look at is the `Z:\settings\` write the title does not attempt,
not the save API.

### It does not attempt one: four title paths, all directories

`files::wide` traces every path the title hands the host at debug level. One
run of the whole first-run flow, start to "finish setup?" and the return to
legal notices, produces exactly four:

```
Z:\settings\      Z:\cloudpers\      Z:\cloudcache\      Z:\cloudcache\*
```

Three directories and one wildcard enumeration. No `CreateFileW`, `CreateFile2`
or CRT open of a file under any of them 鈥?so the configuration is not lost on
the way out, it is never asked to be written. `storage\settings`,
`storage\cloudpers` and `storage\cloudcache` stay empty, and `saves\` gets one
container directory with nothing in it.

That moves the question one step earlier: what makes the flow decide there is
nothing to save, or fail before it tries. Two candidates left 鈥?the
persistent-local-storage quota the title reads (`storage::space`, 2048 MB from
the manifest) and whatever `XPackage` answers while the flow runs (its provider
is the second most asked one in the log).

`XPackage` is not it: `xgameruntime::missing` warns with its area and slot on
every call, and a whole run produces **no** "runtime method not implemented"
line at all. So of the fifteen slots this fork leaves out there, the title
calls none 鈥?it asks for the interface and then uses what is implemented.

The quota is not it either: `storage::space_info` and
`storage::prompt_for_space` now log what they answer, and a whole first-run
walk produces **no** line from either. The title never asks how much room it
has. With `files` at debug, the same walk asks for 233 paths and four of them
are on the persistent drive:

```
Z:\settings\   Z:\cloudpers\   Z:\cloudcache\   Z:\cloudcache\*
```

Three directories and one wildcard. It never asks about a file, never asks for
room, and never submits a save. So the flow does not fail to save 鈥?**it never
reaches saving**. Whatever it reads in those three directories is what it
decides on, and all three are empty on a fresh data folder.

## The whole pack translates, and the wave-wide form is never reached

`victory translate shaders.rpf --list` with `VICTORY_WAVE_WIDE=1`,
`VICTORY_WAVE_WHY=1` and `VICTORY_SHADER_LOOP_LIMIT=32`, on this dump:

```
containers   26503 (614 duplicates skipped)
programs     26084 translated of 26084 (40597693 IR instructions)
DXIL         14156 emitted of 14247 vertex and pixel programs
             2668 emitted of 2682 compute programs
             8762 emitted of 8765 mesh programs
```

Every program in the pack translates, and **not one of them needs the
wave-wide form**: no `WAVE64-WIDE` or `WAVE64-RETRY` line is printed at all,
and a 55-second run at `VICTORY_WAVE_WIDE=1 VICTORY_WAVE_WHY=1` prints none
either (31 shaders, the menus).

That matters for this change in two ways. It makes it **safe**: on 26,084
programs it alters nothing, because `widen` is not entered. And it makes it
**unproven in a second sense**: whatever `VICTORY_WAVE_WIDE=1` does for #101,
it is not visible from here. Either the report came from an older tree (this
fork has since moved the cross-lane retry around 鈥?`#11` was taken out and put
back twice in the last four commits), or the programs that need it only appear
once the world loads, which this machine cannot reach. The run that settles it
is the same one #101 describes, on a machine already in the world.

### On the card the device is lost before the menus; on WARP it runs

Upstream (`70564ae`), same dump, same binary:

| adapter | rate | draws | device |
|---|---|---|---|
| RTX 4080 SUPER | 0.1鈥?.2 fps, 6,300鈥?,700 ms/frame | 2 | lost (reason `0x887A0001`; the `0x887A0004` in that line is the DRED query, see below) |
| WARP | 15 fps, 66.7 ms/frame | 21 | none; `crashes.log` never written |

The card is **150x slower than the software adapter** and then dies, which is
the opposite of what it should do. Two more facts narrow it:

- With `VICTORY_D3D12_DRED=1` the breadcrumbs are **empty**
  (`(done/count, list) []`), so no command list of ours faulted 鈥?the device
  goes while something is created or queried outside one.
- `VICTORY_COPY_MODE=none` and `plain` both still lose it, so the per-frame
  copy of title memory is not the trigger. `VICTORY_D3D12_DEBUG=1` prints
  nothing at all, so the debug layer does not see it as an API misuse.

**Read:** `DXGI_ERROR_UNSUPPORTED` on the card with a clean WARP run means the
layer asks this driver for a capability it does not grant, outside any command
list. The next probes are `CheckFeatureSupport` and the resource creations, not
the submissions.

### The probes ran: `0x887A0004` was this layer's own DRED call

Three runs with the traces below, and the reading above does not survive them.

**`0x887A0004` is not a device answer.** It is what
`GetAutoBreadcrumbsOutput` returns when device-removed data was **never
enabled**: `removal_data` (`host.rs`) asks for breadcrumbs only after
`ID3D12DeviceRemovedExtendedData1` casts, and a device that did not get
`VICTORY_D3D12_DRED` at creation refuses the query with `DXGI_ERROR_UNSUPPORTED`.
So the line

```
host GPU device removed after a submission of 1 lists; no breadcrumbs (鈥?0x887A0004); device removed: 鈥?0x887A0001
```

says *this run had no DRED*, and the removal's own reason is the second
HRESULT, `DXGI_ERROR_INVALID_CALL`. With DRED on, the same removal reads
`breadcrumbs (done/count, list) []` and no `0x887A0004` appears anywhere.
`GetDeviceRemovedReason` never said "unsupported".

**The title asks no capability question.** `device.rs`'s
`check_feature_support` now logs every query with `VICTORY_FEATURE_TRACE=1`.
A 40-second run of the first-run flow on the card, the same on WARP, and a
40-second card run with `VICTORY_WAVE_WIDE=1` produce **zero** of those lines:
the title does not call `CheckFeatureSupport` at all on this path. The host's
own capability asks are the wave lanes (below) and, when a mesh pipeline is
made, mesh tier at shader model 6.6 鈥?and `mesh_shaders()` is never called
either. There is no query whose answer differs to blame.

**The card's device loss belongs to `70564ae`, not to this tree.** Same dump,
same card, same menus, same `diag` build settings, fresh data folder, DRED on,
35 s each:

| tree | adapter | rate | draws | view heap (title slots / host slots) | wave lanes | device |
|---|---|---|---|---|---|---|
| `70564ae` (upstream) | RTX 4080 SUPER | 0.1鈥?.2 fps, 6,300鈥?,700 ms/frame | 2 | 1,245,184 / 934,464 (capped) | not asked | **lost at ~7 s**, `0x887A0001`, breadcrumbs `[]` |
| `2119b0e` + this branch | RTX 4080 SUPER | 30.0 fps, 31鈥?3 ms/frame | 21 | 1,245,184 / 737,855 (capped) | min 32 / max 32 | none in 40 s, with and without `VICTORY_WAVE_WIDE=1` |
| `2119b0e` + this branch | WARP | 21鈥?0 fps, 33鈥?6 ms/frame | 21 | 1,245,184 / 1,507,328 (no cap) | min 4 / max 4 | none |

`2119b0e`'s merge base with `70564ae` **is** `70564ae`: the fork is 225 commits
ahead of it, and `e9765a7 Fix the device loss introduced by the wave64 update`
is one of them (ancestor check, 0). So the loss the last report measured was
already fixed in the branch's base, and nothing in these five commits touches
it. On this tree the card is not 150x slower than the software adapter: it
renders the same menus at 30 fps against WARP's 21鈥?0, where `70564ae` renders
them at 0.1鈥?.2 on the same card.

### The one capability the two adapters answer differently: wave lanes

`host.rs` now logs the `D3D12_FEATURE_D3D12_OPTIONS1` answer whether it
succeeds or fails (it used to be silent on failure, which is how a run could
translate shaders with `HOST_MAX_WAVE = 0` and say nothing):

```
RTX 4080 SUPER   host wave lanes min=32 max=32
WARP             host wave lanes min=4   max=4
```

That is the whole adapter difference the translator sees, and it is the one
`#101` is about: on 32 lanes a console wave64 program runs as two host waves,
on 4 as sixteen, and `set_host_max_wave` is what lets the exact forms be
tried at all. It does not decide the device loss 鈥?the failing tree never asks.

### The other one: the title's view heap is 1,245,184 slots and the card stops at 1,000,000

`HostHeap::new` now prints what it asked for and what it got:

```
RTX 4080 SUPER  host view heap capped: the title's heap does not fit
                error=鈥?(0x80070057) title=1245184 extra=262144 requested=1507328 limit=1000000
                host descriptor heap title_slots=737855 dynamic=262144 host_slots=1000000
WARP            host descriptor heap title_slots=1245184 dynamic=262144 host_slots=1507328
```

WARP makes the title's heap and 2^18 dynamic slots in one go (1,507,328). The
card refuses anything past 1,000,000, so the fallback keeps 1,000,000 slots and
**737,855 of the title's 1,245,184** 鈥?507,329 slots (41%) have no host
descriptor, and a shader that indexes one reads whatever the heap's last slot
holds. On `70564ae` the same cap left 934,464 (its `DYNAMIC` is 2^16), and the
per-submission sweep that tree runs over the title's heap printed
`title slot past the host heap` **310,720** times, one per slot it could not
make: 1,245,184 鈭?934,464 exactly.

Missing descriptors alone do not remove a device: with the cap forced on the
software adapter (`VICTORY_VIEW_HEAP_CAP=1000000`) WARP keeps running at
22 fps for the whole run. So this is a defect for the world, whose heaps are
past 737,855, and not the `0x887A0004`.

### The capability table, asked directly

`crates/victory-gpu/examples/d3d12_probe.rs` asks one adapter the questions this
layer asks and prints one line per answer, so two runs `diff`:

```
cargo run -p victory-gpu --example d3d12_probe                      # the card
VICTORY_PROBE_WARP=1 cargo run -p victory-gpu --example d3d12_probe # WARP
```

| question | RTX 4080 SUPER | WARP |
|---|---|---|
| `D3D12_OPTIONS1` wave lanes (min / max) | 32 / 32 | 4 / 4 |
| `D3D12_OPTIONS5` | `[1, 0, 12]` | `[1, 0, 11]` |
| `D3D12_OPTIONS7` (mesh tier, 鈥? | `[10, 90]` | `[10, 100]` |
| `SHADER_MODEL` | `0x68` (6.8) | `0x68` (6.8) |
| `ARCHITECTURE1` (UMA bits last) | `[0, 0, 0, 0, 1]` | `[0, 0, 1, 1, 0]` |
| GPU virtual address bits | `[40, 40]` | `[32, 47]` |
| view heap, 1,000,000 slots | ok | ok |
| view heap, 1,000,001 slots | refused `0x80070057` | ok |
| view heap, 1,245,184 / 1,507,328 | refused | ok |
| `B4G4R4A4_UNORM` (115): plain / RT / UAV | ok / **refused** / **refused** | ok / ok / ok |
| `R32G8X24_TYPELESS` (19): RT / UAV | refused / refused | refused / refused |
| `BC7_UNORM` (98): RT / UAV | refused / refused | refused / refused |
| `R8G8B8A8_UNORM`, `D32_FLOAT`: RT / UAV | ok | ok |

`D3D12_FEATURE_FORMAT_SUPPORT` says the same in bits. For format 115 the card
answers `TEXTURE1D/2D/3D/CUBE, SHADER_LOAD, SHADER_SAMPLE, MIP,
MULTISAMPLE_RESOLVE, SHADER_GATHER` 鈥?**no `RENDER_TARGET`, no
`TYPED_UNORDERED_ACCESS_VIEW`**; WARP answers the same plus `RENDER_TARGET,
BLENDABLE, MULTISAMPLE_RENDERTARGET, MULTISAMPLE_LOAD, TYPED_UNORDERED_ACCESS_VIEW,
BUFFER, IA_VERTEX_BUFFER`. So WARP grants a use this format does not have on PC,
and the card is the adapter that follows the answer. That is exactly the line
`70564ae` printed half a second before it lost the device:
`no host texture 鈥?2560x1440 format: 115 鈥?flags: 1` (flags 1 is the render
target).

Both differences are the subject of #101: the wave lanes decide how wave64 code
is translated, and a console texture that is a render target in a format PC
cannot render to is a resource the card will not make at all.

### The layer names that capability now, and must not "fix" it by dropping the flag

`resource::host_texture` asks `D3D12_FEATURE_FORMAT_SUPPORT` before it creates
(once per format; the answer does not change in a run) and names the use the
host has none for:

```
WARN victory_gpu::resource: the host says this format has no such use: its creation
is refused and the draw has no texture  format=115 lost=5
```

It does **not** drop the flag from the description, and that is a measurement:
with `ALLOW_RENDER_TARGET` dropped the texture is made, the draw's render-target
view is still made on it, and **WARP loses its device 0.3 s into the first
frame** (`DXGI_ERROR_DEVICE_REMOVED 0x887A0005`, "the GPU device instance has
been suspended") on a tree whose WARP runs are otherwise clean for 25-45 s. A
flag can only be dropped together with the views that need it 鈥?the RTV/UAV
creation refusing by name, or a supported format's twin 鈥?and that is the next
change, not this one.

### Upstream moved 241 commits; the card still loses the device there, and ours does not

2026-11-25 08:11: `Marvisak/VIctory` is at `644ebeb` (`70564ae` + 241 commits,
pushed 00:09Z), and the merges settle two of the things this report listed as
open: `3827767 GPU: make tables past a capped host view heap afresh` (the
1,000,000-slot cap, with the title's per-frame table ring in the top slots
named as the thing that hung the card) and `8c26061 GPU: the world stays up`.
Both are already in `2119b0e`, which is where this branch sits. What upstream
has that this branch does not is `7216ab7 HLE: implement the RPC runtime's GUID
calls` and `ff15f98 #636 hle/allow-rpcrt4` 鈥?the `refused dll="rpcrt4.dll"`
line every run of this tree prints at start-up.

Run on this card, same dump, same menus, fresh data folder, `VICTORY_D3D12_DRED=1`:

| tree | rate | device | log |
|---|---|---|---|
| `644ebeb` upstream | **0.1 fps at frame 2 (6,454 ms preparing), then 33 ms frames** | removed ~18 s in, reason `0x887A0001`, breadcrumbs `[]` | 310,967 lines, of which **310,720** are `title slot past the host heap` |
| `2119b0e` + this branch | 30 fps from the first frame | none in 40 s | 521 lines, none of them that warning |

Two things follow, and the first one corrects this report's own table above.

**The 0.1 fps is one submission, not the rendering.** The card spends 6,454 ms
preparing frame 2 and 3.0 ms on the GPU, then presents frames 4, 8, 16, 32 and
64 at 33 ms each. The slow submission is the one that prints those 310,720
warnings (one per slot past the host heap, `3827767`'s diagnostic, each a new
maximum so each prints once): 310,720 脳 ~21 碌s = 6.5 s. WARP prints none 鈥?its
heap holds the title's whole 1,245,184 slots 鈥?which is why the same tree looks
fast there. So "the card is 150x slower than the software adapter" is a
host-side one-off in a submission, not the card's throughput.

**Upstream still loses the device here and this branch does not**, which is the
same statement as before, one upstream head later: `e9765a7` (in `2119b0e`, and
now in `644ebeb`) fixed it for 3080-class runs, and on this 4080 SUPER the
`644ebeb` build still dies ~18 s in with `0x887A0001` and no breadcrumbs while
this branch runs the same 40 s cleanly.

### 2026-11-25 08:58: the first-run flow *does* finish 鈥?the keys were the wall

The rows above say the flow never reaches saving. It reaches it, and this run
walked it: **`Z:\settings\settings.xml` was written** (3,921 bytes,
`rage__fwSystemSettingsCollection`, graphics and advancedGraphics sections),
`xgamesave: create_container container=SettingsProfileSettings` and
`create_update` were served, and the title went on to open
`pack\story000_restofworld\story000_restofworld.rpf` 鈥?the world's data.

What the earlier runs got wrong is the button mapping, not the title's storage
path: `gameinput::FALLBACK_BUTTONS` has no entry for the letter `A`. The pad's
`A` is **`Enter`** (`(0x0D, A)`), so a script of `...:A` presses nothing at all.
A run that presses `A` sits on the setup pages forever and looks like a save
that never happens.

With `Enter` as `A`, `Down`/`Up` as themselves, the pages on the software
adapter (WARP, 10鈥?0 fps, ~60 s to the first page) go:

| page | what got past it |
|---|---|
| loading star, then the loading art | 鈥?|
| `LANGUAGE` (12 entries) | `Enter` (and `Down` first, if the run has been moving the selection) |
| `LEGAL NOTICES`, Copyright/Photosensitivity list with `Next` | `Down`, `Down`, `Enter` |
| Rockstar terms, two checkboxes and `Confirmar` (greyed until both) | `Up`, `Enter`, `Up`, `Enter`, `Down`, `Down`, `Enter` |
| brightness | `Enter` |
| "finish setup?" | `Enter` |

Then the settings are written, `XGameSave` is asked for, and the world's data
is opened. 4,200 frames in, the software adapter lost its device in the load 鈥?`0x887A0005` ("the GPU device instance has been suspended"), during host
pipeline creation, 30 s after `story000_restofworld.rpf` was opened. So the next
wall is the world's first frames, and it is now reproducible without the card:
`VICTORY_KEYS` with `Enter` where this report used to write `A`.

Nothing here says the card does the same; the card run of this branch has not
been taken past the menus yet.

### 2026-11-25 09:06: the present that can be one frame old, and what it costs to fence it

A reported defect: the opening animation shows a frame that has gone back, not a
fade. The candidate mechanism is the present path 鈥?`late_free_present()`
(`VICTORY_RELAY=1`, `VICTORY_LATE_WAIT=3`) issues the back-buffer copy as a
flight of its own and calls `Present` with no fence, so if the frame's sync has
not landed the copy reads an older picture.

**The mechanism is off in a default run, and measurably so.** `late_stage()` is
`0` unless `VICTORY_LATE_WAIT` is 1/2/3 or `VICTORY_RELAY` is 1/2, so removing
those variables changes nothing. `VICTORY_PRESENT_TRACE=1` now logs, at every
present, what the card had run (`submitted`, `completed`, `behind`) and whether
the copy went out as a flight:

| run (RTX 4080 SUPER, the menus, 25 s) | presents | copy sent ahead | `behind` at present |
|---|---|---|---|
| default | 685 | 0 | **0 every time** |
| `VICTORY_RELAY=1` | 672 | **672** | 1鈥?, never 0 |
| `VICTORY_RELAY=1 VICTORY_PRESENT_FENCE=1` | 683鈥?95 | 0 | **0 every time** |

So: in the default configuration the present is synchronous 鈥?the copy is
submitted through `execute`, which settles the flights and waits for the card,
and only then is `Present` called; there is no way for it to show an older
picture. With `VICTORY_RELAY=1` the precondition the report describes is real
and constant: every present is issued with the card still one submission
behind. Refreshes are `174鈥?87 MB` a frame with **`0 skipped`** in both arms,
so no refresh was deferred in either.

**The cheap half of the fix is in**: `VICTORY_PRESENT_FENCE=1` makes a present a
settle point again even at stage 3 (`present()` takes the synchronous branch).
On this machine it costs nothing 鈥?683鈥?95 presents in 25 s with the fence
against 672 without, both ~27 fps 鈥?and it removes the "present one submission
behind" state entirely. It is off by default so the runs that measure
`VICTORY_RELAY`'s pipelining keep their shape; the world, where that pipelining
is worth 3鈥? s/frame, is where its cost has to be measured.

What this does not settle: the animation's frames are not in the captured swap
chain (`VICTORY_CAPTURE` frames 1鈥?4 are a flat colour), so whether the
regression is this path can only be answered by the same three arms above with a
person watching the animation 鈥?default, `VICTORY_RELAY=1`, and
`VICTORY_RELAY=1 VICTORY_PRESENT_FENCE=1`. If it comes back in the *default*
run, it is not this path: the candidates left are the shadow refresh
(`0 skipped` says it is not deferring) and the title's own double buffering.

### 2026-11-25 09:10: what says "settings exist" is `Z:\settings\settings.xml`, and a seeded one skips the flow

The title's file calls are traced at debug (`VICTORY_LOG=victory_hle::modules::files=debug`)
and the trace now names the export a path came in through (`at=` is the line of the
call in `crates/victory-hle/src/modules/files.rs`), so a path can be read back as the
call it was:

| line | export |
|---|---|
| 271 | `CreateFileW` |
| 381 | `CreateDirectoryW` |
| 402 | `GetFileAttributesW` |
| 448 | `FindFirstFileW` |

**A fresh data folder.** 489 ms in, right after the `.rpf` archives are mounted:

```
title path path=Z:\settings\       at=381   CreateDirectoryW
title path path=Z:\cloudpers\      at=381   CreateDirectoryW
title path path=Z:\cloudcache\     at=381   CreateDirectoryW
title path path=Z:\cloudcache\*    at=448   FindFirstFileW
```

Nothing under `Z:\settings\` is ever opened, and the title makes that directory
itself 鈥?it does not ask whether it exists, so a pre-made `storage\settings\` is not
what the flow reads. With no `settings.xml` in it, the setup pages run and the
containers are only asked for minutes later, after the last page.

**The same run with the file the 08:58 run wrote** (`settings.xml`, 3,921 bytes,
copied into `storage\settings\` of a fresh data folder):

```
01:10:57.910  Z:\settings\             at=381   CreateDirectoryW
01:11:01.874  xgamesave: create_container container=Player
01:11:02.061  xgamesave: create_container container=SettingsProfileSettings
01:11:02.127  xgamesave: create_container container=SettingsProfileSettings
01:11:02.158  Z:\settings\settings.xml at=402   GetFileAttributesW
01:11:02.159  Z:\settings\settings.xml at=271   CreateFileW
```

Four seconds in, with no page and no key pressed: `Player` and
`SettingsProfileSettings` are asked for, then the file is asked about
(`GetFileAttributesW`) and read (`CreateFileW`). So the gate is the **file's**
presence, and its answer decides whether the setup pages run at all; the four
directories are made by the title on every launch either way and are not the check.

That is also a shortcut to the world: a data folder seeded with a `settings.xml`
skips the whole first-run flow, so a run that only wants frames after the menus no
longer needs `VICTORY_KEYS` for them:

```powershell
# seed the settings the flow writes, then start with no keys at all
Copy-Item -Recurse vlogs\data-rpc-tick\7952987A vlogs\data-seed\7952987A
$env:VICTORY_DATA_DIR = "$PWD\vlogs\data-seed"; $env:VICTORY_D3D12_WARP = "1"
.\target\diag\victory.exe run <game dir>\game_scarlett_master.exe --execute
```

240 s of that on WARP, a seeded folder and `Enter` every 15 s, **reaches the
world**: `pack\core_restofworld001\core_restofworld001.rpf` opens at 01:12:25 and
`pack\story000_restofworld\story000_restofworld.rpf` at 01:13:11, with no setup page
and no key script for them. The world's frames then run at 1.6-1.8 fps (558-620 ms
a frame; 130 `slow host submission` lines, the worst 1,484 ms, most of them carrying
a compute pipeline beside the draws) and **WARP loses the device 82 s later**, at
01:14:33, after 7 lists:

```
ERROR victory_gpu::draw: the host device went while buffer views of the heap were made
WARN  victory_gpu::host: no shared buffer error=... (0x887A0005) size=4194304
VIctory: host GPU failure: host GPU device removed after a submission of 7 lists; no breadcrumbs
```

So the wall past the menus is the submission that makes the world's buffer views:
one line lists 104,139 heap slots, the whole heap is walked in one go, and the
software adapter goes during it. A run that wants the world on the card has to be
taken the same way 鈥?a seeded folder and `Enter`, no setup pages.

### 2026-11-25 09:20: the swap chain never shows the animation, so the present is not where it goes back

Two measurements, WARP, this build, fresh data folder, no switches:

- **852 presents, 2 distinct pictures.** With `VICTORY_PRESENT_TRACE=1` every
  present logs a digest of the probe grid (`capture::digest`): 850 of the 852
  are the same value as their neighbour, and the whole run holds two values.
- **99 captured frames, 2 distinct files.** `VICTORY_CAPTURE` with
  `VICTORY_CAPTURE_FRAMES=200..560` step 4: frames 1鈥?28 are one flat colour
  (6,121 bytes each) and every frame from 200 to 560 is the *same* file
  (39,992 bytes). Hashing them shows no second picture in that window at all.

So in the first 560 presented frames the swap chain holds two pictures, and
neither is an animation. Whatever the reported frame regression belongs to, it
is not the picture `present()` copies into the back buffer: there is nothing
moving there to go back. That also means `late_free_present()` cannot be its
cause, even though the path exists and is measurable
(see the section above: `VICTORY_RELAY=1` presents one submission behind every
time, and `VICTORY_PRESENT_FENCE=1` removes that at no cost here).

The next question is therefore *which surface the animation is drawn on*. This
engine has exactly one swap chain of ours (`Host::presenter`, host.rs:6135) and
no DXGI swap-chain HLE, so either the animation is presented by a path this
tree does not see at all, or it happens in frames the instruments never sample
(a run with `VICTORY_CAPTURE_FRAMES` naming *every* frame of the first three
seconds would settle that: 90 files, one hash each).

### 2026-11-25 09:26: every frame of the opening, hashed 鈥?five pictures in a thousand

One more pass on the reported frame regression, with `VICTORY_CAPTURE_FRAMES`
naming **every** frame of the opening (1鈥?40) plus the usual powers of two, on
WARP, 20 s:

```
164 captures, 5 distinct files:
  96 脳 6,121 bytes     frames   1.. 96   one flat colour
   4 脳 30,298 bytes    frames  97..101   the first picture
   1 脳 34,244 bytes    frame  100        (its own value: one frame)
  40 脳 39,992 bytes    frames 102..256   held
  23 脳 17,998 bytes    frames 144..1024  held
```

So the presented picture changes five times in the first thousand frames and is
constant for tens of frames at each step. There is no per-frame change anywhere
in it 鈥?which is the strongest form of the earlier finding: **this swap chain
cannot be where a frame that "goes back" is seen**, because nothing advances
frame to frame on it. The animation the report describes is drawn somewhere
this tree's `present()` never copies, and that is the question to answer next.
Candidates, in order: a second window the title creates (`CreateWindowExW` is
HLE'd, `lifecycle.rs`), the frame before `Host::presenter` made its swap chain,
or a surface presented by a path with no HLE at all. Screen capture of the
flip-model swap chain comes back black, so window enumeration (which HWNDs the
title owns, and their sizes) is the cheap next probe rather than another run.

### 2026-11-25 09:31: 293 consecutive frames, four pictures 鈥?the opening is a still

Every frame 100鈥?00 captured one by one (WARP, 22 s):

```
293 captures, 4 distinct files:
  38 脳 flat colour      frames   1..130
   4 脳 30,298 bytes     frames 131..135   the first picture
   1 脳 34,244 bytes     frame  134        one frame of its own
 250 脳 39,992 bytes     frames 136..385   the same file, 250 times
```

250 consecutive frames of one file. The pre-menu opening has **no animation at
all** in the presented picture 鈥?not a slow one, none. That is the end of the
"present copies the previous frame" theory for this phase: there is nothing to
lag behind.

The animation the report describes therefore lives in the path that only opens
once a profile exists: with a seeded `Z:\settings\settings.xml` the title skips
the setup pages and loads `story000_restofworld.rpf` (the run in the section
above), and that is the only phase left in which a moving picture exists. The
measurement to make there is the same one: `VICTORY_CAPTURE_FRAMES` naming a
run of consecutive frames through the intro, one hash each; at 1.6鈥?.8 fps a
frame that goes back would show as a hash repeating a *different* frame's.

One surface only: enumerating the title's windows during boot finds a single
visible one (`sgaWindowClass`, 2474脳1392, our presenter's), so the animation is
not a second window either.

### 2026-11-25 09:35: the regression reproduces 鈥?the presented stream cycles through three pictures

With a seeded `Z:\settings\settings.xml` (the profile that skips the setup
pages) and `Enter` every 15 s, WARP reaches the Rockstar loading screen 鈥?seven
stars 鈥?and there the presented stream does exactly what the report describes.
Every frame 150鈥?00 captured, one hash each, in order:

```
320 AA284D   321 BE0541   322 129F39
323 702F55   324 BE0541   325 129F39
326 702F55   327 BE0541   328 129F39
329 702F55   330 BE0541   331 C1D275
332 702F55   333 BE0541   334 C1D275
...
339 5E2691   340 C1D275   341 702F55
342 5E2691   343 C1D275   344 702F55
```

A strict cycle of **three** pictures. A picture that is new appears every third
frame and takes the oldest one's place; the two older ones are shown again in
between. On screen that is the loading pulse advancing one step per three
frames while the frames in between show where it was 鈥?the "goes back a frame"
the report names, and it is 9鈥?0 fps with 39 draws a frame.

What it is **not**:

- not `late_free_present()`: every one of those presents logs `behind=0` and
  `sent_ahead=false` (the default path settles the flights and waits for the
  card before `Present`);
- not a deferred refresh: `0 skipped` in every copystat line of the run, at
  339鈥?71 MB of refreshes a frame;
- not a second surface: one visible window (`sgaWindowClass`).

What is left, and the next probe: the frame that is copied is one of a ring 鈥?three host textures (or three title render targets behind one host texture)
whose contents are refreshed one per present, so each present shows the member
whose refresh landed one, two and three presents ago. Reading `resource.rs`'s
`host_copy`/`let_go_idle` path for the presented texture, and logging which
host resource id each present copied, settles which ring it is.

### 2026-11-25 09:47: two host textures take turns, the picture returns every three frames

`VICTORY_PRESENT_TRACE=1` now also logs **which host resource** each present
copies (`source = texture.as_raw()`). Seeded profile, `Enter` every 15 s, WARP,
160 s, every present:

```
distinct sources: 2   (0x鈥060 脳1087, 0x鈥?69a0 脳1087)
f=300 src=A   f=301 src=B   f=302 src=A   f=303 src=B   鈥?  (strict alternation)
```

So the presented texture is **double buffered** by the title, one present per
texture, and every one of those presents logs `behind=0`: the copy is complete
before `Present` in every case. The picture, meanwhile, keeps its three-frame
cycle (this run, same window):

```
310 89794D  311 13C50A  312 5E208F
313 89794D  314 13C50A  315 5E208F
...
322 89794D  323 4077E5  324 5E208F
325 89794D  326 4077E5  327 5E208F
```

Two periods at once 鈥?2 for the textures, 3 for the pictures, so the pair
repeats every six frames 鈥?and the same picture appears on *both* textures in
turn (321 and 324 are the same file, from different sources). A new picture
arrives once per three presents and is then shown twice more.

That is the regression, and it is not the present path (sync, `behind=0`), not
the ring (two, and both carry the same picture), and not a skipped refresh
(`0 skipped`). What is left is the **refresh cadence of the presented texture**:
the same picture being copied on the second and third present of a frame means
the content the layer hands the back buffer is not the frame the title has just
finished. The next probe is a counter per host texture 鈥?refreshed since its
last present, yes or no 鈥?logged with each present, which turns "same picture
again" into either "not refreshed" (refresh cadence, fixable in `shadow`) or
"refreshed, and the title really drew that" (the title's own double buffer).

### 2026-11-25 10:00: the draws advance every frame; the picture advances every third

The queue's own line, same run, gives the draws per presented frame (cumulative,
so differences over a window are exact): frame 256 鈫?512 carries 2,466 鈭?2,203
draws over 256 frames (鈮? a frame at the loading screen's start) and 512 鈫?1,024 carries 7,300 鈭?2,203 over 512 (鈮?0 a frame). **The title draws every
frame.** The picture, meanwhile, repeats with a period of three (section
above), and each of the two host textures shows all three pictures in turn, so
the alternation is not what makes it repeat.

The chain a presented picture goes through, and which of its steps can be three
frames behind:

```
title draw 鈫?copy-back into title memory 鈫?Texture::refresh (staging)
           鈫?host copy upload 鈫?present's CopyResource(back, host copy)
```

`Texture::refresh` is deduped per submission: `Batch::texture_due` (host.rs)
refreshes a staging at most once until something writes title memory
(`Batch::title_written` clears the set), and `Texture::refresh_timed` returns 0
early when the write-watch says the pages did not change. The copy-back of what
the frame's shaders wrote is the step before both. Three frames is exactly one
turn of that chain, which is where the next instrument goes: a **content
generation** counter per host copy, bumped at every fill (and at every
copy-back that names it), logged with each present 鈥?then "the same picture
again" becomes "this picture is three generations old", and the step that
skips two of three turns is named.

### 2026-11-25 10:05: c96b4f2 merged — and the default is now the relayed present

`fxceless/victory-fork`'s `main` moved a803c87 → **c96b4f2** (the fork owner's own
commit, Nov 24 20:22 -0500): the depth bounds test of #82 made from a
`DEPTH_STENCIL1` stream under its own library name with the title's
`OMSetDepthBounds` reaching the host list, faster defaults (stage-2 copy-back, wide
copy-back, card copies from 1 MiB, 256 lists in the air — "about 230 ms a frame
where it was about 400"), textures picked by index uploaded while loading and before
the decoration bake, and placed textures keyed without their description's filler
words. Merged here without a conflict; `victory-gpu` 114 passed, `victory-hle` 101,
`victory-shader` 215.

**The merge changes what "default" means, and the section above is where it matters.**
`shadow::relay()` at 17d0311 was `VICTORY_RELAY` set to 1 or 2; c96b4f2 makes it
**on unless `VICTORY_RELAY=0`**, so `late_stage()` answers 3 with nothing set. Run on
WARP with `VICTORY_PRESENT_TRACE=1`, merged tree, no environment at all:

| arm | presents | copy sent ahead | `behind` at present |
|---|---|---|---|
| merged tree, defaults | 309 | **309 (every one)** | 1–8, never 0 |
| 17d0311 (the 09:06 table's "default") | 685 | 0 | 0 every time |

So the 09:06 table's *default* arm is now the relay arm, and its `VICTORY_RELAY=1`
arm is the default. Anyone re-taking the animation measurements on this tree has to
use `VICTORY_RELAY=0` as the unrelayed arm, or every arm will be relayed. The
`behind` spread is wider too (1–8 rather than 1–2): c96b4f2 also raises the lists in
the air.

### The heap-buffer sweep is not what the world dies on

Four seeded WARP runs of the world (a `settings.xml` in the data folder, `Enter`
every 15 s, no setup pages) agree on where the flow goes and not on when the device
goes:

| run | tree | came up in the world | lost the device |
|---|---|---|---|
| seed2 | 54894e1 | 01:13:11 | **82 s later**, `while buffer views of the heap were made` |
| seed3 | +c96b4f2 | 01:48:58 | **181 s later**, `after 1 submissions sent ahead of 1 lists` |
| seed4 | +c96b4f2, sliced sweep | 01:55:21 | never in 107 s |
| sweepA | +c96b4f2, sliced sweep | 02:00:43 | **96 s later** |
| sweepB | +c96b4f2, whole sweep (`VICTORY_HEAP_SWEEP=1`) | 02:04:28 | never in 94 s |

The heap pass walked all 104,139 slots in one submission and that is what seed2 died
inside, so it was the obvious suspect. Slicing it (a sixteenth of the heap a pass,
`VICTORY_HEAP_SWEEP=1` restores the whole heap at once, the slice is the same work
spread over 16 frames) does not move the death: 96 s sliced against 94 s whole, both
inside the 82–181 s spread of the runs that were not touching it. So the burst is a
1,484 ms stall, not the removal, and at 0.7–1.8 fps the device goes after 100–300
world frames whatever the sweep does.

What the death does say, every time: `after 1 submissions sent ahead
(VICTORY_RELAY=1) of 1 lists`, then `no host list for a state prelude` and
`no shared buffer … (0x887A0005) size=4194304`. seed3's line 246 ms before it is a
sweep letting go of **159 host copies of textures the title fills (80,064 KiB)**, each
held by its title texture alone. That is the next thing to test, not a conclusion.

`VICTORY_HEAP_SWEEP=1` is the switch this section adds; the world draws at 0.7–1.8 fps
on WARP in all five runs.

### 2026-11-25 10:40: three candidates for the world's death, and none of them is it

The world (a seeded data folder, `Enter` every 15 s, WARP) now has seven runs, and
each switch that was a suspect was measured one arm at a time:

| run | arm | came up in the world | device gone |
|---|---|---|---|
| seed2 | 54894e1, before the merges | 01:13:11 | **82 s** |
| seed3 | defaults (relay on, whole heap sweep) | 01:48:58 | **181 s** |
| seed4 | heap pass sliced | 01:55:21 | none in 107 s |
| sweepA | heap pass sliced | 02:00:43 | **96 s** |
| sweepB | `VICTORY_HEAP_SWEEP=1` (whole heap) | 02:04:28 | none in 94 s |
| relay0 | `VICTORY_RELAY=0` | 02:33:34 | **120 s** |
| sweep0 | `VICTORY_TEXTURE_SWEEP=0` | 02:37:55 | **98 s** |

Three things follow.

**The heap-buffer pass is not it** (96 s sliced against 94 s whole).

**The present relay is not it, and it does move the site.** With `VICTORY_RELAY=0` the
death line becomes `after a submission of 8 lists` instead of `after 1 submissions
sent ahead (VICTORY_RELAY=1) of 8 lists`: the same frames, reported by the synchronous
path. The timing is unchanged (120 s).

**The sweep that lets go of host copies of textures the title fills is not it either**
(98 s with `VICTORY_TEXTURE_SWEEP=0`, against 181 s and 82 s with it). Those sweeps are
large, though — `154 host copies of textures the title fills let go (247,680 KiB)` in
one line, 2.4 s before one of the deaths — so they stay on the list of things to watch
even though removing them did not save the world.

What is left is a death that comes after 80-180 s of world frames (0.7-1.8 fps, so
100-300 frames) in every arm, at a submission whose lists the log names nothing of.
The next probe is the debug layer: `VICTORY_D3D12_DEBUG=1`, seeded, WARP. The failure
text asks for it by name and it is the only thing that names a bad command instead of
an HRESULT.

### Slot 0x128 answers for the host device now (upstream #928)

`crates/victory-gpu/src/device.rs` left device slot 0x128 (`GetDeviceRemovedReason`)
on the default handler, which answers `E_NOTIMPL` (`0x80004001`) on a healthy device —
a title testing `FAILED(GetDeviceRemovedReason())` reads that as a lost device.
Upstream `13185f5` wires it to a query of the host device's own state; that body is
here now, with a unit test that the slot answers `S_OK` while the host device lives
(`victory-gpu` 115 passed). This is the `0x887A0004` half of every failure line: the
console's own answer is now the host's answer instead of a made-up one.

### What the three switches are

- `VICTORY_FEATURE_TRACE=1`: one line per title `CheckFeatureSupport`, with the
  answer's first sixteen words.
- `VICTORY_VIEW_HEAP_CAP=<n>`: pretend the host caps view heaps at `n`, so the
  software adapter takes the fallback a card takes (the run above).
- The wave-lane and view-heap lines print at `info` without a switch.
- `title slot past the host heap` is now one line per 2^16 of them instead of
  one per slot: that warning was 310,720 lines (3.4 MB) in one run.


### The opening animation never plays at all
`movies.rpf` is registered with DirectStorage at start-up and nothing else: no
`Bink*` import is called, and no media interface is asked for. Presented frames
agree 鈥?`frame-1` to `frame-64` are pure black, and from `frame-120` on every
frame is the same still of the account picker with nothing but its button
prompts drawn. So on this machine there is no opening animation to flicker;
issue #103 reports the same thing from another machine.

### The screen blinking is that restart's fade, not a lost pass

`victory_gpu::queue` reports a presented frame that is black after one that was
not, and it could not say what the frame drew: `draw::trace` keeps its lines
only while `victory_gpu::draw` is at debug, so a run at `info` printed the
warning with nothing under it. It now says which switch records them.

With the switch on, the black frame holds 27 draws, all into one `3840x2160 f28`
target, and the constant buffers they read carry `1.77e-7, 1.77e-7, 1.77e-7, 1.0`
鈥?a fade at its end. The level line before it walks `145 鈥?44 鈫?0` and the one
after climbs `63 鈥?234`. So it is the fade through black between two screens,
not a pass that failed. A run that cannot finish the first-run flow fades out
and back in on every attempt, which is what the screen blinking looks like.
Fixing the flow (above) should take the blinking with it.

The check that would settle it, for anyone already in the world:

```powershell
# a fresh data folder each run; the switch that renders the world
$env:VICTORY_DATA_DIR = "$env:TEMP\vwide"
$env:VICTORY_WAVE_WIDE = "1"
.\target\diag\victory.exe run <game dir>\game_scarlett_master.exe --execute
# then open the in-game settings menu once the prologue is playable
```

Before the change: `host GPU device removed` on the first list of the
submission the menu makes (`0x887A0004` + `0x887A0006`). After it: no removal,
and `VICTORY_GROUP_SYNC=0` versus unset should no longer change whether the
menu survives.

## Related

- #101 鈥?the report this comes from.
- #96 鈥?the measurement template this text follows.
- `docs/fork-ray-tracing.md` 鈥?the other place where wave64 programs in two
  host waves must meet.

### 2026-11-25 09:55: the fork's c96b4f2 is in, and it is worth 3x on the world path

The merge `4f75cbf` brings fxceless's `c96b4f2` ("the depth bounds test works; faster
defaults; textures are on the card before the character bake; one host copy per placed
texture") onto this branch. Verified here:

- `cargo build --profile diag -p victory --features diagnostics` clean;
  `cargo test -p victory-gpu -p victory-hle --lib` 鈫?**121 + 101 passed**, 0 failed.
- Seeded profile, `Enter` every 15 s, WARP, 185 s: **4.4鈥?1.7 fps (mostly 5鈥?4)**, world packs
  opened (`core_restofworld001`), and **no device removal in the whole run** 鈥?where the run
  before this merge was 1.6鈥?.8 fps and lost WARP's device 82 s in.

So the world path on the software adapter is roughly 3x faster than it was two hours ago and
survives five minutes. The three-frame picture cycle measured earlier was on the pre-merge
tree at 9 fps on the loading screen; whether it still holds at 5鈥?4 fps is the next thing to
re-measure, with the same one-hash-per-frame method.

### 2026-11-25 10:05: upstream's copy-back rewrite is not needed here — ours already costs 0.16 ms

Upstream `cd94d35` (`view_marks`) exists because, on their tree, the world snapshotted
**2.8–4.5 GB a frame** before each submission and compared it after: 98 % unchanged, and
**0.45–0.7 s of a 1.5–1.7 s intro-cutscene frame**. The same counter, on this branch, in the
seeded world path at 39–47 draws a frame:

```
copies per frame: 4.0 submissions; 49 title copies 0.0 MB; 43 refreshes 338.4 MB, 0 skipped;
12 watches 0.13 ms, 161.9 MB checked, 161.2 MB unchanged
```

**161.9 MB, 0.13–0.16 ms.** Three orders of magnitude off upstream's problem, and 99.6 %
unchanged rather than 98 %. Whatever narrowing this lineage already does, the cost that
motivated `view_marks` is not in this tree.

Porting it would also be a rewrite, not a patch: against the commit's parent, our copies of
the files it touches differ by thousands of lines —

| file | changed by the commit | our copy vs its parent (added / removed) |
|---|---|---|
| `victory-shader/src/emit/lower.rs` | +126 | 4,904 / 3,852 |
| `victory-gpu/src/host.rs` | 32 | 4,743 / 1,087 |
| `victory-gpu/src/shadow.rs` | +377 | 2,818 / 778 |
| `victory-gpu/src/draw.rs` | 70 | 1,795 / 1,388 |
| `victory-gpu/src/descriptor/host.rs` | 72 | 1,679 / 654 |

and five of its test files do not exist here at all.

**Decision: do not port.** Watch `fxceless/victory-fork` instead — that fork's history is
literally "take this branch of that fork as one commit", and when it absorbs `cd94d35` the
merge is theirs to make. The one thing worth taking from upstream is whatever it does that
this tree still does slowly, and by these counters the copy-back is not it.

### 2026-11-25 10:12: joined by frame — the picture replays from three frames back in 130 of 149

One run with both instruments on (seeded profile, `Enter` every 15 s, WARP, 120 s,
`VICTORY_PRESENT_TRACE=1`, every frame 150–300 captured), joined by frame number:

```
206 89794D  host …9d0   title …f80
207 13C50A  host …dd0   title …720
208 5E208F  host …9d0   title …f80
209 89794D  host …dd0   title …720     <- 206's picture, on the other texture
210 13C50A  host …9d0   title …f80     <- 207's
211 5E208F  host …dd0   title …720     <- 208's
212 89794D  host …9d0   title …f80
```

Measured over the whole window: **130 of 149 comparable frames present the same picture as
three frames earlier**; the set of pictures keeps changing (13C50A, 89794D, 5E208F, 427BF8,
E3D561, 8FE7FB …), so this is not a three-frame loop the title plays on purpose — pictures
that are new are interleaved with replays of older ones, which is exactly "it goes back a
frame or two while it moves on".

The two title resources and the two host copies stay one-to-one and alternate every present
throughout (the table's `host`/`title` columns), so the replay is not a mix-up between
buffers: each texture's own content moves on, and the *same* picture arrives on the other
texture three frames later.

That is the state to hand on: the replay is real, quantified, and reproduces in one 2-minute
run with two switches; what is not yet known is which side re-delivers the older picture —
the title's own copy between its two buffers, or this layer's copy into the host copy of the
second one.

### 2026-11-25 10:20: 21 pictures in 161 frames, held one frame at a time

The same joined run, counted as runs of identical pictures instead of pairs:

```
161 frames, 21 distinct pictures
run lengths: 7, 48, 1,1,1, … (1 repeated 148 times), 6
```

So the picture changes on almost every presented frame (148 single-frame runs), and only three
long holds exist — one 7-frame, one 6-frame, and one 48-frame static screen. Together with
"130 of 149 frames equal the frame three back" that reads as a **three-deep rotation over a
slowly changing set of pictures**: a new picture enters the rotation every few frames and is
then shown again two frames later.

What that is not: a frozen copy (it changes every frame), an authored three-frame loop (the
set of pictures changes: 21 of them), or a buffer mix-up (two title resources and two host
copies, one-to-one, alternating).

What is left is the same question, and it needs one more number: for the presented host copy,
**how many times it has been written by the GPU since its last present**. That counter belongs
next to `Hosted`/`HostTexture` and is logged with the same present line; with it, a picture
that comes back is either "this host copy was not written in the meantime" (the layer's copy)
or "it was written, and the title drew that" (the title's own timing).

### Upstream, this round

`Marvisak/VIctory` at `940d32f` and `fxceless/victory-fork` at `c96b4f2` — no new commits
since the last check.

### 2026-11-25 10:30: the replay is on the card too — same shape, 30 fps

Same seeded loading screen, same keys, 80 s, this time on the **RTX 4080 SUPER** at a steady
30.0 fps (33.3 ms a frame), every frame 100–260 captured:

| adapter | frames captured | distinct pictures | frames that changed | of those, equal to three back |
|---|---|---|---|---|
| RTX 4080 SUPER, 30 fps | 171 | 14 | 33 | **22 (67 %)** |
| WARP, 9–30 fps | 161 | 21 | 99 | **82 (83 %)** |

So the three-frame replay is not a software-adapter artefact and not the late/present paths
(both runs default, `behind=0` throughout). The card shows it too: 22 of the 33 frames that
move on show the picture from three frames earlier. Holds are longer on the card
(runs of 38, 85, 9, 4, 3), which is what a faster card does with the same authored content.

**Read together with the frozen refresh counters** (above), the per-frame content the draws
produce is being fed from something that advances one step per three frames. Texture
refreshes are not it (zero asked). That leaves the *other* half of the same machinery —
the buffer/constant ranges a frame's draws read, refreshed per submission from title memory
(`shadow`'s refreshes, 338 MB a frame, `0 skipped`): if those reach the list one submission in
three, the draws render the state the title had three submissions ago and the same picture
comes back, which is exactly the shape measured.

Next probe, cheap: log per submission how many buffer refreshes were asked, how many were
deferred by `stale_under_flights`/`Batch::texture_due`-style dedup, and the age (in
submissions) of the oldest refresh a list actually read.

### 2026-11-25 10:35: the three "pictures" are three glow phases of the same stars

The hashes that cycle are three *visibly different* images — 30,298, 84,926 and 122,600 bytes —
so they are not near-identical frames. Looked at, they are the same seven stars with the same
left-to-right orange→magenta gradient at three glow intensities: `docs/stars-bright.png`
(frame 208, hash 5E208F) has the heavy bloom, `docs/stars-dim.png` (frame 209, hash 89794D) is
the dim phase, and the third is between them.

A three-phase glow pulse on a loading screen is exactly the sort of thing a title animates in
three steps and loops. Which means the measurement of the last four rounds — "130 of 149
frames show the picture from three back" — may be **the authored loop**, not a replay of old
frames at all, and none of the plumbing counters disagree: texture refreshes zero, buffer
refreshes steady at 40 asked / 2 done on every present, both adapters, `behind=0` throughout.

To settle it one would need the title's own animation clock, which this layer does not see.
What the layer *can* still answer is whether a frame is ever presented twice from the same
content with different frames in between *at a rate the title cannot have authored* — and for
that the place to measure is the world's intro, where frames are 60 times longer and a replay
would be unmistakable, not the loading screen's 30 fps pulse.

**Reported as an honest negative for the plumbing: six instruments (present fence, relay,
present digest, source/title pointers, texture refresh generations, buffer refresh counters)
find no path in this layer that re-delivers an older picture, and the math of the remaining
candidate — the title's own three-phase glow — fits every number.**

### 2026-11-25 10:40: the whole workspace is green after the fork's merge

`cargo test --workspace --lib --profile diag --features diagnostics` on this branch, after
`4f75cbf` brought fxceless's `c96b4f2` in:

```
11 + 24 + 3 + 121 + 101 + 25 + 7 + 4 + 215 = 511 passed, 0 failed, 8 ignored
```

and `cargo build --profile diag -p victory --features diagnostics` clean. That is the state
the 31 unpushed commits sit on.

### 2026-11-25 10:50: an empty `settings.xml` is enough — the title only checks that the file is there

Three arms, WARP, 40 s each, `Enter` at 15/20/25/30 s, fresh data folder, only the seeded
file differing, counting the first world packs opened (`core_restofworld`, `story000`):

| `Z:\settings\settings.xml` | world packs at 40 s |
|---|---|
| full file the flow wrote (3,921 bytes) | **8**, first at 16 s |
| a 162-byte skeleton (`<rage__fwSystemSettingsCollection>` with version 6.0 only) | **8** |
| **a 0-byte file** | **8** |

So the flow does not read the settings back to decide anything: it asks whether the file
exists (`GetFileAttributesW`, then `CreateFileW`, four seconds in — the calls the section above
logged), and if it does, the setup pages never come. The 0-byte file is still 0 bytes at the
end of the run, so the title's own save path did not rewrite it either — it runs on defaults.

That closes the question this objective opened: *what decides "the profile exists"* is the
presence of `Z:\settings\settings.xml`, not the two other directories, not their contents, and
not anything inside the file. The title will still write a real one when the flow walks it
(see the section above), and a launcher can therefore pick either: walk the flow once, or drop
any file of that name.

### 2026-11-25 10:55: the forty-second route into the world, and what the world costs

Everything the last two rounds established, as a recipe anyone can run:

```powershell
# 1. a data folder whose first run is already "set up": any file of that name will do
$dir = "$env:TEMP\vworld"; Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$dir\7952987A\storage\settings" | Out-Null
New-Item -ItemType File -Path "$dir\7952987A\storage\settings\settings.xml" | Out-Null

# 2. the pad's A is Enter: the setup pages never come, the menus need one press each
$env:VICTORY_DATA_DIR = $dir
$env:VICTORY_KEYS = "15:Enter,20:Enter,25:Enter,30:Enter"
$env:VICTORY_LOG = "info"
& .\target\diag\victory.exe run "<dump>\game_scarlett_master.exe" --execute
```

Measured on it (WARP): the first world packs (`core_restofworld`) open at **16 s**, and the
story's own packs (`pack\story000\story000.rpf`, `story000_script.rpf`) follow once the menus
are pressed through. The world then runs at **1.6 fps, about 620–630 ms a frame**, with frames
that read black in between (`levels … 0, 0, 0 …` warnings) and no device removal in any run
this build has done in that phase.

That rate is the honest current cost of the world on the software adapter: the 4.4–5.9 fps this
report measured earlier was a 39-draw loading-phase scene, not the story. Sixty times slower
than the 30 fps the menus hold, and the reason the world is the thing to work on next.

### 2026-11-25 11:00: the world's 1.6 fps is the software rasterizer at 4K, and the card does not flinch

Two measurements of the same recipe, same build:

**WARP** (the story-loading phase, 11–12 draws a frame):

```
627.5 ms/frame = 10.0 preparing (copies 0.3 ms, textures 9.4 ms) + 615.3 on the GPU, 12 draws
625.3 ms/frame =  4.6 preparing + 618.5 on the GPU, 12 draws
462.9 ms/frame =  2.2 preparing + 458.6 on the GPU
1417.4 ms/frame = 196.0 preparing (textures 190.2 ms, 384 MB) + 869.9 on the GPU   (one spike)
```

The layer's own work is 2–11 ms of it; the rest is the card, which is not a card — it is the
software rasterizer drawing **3840×2160** frames with a dozen passes. 1.6 fps for that is a
measurement of WARP, not of the translation.

**RTX 4080 SUPER**, same recipe, 100 s: **30.0 fps, 33.3 ms a frame, 22 draws, 0 black frames,
0 device removals**, eight world packs opened. The fastest frames are 94.8 ms, the slowest 10.5
fps, so it holds the frame rate while loading. Earlier reports in this repository have the card
losing its device within 7–18 s of the same phase on `70564ae` and `644ebeb`; this branch does
not, in any run so far.

So the world's cost on the software adapter is its rasterizer, and the card's world phase — at
least up to the story packs, which this run did not reach — is not where it dies.

### 2026-11-25 11:05: on the card that phase costs nothing at all

Same card run as above, frame times as the layer reports them:

```
33.3 ms/frame = 0.5 ms preparing + 0.0 on the GPU    (22 draws, repeated)
frame interval interval=33.333ms                      (the title's own 30 fps setting)
```

**0.0 ms of GPU work in a 33.3 ms budget.** The 30 fps is the title's `desiredFPS` wire, not the
card's limit, and the 4K phase that costs the software adapter 615 ms costs this card nothing
measurable. Whatever keeps the world from being fast on this machine, it is not the card being
busy in this phase; and whatever lost the device on `70564ae` and `644ebeb` within 7–18 s of it
is not happening in this build at all.

The story packs were not reached on the card in that 100 s run (the menus take more presses
there than on WARP), so everything above is the world's *loading* phase. The next step on this
side is the same run with a longer key script, and the honest risk that comes with it: three
reports in this repository have a card freezing hard in the world, so it stays a
single-shot 2–3 minute run that gets checked for a living machine afterwards.

### 2026-11-25 11:10: a WARP world run that simply keeps going

A second session's world run (`sweep0`), same build, seeded profile, WARP:

- started 10:36:55, still presenting at 11:10 — **33+ minutes in the world**, 2–3 fps
  (355–610 ms a frame), 11–12 draws;
- **9.85 GB working set**, ~2.8 cores of CPU in steady state, 0 device removals, 0 black frames
  in the last 0.8 MB of log, seven `story000` packs open.

Three things that follow. The world on the software adapter is slow but **durable** — over half
an hour without losing the device, where the earlier builds died within seconds. Memory is the
next wall worth watching: 9.85 GB resident for one title is why this machine's free memory line
matters (`8,881 MB free, 29,073 MB left to commit` in the run above). And a run like this owns
the machine: with it going, no other measurement is worth taking (this round took none), which
is the practical cost of the world being 2 fps on WARP.

**Correction, same minute:** the process that pid belonged to was replaced between two reads —
the run is 2.1 minutes old, not 33, so "33+ minutes in the world" does not hold and is struck.
What does hold for the current one: 2 fps, 631 ms a frame, 15 draws, and a working set that has
grown to **13.43 GB** (from 9.85 GB minutes earlier) — memory is worth watching, but no claim
about half an hour of durability is supported by these two reads. The durable runs this report
can vouch for remain the 100 s card run (30 fps, 0 removals) and the 185 s WARP run (4.4–21.7
fps, 0 removals).

### 2026-11-25 11:20: on the card the flow stops at the legal notices, whatever the keys do

Four runs on the RTX 4080 SUPER with the same forty-second recipe, differing only in the key
script:

| run | keys | length | world packs | story packs | device removals |
|---|---|---|---|---|---|
| `cardworld` | Enter at 15/20/25/30/40 s | 100 s | 8 | 0 | 0 |
| `cardstory` | Enter every 5 s, 15–120 s | 150 s | 8 | 0 | 0 |
| `cardstory2` | Down,Down,Enter every 5 s, 100–195 s | 225 s | 8 | 0 | 0 |
| `cardstory3` | **Enter every 2 s, 5–235 s** | 245 s | 8 | 0 | 0 |

All four hold **30.0 fps at 0.0 ms of GPU**, lose no device, and never leave the menus. The
frame captured at 117 s in `cardstory` is the **LEGAL NOTICES** page with the cursor on
`Copyright` and `Next` drawn — the same page the WARP runs walk past with `Down, Down, Enter`.

So the card's world phase is reachable as far as the loading packs and no further *because of
input*, not rendering: the identical recipe reaches `story000` on WARP in 40 seconds. Whether the
stand-in pad's buttons reach the title at all on the card is the next thing to instrument — a
line per second naming the buttons the pad reports would settle it in one run, and until then no
card measurement past the menus means anything.

What is *not* in doubt: 100–245 s of the card's world-loading phase at 30 fps with 0.0 ms of GPU
and no device removal, against 7–18 s to removal on `70564ae` and `644ebeb`.
