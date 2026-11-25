# What this branch has that upstream does not, judged against the forks and the merged PRs

Checked 2026-11-25 21:40 against `Marvisak/VIctory` (225 merged PRs, 100+ forks), the
most-starred forks, and `fxceless/victory-fork` (two unmerged commits, `a253706`, `0b0074e`).

## The ecosystem is working on shaders, not on this

| fork | stars | what it is doing |
|---|---|---|
| `JMAN730/project-flamingo` | 42 | shader tests, tests compile again (merges of shader PRs) |
| `PastiiJay/klbf-lab-beta` | 11 | FidelityFX SDK requirement for Series S mode, water physics on a 5070 Ti |
| `DexNom/VIctory` | 10 | **wave64 mask restored from scalar copies**, 40 shader variants, integer-target blending |
| `Xeltax/VIcky`, `asdaasdsaddf`, others | 3 | forks of the same shader line |

Nobody in that list is measuring frame composition, host memory, or how to drive the title's menus.
That is where this branch's commits land.

## Judged, group by group

| this branch's work | upstream status | verdict |
|---|---|---|
| `rpcrt4` GUID HLE (`17d0311`) | **came from upstream** (`7216ab7`) | not ours; keep as the base needs it |
| `GetDeviceRemovedReason` (`9f82e00`) | **upstream #928, merged** | not ours; ported deliberately |
| `VICTORY_COPY_PLAIN`-style user-mode copies | **upstream #1010 open**, fxceless `0b0074e` implements it | superseded — take theirs |
| `cd94d35` view_marks | upstream, merged | we measured it as unnecessary here (12 watches, 0.13–0.16 ms) |
| present trace, picture digest, refresh counters | superseded in instrumentation by fxceless `a253706` (`FRAME_LOG`, `CARD_METER`, `DRIVER_WATCH`) | take theirs; ours found what theirs cannot (below) |
| **texture-refresh numbers** — 24,821 refreshes and 24.8 GB of title memory a frame, `0 skipped` | upstream has **#388 open** ("28 ms a frame refreshing sampled textures" under Wine) and **#1873** (share the detile scratch) | **complementary and stronger**: our frame was 7 s of it, and the `0 skipped` counter is the exact evidence #388 lacks |
| **the staging budget is the heap pass** — 192 MB → 420.8 ms, 64 MB → 139–499 ms | no upstream issue found | **unique** knob and measurement |
| **written-only detiling** with a 64 KiB page bitmap (bytes 372 → 4–28 MB a frame) | **#388** covers the retile path, not this | **unique**, and it is the answer to "which pages" rather than "which texture" |
| **scripted keys must drive the pad sticks**, not only its buttons | **#1702 open** (`VICTORY_NO_HOST_PAD`: a host pad hides the stand-in) and **#1430**, **#729**, **#1786** in the same area | **unique half of a known problem**: enumerating the stand-in is not enough if the title polls pad 0, which is what our measurement shows |
| **the terms page cannot be passed without a stick** (confirm disabled until the box is ticked) | no issue found | **unique** — and it is why a first run stops there for everyone |
| **the title does commit saves** (Player v4, SARC0015 242,992 B, SettingsProfileSettings) | no issue found; our own objective assumed the opposite | **unique correction**, worth posting where first runs are reported |
| **WARP cannot be used to judge the world**: 458 compute pipelines refused, "wants wave lane count of 64 … maximum is 4" | **#2105, #599, #2035 open** (wave intrinsics on narrow host waves) | **complementary**: our line explains the WARP world's 1,935 dropped draws a frame in one sentence |
| **the fatal path is `mov dword ptr [0], 0x4d8bd421` after formatting `ALERT_ERROR_SUPPORT_0x%x`** | no issue found | **unique** reverse-engineering of the crash site |
| **the WARP world's death is host memory** (6 → 18.4 GB in 30 s, `0x887A0005`, zero `E_OUTOFMEMORY` from our own allocations) | **#1479 open** reports the same shape on a 4070: world held 80 s, then removal after a 3,818 ms submission | **complementary and larger**: our numbers say what the memory was (10 GB of texture twins + 9 GB of upload buffers), and our card run says it is not the title |
| **the card runs the opening cutscene and credits** at 4.2–7.9 fps, 700–900 s without a removal | first-run reports are all "world dies" | **unique evidence** that the branch's own state is a working one |
| `drive_card.ps1` (real keys), `world_ram.ps1`, `frame_stats.ps1`, `disasm_rva.py` | nothing comparable in the forks | **unique tooling** |
| `docs/world-death.md`, `next-steps.md` | — | **unique record** of what was excluded and how |

## What is worth sending, and where

Cannot be posted from here (no write access to `Marvisak/VIctory`), so these are for the operator:

1. **#1479** (first run: world 80 s then removal): the memory composition at the removal, the
   per-second RAM series, and the fact that the same phase on a 4080 SUPER runs 700–900 s without a
   removal — with `VICTORY_FAST=1` and `VICTORY_TEXTURE_STAGE_MB=64`.
2. **#1702** (host pad hides the stand-in): that enumerating the stand-in is not sufficient — the
   title polls pad 0, its buttons reach it and its **sticks do not**, which is what keeps the terms
   page from being passed. Include the `FALLBACK_BUTTONS` sticking and the schedule that works.
3. **#388** (refresh cost under Wine): the `0 skipped` counter and the 24,821-refresh frame; the
   written-bytes ratio (13–23 % of what a whole detile moves) as the measurement that says which
   granularity pays.
4. **#2105 / #599 / #2035** (wave intrinsics): the debug layer's own sentence for the 458 refusals,
   and the WARP world's 1,935 dropped draws a frame as its consequence.
5. Any first-run thread: that the saves **are** committed and versioned on disk, and that what stops
   the flow is the terms page, not a save.

## What not to spend more time on

- Porting what the fork has already done better (`COPY_PLAIN`, `FRAME_LOG`, `DRIVER_WATCH`,
  `REFRESH_ONCE`, the corrected draw-window numbers) — merge, do not re-derive.
- Shader fidelity work: the top forks are all in it, and it is not this branch's line.
- Re-measuring the WARP world's correctness: wave64 cannot exist there.
