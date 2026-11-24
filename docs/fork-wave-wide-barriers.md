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
already makes elsewhere — it is the *approximate* form, and it only runs when
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
`b99f876b74d4a77f03af5f878223b27bd647b5c35a79d5decd9f716504239e93` — the same
build every report in this repository uses. Rust 1.98.1 (pinned), MSVC
14.44.35207, SDK 10.0.26100.0.

- `census` sees 18 images, 0 unreadable; `run` without `--execute` binds
  `game_scarlett_master.exe` at **88 hle, 427 host, 72 title, 0 missing**, and
  the four title DLLs at 9/48, 4/18, 27/171 and 6/54, all 0 missing — the same
  numbers as the report in the upstream repository's own issue.
- The title boots and the first-run screens run at **30 fps, 33.3 ms/frame,
  38-61 draws/frame**, at 1920x1080, on the 4080 (the host's memory line
  reports a 15,277 MB budget, so the adapter is the card, not a virtual one).
- Legal notices, the Rockstar terms page (two checkboxes, Confirm greyed out
  until both are ticked), the brightness calibration page, the "finish setup?"
  page and the loading art all render correctly — text legible, selection
  highlight correct, pad prompts drawn.
- 2D is clean and there is no device loss on this path with or without the
  patch.

## What was not verified

**The fix is unproven until a machine that reaches the world runs it.** This
machine did not: scripted `VICTORY_KEYS` walked account picker → legal notices →
terms → brightness → "finish setup?", and then the title came back to the legal
notices page instead of loading, on every attempt (9 runs, 60-160 s each, fresh
`VICTORY_DATA_DIR`). Whether that is the profile write, the offline account, or
the key sequence is not known yet, and it is the reason this change cannot claim
#101 fixed.

### What the first-run flow does on the way out

With `VICTORY_LOG` at debug for `victory_hle::modules`:

- The title asks for the persistent-local-storage provider
  (`f4faf4d4-2d04-4fce-b3e0-474a713a3e84`) with the 2026 interface
  (`41a4e10c-…`) and gets it; the calls are served, and the path it receives is
  a drive root as intended.
- It then reaches `Z:\settings\`, `Z:\cloudpers\`, `Z:\cloudcache\` and
  `Z:\cloudcache\*` — directories and one wildcard enumeration — and writes no
  file in any of them. `storage\settings`, `storage\cloudpers` and
  `storage\cloudcache` exist and stay empty; `saves\` gets a container
  directory (`0009000000000001\00000000-0000-0000-0000-00007952987a`) and nothing
  inside it.
- **No `XGameSave` provider is ever requested**, so none of the save API in
  `victory-hle::modules::xgamesave` is reached at all; the container directory
  is made by something else. `XGameSaveSubmitUpdate` (the blocking form, 0xd8)
  was `missing` in this fork and is now implemented as the same commit the
  async form runs — it changes nothing here, because nothing calls it.
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
or CRT open of a file under any of them — so the configuration is not lost on
the way out, it is never asked to be written. `storage\settings`,
`storage\cloudpers` and `storage\cloudcache` stay empty, and `saves\` gets one
container directory with nothing in it.

That moves the question one step earlier: what makes the flow decide there is
nothing to save, or fail before it tries. Two candidates left — the
persistent-local-storage quota the title reads (`storage::space`, 2048 MB from
the manifest) and whatever `XPackage` answers while the flow runs (its provider
is the second most asked one in the log).

`XPackage` is not it: `xgameruntime::missing` warns with its area and slot on
every call, and a whole run produces **no** "runtime method not implemented"
line at all. So of the fifteen slots this fork leaves out there, the title
calls none — it asks for the interface and then uses what is implemented.

The quota is not it either: `storage::space_info` and
`storage::prompt_for_space` now log what they answer, and a whole first-run
walk produces **no** line from either. The title never asks how much room it
has. With `files` at debug, the same walk asks for 233 paths and four of them
are on the persistent drive:

```
Z:\settings\   Z:\cloudpers\   Z:\cloudcache\   Z:\cloudcache\*
```

Three directories and one wildcard. It never asks about a file, never asks for
room, and never submits a save. So the flow does not fail to save — **it never
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
fork has since moved the cross-lane retry around — `#11` was taken out and put
back twice in the last four commits), or the programs that need it only appear
once the world loads, which this machine cannot reach. The run that settles it
is the same one #101 describes, on a machine already in the world.

### On the card the device is lost before the menus; on WARP it runs

Upstream (`70564ae`), same dump, same binary:

| adapter | rate | draws | device |
|---|---|---|---|
| RTX 4080 SUPER | 0.1–0.2 fps, 6,300–6,700 ms/frame | 2 | lost (reason `0x887A0001`; the `0x887A0004` in that line is the DRED query, see below) |
| WARP | 15 fps, 66.7 ms/frame | 21 | none; `crashes.log` never written |

The card is **150x slower than the software adapter** and then dies, which is
the opposite of what it should do. Two more facts narrow it:

- With `VICTORY_D3D12_DRED=1` the breadcrumbs are **empty**
  (`(done/count, list) []`), so no command list of ours faulted — the device
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
host GPU device removed after a submission of 1 lists; no breadcrumbs (… 0x887A0004); device removed: … 0x887A0001
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
made, mesh tier at shader model 6.6 — and `mesh_shaders()` is never called
either. There is no query whose answer differs to blame.

**The card's device loss belongs to `70564ae`, not to this tree.** Same dump,
same card, same menus, same `diag` build settings, fresh data folder, DRED on,
35 s each:

| tree | adapter | rate | draws | view heap (title slots / host slots) | wave lanes | device |
|---|---|---|---|---|---|---|
| `70564ae` (upstream) | RTX 4080 SUPER | 0.1–0.2 fps, 6,300–6,700 ms/frame | 2 | 1,245,184 / 934,464 (capped) | not asked | **lost at ~7 s**, `0x887A0001`, breadcrumbs `[]` |
| `2119b0e` + this branch | RTX 4080 SUPER | 30.0 fps, 31–33 ms/frame | 21 | 1,245,184 / 737,855 (capped) | min 32 / max 32 | none in 40 s, with and without `VICTORY_WAVE_WIDE=1` |
| `2119b0e` + this branch | WARP | 21–30 fps, 33–46 ms/frame | 21 | 1,245,184 / 1,507,328 (no cap) | min 4 / max 4 | none |

`2119b0e`'s merge base with `70564ae` **is** `70564ae`: the fork is 225 commits
ahead of it, and `e9765a7 Fix the device loss introduced by the wave64 update`
is one of them (ancestor check, 0). So the loss the last report measured was
already fixed in the branch's base, and nothing in these five commits touches
it. On this tree the card is not 150x slower than the software adapter: it
renders the same menus at 30 fps against WARP's 21–30, where `70564ae` renders
them at 0.1–0.2 on the same card.

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
tried at all. It does not decide the device loss — the failing tree never asks.

### The other one: the title's view heap is 1,245,184 slots and the card stops at 1,000,000

`HostHeap::new` now prints what it asked for and what it got:

```
RTX 4080 SUPER  host view heap capped: the title's heap does not fit
                error=… (0x80070057) title=1245184 extra=262144 requested=1507328 limit=1000000
                host descriptor heap title_slots=737855 dynamic=262144 host_slots=1000000
WARP            host descriptor heap title_slots=1245184 dynamic=262144 host_slots=1507328
```

WARP makes the title's heap and 2^18 dynamic slots in one go (1,507,328). The
card refuses anything past 1,000,000, so the fallback keeps 1,000,000 slots and
**737,855 of the title's 1,245,184** — 507,329 slots (41%) have no host
descriptor, and a shader that indexes one reads whatever the heap's last slot
holds. On `70564ae` the same cap left 934,464 (its `DYNAMIC` is 2^16), and the
per-submission sweep that tree runs over the title's heap printed
`title slot past the host heap` **310,720** times, one per slot it could not
make: 1,245,184 − 934,464 exactly.

Missing descriptors alone do not remove a device: with the cap forced on the
software adapter (`VICTORY_VIEW_HEAP_CAP=1000000`) WARP keeps running at
22 fps for the whole run. So this is a defect for the world, whose heaps are
past 737,855, and not the `0x887A0004`.

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
agree — `frame-1` to `frame-64` are pure black, and from `frame-120` on every
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
— a fade at its end. The level line before it walks `145 … 44 → 0` and the one
after climbs `63 … 234`. So it is the fade through black between two screens,
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

- #101 — the report this comes from.
- #96 — the measurement template this text follows.
- `docs/fork-ray-tracing.md` — the other place where wave64 programs in two
  host waves must meet.
