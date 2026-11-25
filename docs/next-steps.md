# What to do next on this branch, in order, with the numbers that justify each step

Written 2026-11-25 15:05 after the card's story was reached and ran for seven minutes at 6.5 fps
(`docs/world-death.md` has the runs). Everything here is measurable with the two tools in
`tools/`: `drive_card.ps1` (real keys — the card ignores `VICTORY_KEYS`) and `world_ram.ps1`.

## State of things

- **The card reaches the story and renders it**: `story_packs=7`, `world_packs=8`, zero device
  removals and zero traps over 420 s. Real keystrokes are needed; scripted ones do not move its
  menus (measured four ways: focus, delivery, pad polling, key hold).
- **WARP cannot be used to judge the world**: 458 compute pipelines are refused because the
  title's shaders want wave64 and WARP reports 4 lanes (`docs/world-death.md`). The WARP world's
  1,935 dropped draws a frame are that, not a translation bug.
- **The world's WARP death was host memory** (18–27 GB private, paging out, `0x887A0005`), not a
  GPU fault: excluded by counting `E_OUTOFMEMORY` per arm, by `VICTORY_SWEEP=0`, by
  `VICTORY_HOST_TEXTURE_CAP_MB`, and by the RAM sampler.
- With `VICTORY_TEXTURE_SAMPLE_SKIP=1` and `VICTORY_TEXTURE_REFRESH_EVERY=8` the story's frame is
  **145–522 ms (1.9–6.9 fps)** where it was 2,333–6,906 ms (0.1–0.4 fps), and a capture verifies
  the picture is intact.

## The three steps, largest first

1. **Refresh only the textures the frame reads.** Measured cost: 24,821 refreshes and 24.8 GB of
   title memory a frame with `0 skipped`. The layer already collects the per-frame *written* set
   (`Batch::texture_due`, deduped, `host.rs:5358`) and already resolves what each draw's
   descriptors *read* (`draw.rs`'s `readable`/`used`). The step stream is executed at flush time,
   i.e. after every draw has been recorded, so the read set is known when `Step::Texture` runs:
   refresh there only if the staging is in that frame's read set. Expect the 109–977 ms of
   texture work to fall towards the tens of milliseconds; keep `VICTORY_TEXTURE_REFRESH_EVERY` as
   the fallback for anything not in the set.
2. **Copy only what the frame reads.** 70–112 MB of title copies and 33–53 MB of copy-back a
   frame, about 120–170 ms. `VICTORY_COPY_MODE=none` proves they are load-bearing (the picture is
   black without them), so the saving must be selective — the same read set as step 1, with the
   copy-back deferred until the title actually reads the memory.
3. **The draws and the heap pass.** 896–2,919 draws a frame, 80–1,512 dropped for want of a host
   pipeline, and a heap pass of 904 ms that appears on some frames. The refusals on the card are
   *not* wave64 (that is WARP's); with `VICTORY_D3D12_DEBUG=1` and the now-logged
   `log_messages()` output, each refusal names its own reason — start there.

## How to tell whether a change worked

```powershell
# the story on the card, with whatever switches the change needs
.\tools\drive_card.ps1 -Tag try1 -Seconds 420 -Seed `
  -Script ((60..285 | ForEach-Object { "$_:Up,$($_+1):Enter,$($_+2):Up,$($_+3):Enter,$($_+4):Down,$($_+5):Down,$($_+6):Enter" }) -join ',')

# then read the last frame line out of vlogs\try1.err.log:
#   fps, frame ms, preparing split, draws, dropped — and capture a frame to check the picture.
```

A change is worth keeping when the frame's `preparing` falls and the capture still renders the
story's key art (frame ~2048 is a good check: the "I Run This Town" collage, 4.2 MB as a capture).
