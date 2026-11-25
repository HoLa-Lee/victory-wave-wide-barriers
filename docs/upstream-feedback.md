# What this branch can tell upstream (ready to paste)

Three findings, each with the log line it comes from and the run it was seen in. Everything
below was measured on one machine (i5-12600KF, 32 GB, RTX 4080 SUPER 16 GB, driver
32.0.16.1742, Windows 11 26200) with the same dump every report in this repository uses
(BLAKE3 `b99f876b74d4a77f03af5f878223b27bd647b5c35a79d5decd9f716504239e93`), `diag` builds,
a fresh data folder per run.

## 1. `0x887A0004` in a device-loss line is not a capability — it is DRED being off

A hardware run without `VICTORY_D3D12_DRED` prints:

```
host GPU device removed after a submission of 1 lists; no breadcrumbs (… 0x887A0004); device removed: … 0x887A0001
```

`0x887A0004` there is what `GetAutoBreadcrumbsOutput` returns when device-removed data was
never enabled (`host.rs`'s `removal_data` asks only after the device casts to
`ID3D12DeviceRemovedExtendedData1`, which a device that never got the DRED settings still
does). With `VICTORY_D3D12_DRED=1` the same removal reads `breadcrumbs (done/count, list) []`
and no `0x887A0004` appears anywhere in the run. The removal's own reason is the second
HRESULT: `0x887A0001` on the card. `GetDeviceRemovedReason` never said "unsupported".

So a report that reads "`DXGI_ERROR_UNSUPPORTED` means the driver refused a capability" is
reading the wrong HRESULT. Check `VICTORY_D3D12_DRED=1` before drawing a conclusion from a
removal line.

## 2. The `title slot past the host heap` warning costs a frame — 6.5 s of one

`descriptor::host::mirror` warns once per new highest slot past the host heap. Because the
sweep walks the title's ring in increasing order, the first submission prints **310,720** of
them (1,245,184 − 934,464 on a card whose view heap is capped at 1,000,000). On `644ebeb`
that showed up as:

```
frame  2: 0.1 fps, 6704.6 ms/frame (6454.3 preparing … 3.0 on the GPU)
frames 4, 8, 16, 32, 64: 33 ms each
```

310,720 × ~21 µs ≈ 6.5 s — the warning itself is the frame, not the card. WARP prints none
(its heap holds the whole 1,245,184 slots) and looks fast for that reason. "The card is 150x
slower than the software adapter" is this one submission.

## 3. `644ebeb` still loses the device on this card, where the fork's base does not

Same dump, same card, same menus, `VICTORY_D3D12_DRED=1`, 35–40 s each, fresh data folder:

| tree | rate | draws | device |
|---|---|---|---|
| `70564ae` | 0.1–0.2 fps, 6,300–6,700 ms/frame | 2 | lost at ~7 s, `0x887A0001` + `[]` breadcrumbs |
| `644ebeb` | 6,454 ms for frame 2, then 33 ms | 2 → 21 | lost at ~18 s, `0x887A0001` + `[]` |
| `2119b0e` (this branch's base) | 30.0 fps, 31–33 ms/frame | 21 | none in 40 s, with and without `VICTORY_WAVE_WIDE=1` |
| same, WARP | 21–30 fps | 21 | none |

`2119b0e`'s merge base **is** `70564ae`; the fork is 225 commits ahead and one of them is
`e9765a7 Fix the device loss introduced by the wave64 update`, so the loss this branch does
not show was fixed there. Whatever `644ebeb` still does on this card is worth a look from
whoever owns #101.

## Bonus: the first-run flow does finish, and `settings.xml` is the file that says so

A fresh data folder gets `CreateDirectoryW` on `Z:\settings\` and nothing inside it; a folder
seeded with the `settings.xml` the flow writes gets `GetFileAttributesW` then `CreateFileW` on
that file four seconds in, and no setup page at all. `XGameSave` is asked for
(`create_container container=SettingsProfileSettings`, then `create_update`) and the title
opens `pack\story000_restofworld\story000_restofworld.rpf`.

The key mapping matters when scripting it: `gameinput::FALLBACK_BUTTONS` has no letter `A`;
the pad's `A` is `Enter` (`(0x0D, A)`), so a `VICTORY_KEYS` script written with `…:A` presses
nothing and the flow sits on the setup pages forever — which reads exactly like "it never
saves". With `Enter`: language, legal notices (`Down Down Enter`), terms (`Up Enter Up Enter
Down Down Enter`), brightness, finish setup.
