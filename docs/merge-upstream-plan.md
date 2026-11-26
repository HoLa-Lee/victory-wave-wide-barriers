# Merging `marvisak/main` into this tree: 61 conflicted files, in the order they should be taken

Written 2026-11-26 from a dry merge (`git merge-tree --write-tree main marvisak/main`), merge
base `ffe310e`. Every number below is the count of commits each side made to that file since
the base (`git log --oneline ffe310e..main -- <file>` and the same for `marvisak/main`).

The point of the order: the files where one side barely moved can be settled by reading one
diff, and the five heavy ones last, each behind a compile-and-test gate of its own.

## Stage 0 - no judgement needed (build files, one commit each side)

| file | ours | theirs |
|---|---|---|
| `crates/victory-loader/Cargo.toml` | 1 | 1 |
| `crates/victory-shader/build.rs` | 1 | 1 |

Both are dependency/flag lines: keep both sides' additions unless they name the same crate.

## Stage 1 - one side only (take the larger side whole, after reading the smaller one)

| file | ours | theirs |
|---|---|---|
| `crates/victory-shader/src/emit/diff_tests.rs` | 1 | 10 |
| `crates/victory-shader/src/emit/container.rs` | 1 | 4 |
| `crates/victory-game/src/sgd5.rs` | 1 | 2 |
| `crates/victory-shader/src/emit/waterfall_tests.rs` | 1 | 7 |
| `crates/victory-shader/src/io.rs` | 1 | 4 |
| `crates/victory-shader/src/native.rs` | 1 | 3 |
| `crates/victory-gpu/src/memory.rs` | 1 | 10 |

Our one commit in each of these is from the fork merge; what it did is readable in a minute.
`memory.rs` is the exception worth care: our side's single commit there is the write-watch
work, and theirs is ten commits of descriptor/heap work - read ours first, then take theirs
and re-apply ours on top.

## Stage 2 - both sides moved, but little (≤ 8 commits each)

`device.rs` (5/2), `indirect.rs` (7/2), `audio.rs` (2/6), `emit/bitcode.rs` (2/6), `run.rs`
(2/12), `main.rs` (2/10), `structure.rs` (2/13), `primitive.rs` (2/4), `emit/rect.rs` (2/2),
`victory-shader/src/resource.rs` (3/8), `emit/wave.rs` (3/4), `pipeline/make.rs` (4/3),
`pipeline/library.rs` (3/9), `frame.rs` (3/5), `emit/host.rs` (3/16), `victory-gpu/Cargo.toml`
(3/3), `fence.rs` (3/3), `modules/files.rs` (4/3), `pipeline.rs` (4/9),
`victory-formats/src/texture.rs` (4/9), `emit/valu_tests.rs` (4/34), `emit/shader.rs` (4/12),
`modules/dstorage.rs` (7/4), `modules/gameinput.rs` (8/4), `modules/xmem.rs` (5/7),
`shader_cache.rs` (5/5), `victory-gpu/src/lib.rs` (5/12), `pipeline/host.rs` (5/12),
`ir.rs` (5/7).

Per file: `git log -p ffe310e..main -- <file>` and the same for theirs, then merge by hand.
Gate: `cargo check -p victory-shader` (the shader files) or `-p victory-gpu`, then
`cargo test -p <crate> --lib` before moving on.

## Stage 3 - both sides rewrote the same thing (do these last, one at a time)

| file | ours | theirs | why it is hard |
|---|---|---|---|
| `crates/victory-gpu/src/host.rs` | **29** | **55** | the frame, the submission, the copy-back: the busiest file on both sides |
| `crates/victory-gpu/src/draw.rs` | 25 | 36 | the draw path and the view heap |
| `crates/victory-gpu/src/texture.rs` | 22 | 23 | the staging/refresh path - and our stride switch lives here |
| `crates/victory-gpu/src/descriptor/host.rs` | 18 | 32 | the view heap and its cap (FIND-9's subject) |
| `crates/victory-gpu/src/shadow.rs` | 16 | 25 | host copies and the copy-back (FIND-14's subject) |
| `crates/victory-shader/src/emit/lower.rs` | 13 | **71** | the translator's largest file, and theirs moved it a long way |

Before starting one of these, decide what "ours" is even for: most of our commits in them are
the fork's (fxceless's line), and upstream main has since solved some of the same problems
differently - `a7cb47c` (integer-target blend) and `#2612` (remap during a pending copy-back)
are two we already met. Prefer upstream's version wherever it covers the same ground; keep ours
only where it does something upstream still does not.

## Rules that cost a session each time they are forgotten

- **Never `git add -A`** in these worktrees. Stage the files you resolved, by name.
- **Rebase onto `marvisak/main` before opening or updating a PR** to it, or the diff shows
  upstream's own work as deletions (this happened to #2892 on 2026-11-26).
- **Push before the network window closes**: github.com's HTTPS refuses connections from this
  machine for minutes at a time while api.github.com stays up; retry, do not rewrite the branch.
- Keep `victory-fork/target-b` (the card build tree) out of the merge. It is a scratch tree with
  its own history; the merge happens in a worktree of `victory-fork-history`.

## Correction after trying it (2026-11-26 16:00)

The file-by-file order above is not a valid unit of work, and this session learned
it the cheap way: after resolving `emit/diff_tests.rs`, `emit/container.rs`,
`io.rs` and `native.rs` by taking upstream's side and re-applying ours with
`git apply --3way`, the crate cannot compile, because the two sides **renamed the
same things in different files**. One example, from `container.rs`: our side has
`Psv { gs: Option<u32> }`, upstream has `Psv { geometry: Option<u32> }`, and the
field is set from `lower.rs` - a file further down the list. Resolving the struct
without the setter renames the crate into a state that no `cargo check` can pass.

So the unit of work is **a whole crate brought to a compiling, testing state**, not
a file:

1. Take upstream's side for every file of the crate (`git checkout marvisak/main -- <crate dir>`).
2. Re-apply our side's semantic changes file by file as diffs against the base
   (`git diff ffe310e..main -- <file>`), in the order the compiler complains.
3. Gate: `cargo test -p <crate> --lib` on the merged crate before touching the next one.
4. Order of crates: `victory-shader` first (it is the deepest and the most renamed),
   then `victory-formats`, `victory-gpu`, `victory-hle`, `apps/victory`, then the docs.

Budget honestly: `victory-shader` alone is 2-4 hours in one sitting (13 of our commits
against 71 of theirs in `lower.rs`), and `victory-gpu` is larger. This is not a
30-minute-slice job, and starting it in slices leaves a worktree that cannot compile
and cannot be committed.

The worktree `C:\Windows\Temp\merge-up` was reset to `4448167` after the attempt; the
four resolved files were kept as diffs in `C:\Windows\Temp\*.patch` for the next
person to reuse (`crates_victory-shader_src_emit_container.rs.patch` and its two
siblings), and `diff_tests.rs`'s only change was the naming (4 occurrences of the
game's name turned into "the title").
