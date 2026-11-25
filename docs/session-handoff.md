# HANDOFF — VIctory（GTA VI Xbox dump）— 2026-11-26 00:30 UTC+8

写给下一个会话：读这一份就能接手，不用翻历史。所有数字都是本机实测，跑过的命令在 §6 可复制。

---

## 1. 一句话状态

**卡上（RTX 4080 SUPER）已经能跑完整个开场**：加载 → 过场动画 → 开场字幕，2.5–7.9 fps，700–900 秒不丢设备、不崩溃。两个 PR 已开给上游 `Marvisak/VIctory`，无冲突，只等维护者批准 CI。认领表 `CLAIMS.md` 停在 13:48 UTC 未更新（**不是我们的问题**），我们的认领等它恢复后自动登记。

---

## 2. 仓库与路径

| 位置 | 角色 | 状态 |
|---|---|---|
| `victory-fork-history/` | **权威仓库**（提交、文档、工具都在这） | `main` = `f43e51d`，工作区干净 |
| `victory-fork/` | **构建树**（只用来编译，历史是旧的） | `CARGO_TARGET_DIR=…\victory-fork\target-b` |
| `VIctory-upstream/` | 上游克隆（备用） | detached / `main` |
| `C:\Windows\Temp\pr-logging` | **PR #2471 的 worktree** | 分支 `gpu/log-refused-pipeline-reason` = `0cd1a79` |
| `C:\Windows\Temp\pr-stride` | **PR #2478 的 worktree** | 分支 `gpu/texture-refresh-stride` = `a6d6afa` |
| `patches/` | 历史 bundle 与说明（旧，已被真 fork 取代） | 可忽略 |

**远端**

| remote（在 `victory-fork-history`） | 指向 |
|---|---|
| `origin` | `fxceless/victory-fork`（上游，**main 已到 `465b94f`**） |
| `owner` | `HoLa-Lee/victory-wave-wide-barriers`（**已改成 `Marvisak/VIctory` 的真 fork**，`fork=true`） |
| `up` | `Marvisak/VIctory`（主仓库，**main = `67e8ae1`**） |

**push 用 token**（classic PAT，写在命令里、不要落盘）：
`git push "https://HoLa-Lee:<TOKEN>@github.com/HoLa-Lee/victory-wave-wide-barriers.git" <branch>:<branch>`
本会话用的 token 在对话里；`owner` remote 的 URL 里也存了一份（要清就 `git remote set-url owner https://github.com/HoLa-Lee/victory-wave-wide-barriers.git`）。

---

## 3. 本会话拿到的成果（按重要性）

### 3.1 卡上世界彻底打通（最大的事）
- **真实按键才能驱动卡上菜单**：`drive_card.ps1` 用 `keybd_event`；`VICTORY_KEYS` 在卡上无效（焦点、投递、pad 轮询、按压时长四项都实测排除）
- **脚本键驱动摇杆**（本会话改的 HLE）：`D/A/W/S` 左摇杆，`L/J/I/K` 右摇杆 —— 没有它过不了 ROCKSTAR 条款页（确认键在勾选前禁用）
- 结果：**加载 → 过场 → 开场字幕**全部渲染，画面已入库：`docs/cutscene-rooftop.png`、`docs/credits-crawl.png`

### 3.2 性能：从 0.1 fps 到 4.5–7.9 fps
| 手段 | 效果 |
|---|---|
| `VICTORY_TEXTURE_SAMPLE_SKIP=1`（4 点指纹跳过未变纹理） | 帧 2333→1211 ms |
| `VICTORY_TEXTURE_REFRESH_EVERY=8`（按地址轮转，8 帧读一次） | 纹理 2655→100 ms（**26×**） |
| 两者合成 **`VICTORY_FAST=1`** | story 中位帧 **1298 ms / 纹理 191 ms / 9 MB** |
| `VICTORY_TEXTURE_STAGE_MB=64`（heap pass 就是 staging 预算） | heap 420.8→139–499 ms |
| 合并上游 `f85101b`（提交线程、copy queue、profiler） | 帧 827→**211–236 ms（4.2–4.7 fps）** |

**对比表在 `docs/world-death.md`（story 阶段中位数，draws≥500）**。

### 3.3 世界之死的定性（三个独立结论）
1. **WARP 上：宿主内存耗尽** —— 工作集 30 秒内 6→18.4 GB（23,962 张宿主纹理 10 GB + 26,167 个 upload buffer 9 GB），`0x887A0005`，而我们自己的分配零 OOM
2. **WARP 不能用来判断世界** —— 458 个 compute 管线被拒，调试层原话：*"wants wave lane count of 64 but maximum wave lane count for device is 4"*；每帧丢 1,935 个 draw 就是这个原因
3. **标题的致命路径**是 `mov dword ptr [0], 0x4d8bd421`，前一步格式化 `ALERT_ERROR_SUPPORT_0x%x`（`tools/disasm_rva.py` 反出来的）

### 3.4 首启谜团解开（原目标 (d) 的答案）
- 进入只查 **`Z:\settings\settings.xml` 是否存在**（0 字节就够；`cloudpers`/`cloudcache` 在进入阶段完全没访问）
- **标题是会提交存档的**：`Player` v4、`SARC0015` 242,992 B、`SettingsProfileSettings` v1 全在磁盘上 —— 所以"每轮退回法律声明页"**不是存档问题**
- 真正卡住的是**条款页**：确认键在勾选前禁用，且需要摇杆才能到那一行

---

## 4. 两个 PR（下一步的主线）

| PR | 标题 | head | 状态 | 内容 |
|---|---|---|---|---|
| **#2471** | GPU: a refused pipeline says what the debug layer answered, before the refusal | `0cd1a79` | open，`mergeable=True`，CI `action_required` | 三处 `log_messages()` 的返回值绑定并打进拒绝警告（+6/−6） |
| **#2478** | GPU: an option to refresh a texture once every N frames | `a6d6afa` | open，`mergeable=True`，CI `action_required` | `VICTORY_TEXTURE_REFRESH_EVERY`，默认 1=原行为（+21/−1，已 rebase 到 `67e8ae1`） |

### #2471 的分诊意见已经处理完（`verdict=needs-work` 两条）
1. **BOM**：`Set-Content -Encoding utf8` 在 PS 5.1 会加 UTF-8 BOM → 已用无 BOM 重写，diff 回到只碰三处调用点
2. **描述不准确**：`Host::log_messages` **本来就把每条 message 写成独立的 `D3D12: …` 警告**，只是返回第一条 → PR 正文与提交信息都已改成"把它放进拒绝行**本身**（原本在之后）"

### 已有第三方验证（#2471）
- `Bj0rnis`：RTX 5070 Ti 144 passed / 2 failed（**既有** #1744 view-heap 基线）/ WARP 146 passed / clippy 0 警告 / 资产政策 182 files ok
- `Vedoxdev123`：RTX 4060 141 passed / 2 failed（同 #1744）

### CI 为什么卡在 `action_required`
GitHub 对**来自 fork 的 workflow** 要求维护者首次批准。**不是我们提交晚、不是代码问题**：`VlREX` 最早的 PR #1792 也是 `action_required`，之后的 PR 就自动跑（批准是按贡献者记的）。`HoLa-Lee` 还没被批过一次。

---

## 5. 项目协作规则（必须遵守，否则 PR 会被拒）

- **协调总表 = 上游 issue #1633**；机器人每 30 分钟读一次，维护 `KevinPratap/VIctory` 的 `forge-status:CLAIMS.md`
  - 语法：`claiming: <ID 或一句话>`、`done: <ID> -> #<PR>`、`release: <ID>`、`finding: <一句话>`
  - **`done:` 必须持有 ID**，否则会被记 "without holding the claim"
  - 非 ID 的词（如 `AI-ASSISTED`、`VICTORY-GPU`）会被拒
- **资产政策（rule #1）**：仓库里**不能有任何来自游戏的东西，包括截图**（`docs/asset-policy.md`）。所以：
  - **我们的 `docs/*.png` 截图绝不能进 PR 分支**（PR 分支从上游 main 的干净 worktree 出）
  - CI 的 `cargo xtask policy` 会检查（我们的 PR 目前 182 files ok）
- **PR 要写"测到了什么"**（测试数、帧时间、字节数），不是"打算做什么"；一个 PR 一个自洽改动

### 我们已发的两条 #1633 评论
- `7165835494`：报到 + 五条实测 + 两个 claim
- `7166001379`：**重叠修正** —— 纹理数字归 `FIND-2`(@aycow)、内存序列归 `GPU-HOST-MEMORY`(@aycow)、#2471 补 `FIND-3`(@makmatvey)；并交接 `claiming: NEW-20`（NVIDIA 世界 TDR，我们有卡有路线）

⚠️ **不要重复别人已认领的**：`FIND-2`（无写监视纹理的整张哈希）、`NEW-5`（refresh merge 建索引 PR #1556）、`GPU-HOST-MEMORY`（宿主内存上限）、`FIND-3`（管线裁定标适配器）。

---

## 6. 复现路线（复制即可）

```powershell
# 卡上跑到过场/字幕（约 10 分钟）
.\victory-fork-history\tools\drive_card.ps1 -Tag run1 -Seconds 700 -Seed -Script `
  ((40..100 | ForEach-Object { "$_:Up,$($_+1):Enter,$($_+2):Up,$($_+3):Enter,$($_+4):Down,$($_+5):Down,$($_+6):Enter" }) -join ',')`
  + ",108:S,115:Enter,128:Enter"
$env:VICTORY_FAST            = "1"
$env:VICTORY_TEXTURE_STAGE_MB = "64"
```

键序说明：**40–100 s 七键循环**过前置页 → **108 s 按 `S`**（左摇杆下移聚焦到服务条款行）→ **115/128 s 按 `Enter`**（勾选、确认）→ 之后每拍需要一次 `Enter` 才会前进。

> 帧率变化后**键序时间点必须重算**（合并 `f85101b` 后页面来得快 3–4 倍）。理想做法：把触发改成**按帧号**而不是按秒（未做）。

编译：
```powershell
$env:INCLUDE/$env:LIB/$env:PATH  ← MSVC 14.44.35207 + SDK 10.0.26100.0
$env:CARGO_TARGET_DIR = "…\victory-fork\target-b"
cargo build --profile diag -p victory --features diagnostics
```

---

## 7. 工具（`victory-fork-history/tools/`）

| 工具 | 用途 |
|---|---|
| `drive_card.ps1` | 卡上真实按键驱动（`-Tag -Seconds -Seed -Script`） |
| `world_ram.ps1` | 每 10 秒采样空闲内存/工作集，打印层的内存行与失败点 |
| `frame_stats.ps1` | 从日志算**可比**的帧统计（`-MinDraws 500` 去掉菜单噪声） |
| `disasm_rva.py` | 用 capstone 反汇编缓存镜像的 RVA，并解析 RIP 相对字符串（需要 `pip install capstone`） |

---

## 8. 关键测量数字（引用时直接用）

| 项 | 数值 |
|---|---|
| 无优化基线（story 阶段中位） | 帧 3,211 ms，纹理 2,655 ms / 372 MB |
| `VICTORY_FAST=1` + `STAGE_MB=64` | 帧 703–1,298 ms，纹理 100–191 ms / 9 MB，**2.5–7.9 fps** |
| 合并 `f85101b` 后 | 帧 **211–236 ms（4.2–4.7 fps）**，纹理 0.1–0.2 ms |
| 纹理刷新（未优化时） | **24,821 次/帧、24.8 GB、`0 skipped`**，6,814 ms 在等标题内存 |
| 被写字节占整张 detile | **13–23%**（24,036,172 / 105,238,272） |
| heap pass / staging 预算 | 192 MB → 420.8 ms；64 MB → 139–499 ms；32 MB → 111–224 ms |
| 世界之死（WARP） | 211–227 s 移除；此前 6/6 复现，离散 16 s |
| 卡上稳定性 | 700–900 s，**0 移除 0 陷阱** |
| 测试 | `cargo test --workspace --lib --profile diag --features diagnostics` → **547 通过**（合并时点） |

---

## 9. 待推进（按优先级）

1. **盯两个 PR**：等 CI 批准/评审；若分诊再给 `needs-work`，按条目改（流程：改 worktree → `cargo check -p victory-gpu --profile diag --features diagnostics` → `commit --amend` → `push --force` → `PATCH /pulls/<n>` 更新正文）
2. **等 `CLAIMS.md` 恢复**（最后更新 13:48 UTC，已停摆 2h+；监控脚本模式见 §10），出现 `HoLa-Lee` 就补 `done: <ID> -> #2478` / `-> #2471`
3. **认领的执行**：`NEW-20`（NVIDIA 世界 TDR）—— 我们有硬件与路线；做法是在基线上逐个测开放 PR，报告哪个改变 TDR（对照：改前 6/6 死、改后 700–900 秒活）
4. **可选新 PR 候选**（上游确认没有）：`VICTORY_TEXTURE_SAMPLE_SKIP`（4 点指纹）；但注意它与 `FIND-2` 重叠，**优先交给 @aycow 而不是另开 PR**
5. **上游新提交**：`fxceless` 已到 `465b94f`（比我们合并的 `f85101b` 新），`Marvisak` 到 `67e8ae1`；有性能/渲染类的新提交就**先合并再测**
6. **未做的技术改进**：`drive_card.ps1` 按键改按帧号；按页 detile 的 `walk` 裁剪；copy-back（每帧 90–150 ms）用上游 `VICTORY_DRIVER_WATCH` 预判丢设备

---

## 10. 踩过的坑（省下一个会话两小时）

| 坑 | 现象 | 解法 |
|---|---|---|
| **PS 5.1 写文件带 BOM** | PR 里"第 1 行也变了"，分诊判 needs-work | 用 `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))` |
| `git commit -m "多行"` 被拆参数 | `pathspec 'world' did not match` | 消息写文件，`git commit -F file` |
| `git add -A` 把临时文件提交进去 | PR 多出 `commitmsg.txt` | commit 前 `git status`，或把它加进 `.git/info/exclude` |
| `Invoke-RestMethod` POST 中文/长文本报 400 | "Problems parsing JSON" | body 用 `[Text.Encoding]::UTF8.GetBytes($json)` + `charset=utf-8` |
| `cd $env:TEMP\...` 后路径错 | 文件找不到（落在会话工作区） | worktree 在 `C:\Windows\Temp\...`，用**绝对路径**或在命令里显式 `cd` 后校验 |
| `keybd_event` 需要前台 | 键没反应 | `SetForegroundWindow($p.MainWindowHandle)` 后再 Tap |
| 抓帧本身掉帧 | 每 8 帧一次 dip | 上游 `a253706`：抓一帧在 present 里要 235 ms；用 `VICTORY_CAPTURE_WORLD_EVERY` 控频 |
| 帧率变了键序就失效 | 卡在设置页 | 重新对表（或改按帧号） |
| `fxceless` 分支删了 `indirect::done` | 合并后编译失败 | 删掉我们那两处 `crate::indirect::done(...)` 调用 |
| 上游重写 `refresh()` 为 `Option<Upload>` | rebase 冲突 | 保留新契约，`if !self.due() { return None; }` |

---

## 11. 文档索引

| 文件 | 内容 |
|---|---|
| `docs/world-death.md`（63 KB） | **主记录**：排除表、时间表、反汇编、内存采样、各配置对照表、"怎么跑" |
| `docs/next-steps.md` | 剩余工作与判据 |
| `docs/value-vs-upstream.md` | 逐组判断我们的提交价值、该发给哪个 issue |
| `docs/asset-policy.md`（上游） | **截图不能进仓库/PR** |
| `tools/*` | 四个工具（见 §7） |

## 12. 不要做的事

- 不要再用 `VICTORY_KEYS` 驱动卡上菜单（无效；用 `drive_card.ps1`）
- 不要在 WARP 上判断世界正确性（wave64 不存在）
- 不要把 `docs/*.png` 截图放进 PR 分支（资产政策）
- 不要重复认领 `FIND-2` / `NEW-5` / `GPU-HOST-MEMORY` / `FIND-3`
- 不要自己批 CI（无权限），也不要以为 `action_required` 是代码问题
- 不要再往 `Z:\` 塞文件试图"修好首启"（已定论：那是条款页，不是设置/存档）

---

## 13. 更新（2026-11-26 00:40，写在这份 handoff 之后）

- **上游最新两笔已经合并**：`3973179`（逐帧构成测量、parts 合并、copy-back 走自己的 view，9.6 fps）+ `465b94f`（散乱间接记录每 list 只 clamp 一次，`VICTORY_INDIRECT_GATHER=1`，10.3 fps）
  → 本地与远端 main 都是 **`36b1207`**，`cargo check -p victory-gpu` 通过
  → **新会话不要再合并一次**；下一步是**验证**：`VICTORY_FAST=1` + `VICTORY_TEXTURE_STAGE_MB=64` + `VICTORY_INDIRECT_GATHER=1` 跑一次卡上，看 4.5 fps 能否往 8–10 fps 靠
- 冲突解决方式（供理解改动）：`draw.rs` 取了上游的 jump-window 块（我们的"提交时刷新参数"实验无效果）；`host.rs` 保留上游 `present`/`present_now` 拆分并把 present trace 的地址贯穿进去；`Held::Present` 扩成 4 字段；删掉上游已废弃的 `crate::indirect::done`
- `CLAIMS.md` 仍停在 `sha=5d4c495 / last_comment=7164183778`（13:48 UTC 之后未更新）；我们 14:54 UTC 的两条评论仍未登记

## 14. 验证跑结果（2026-11-26 00:53，合并 `36b1207` 之后）

命令：`VICTORY_FAST=1` + `VICTORY_TEXTURE_STAGE_MB=64` + **`VICTORY_INDIRECT_GATHER=1`**，卡上 700 秒，§6 的键序。

```
4.2 fps, 239.1 ms（preparing 84.5：copies 55.2 ms 135.9 MB，textures 0.2 ms 0.1 MB；
  GPU 118.2 ms；回拷 178.3 ms 69.9 MB）4035 draws，丢 267
4.1 fps, 243.9 ms（copies 63.4 ms 172.6 MB；GPU 126.8 ms；回拷 182.8 ms 66.8 MB）4933 draws
4.2 fps, 238.5 ms（copies 72.8 ms 170.6 MB；GPU  94.1 ms；回拷 135.2 ms 63.0 MB）5555 draws
4.2 fps, 239.0 ms（copies 71.6 ms 192.2 MB；GPU 107.7 ms；回拷 183.3 ms 69.4 MB）5645 draws
```

**结论：`VICTORY_INDIRECT_GATHER=1` 在我们这张卡/这个场景上没有改变帧率**（合并前 4.2–4.7 fps / 211–236 ms，现在 4.1–4.2 fps / 238–244 ms，属于同一区间）。上游报的 10.3 fps 是 RTX 4070 的"第一个房间"，我们这里的 draws 是 **4,035–5,645**，场景更重。

**帧的构成已经换了位置**：

| 项 | 现在 | 之前 |
|---|---|---|
| 回拷 | **135–183 ms（63–70 MB）← 最大项** | 125–158 ms |
| GPU | 94–127 ms | 89–115 ms |
| copies | 55–73 ms（136–192 MB） | 37–74 ms |
| textures | **0.1–0.3 ms** | 0.1–0.2 ms |

所以下一处该攻的是 **copy-back**（每帧 60–70 MB 花 135–183 ms，约 2–3 ms/MB，是延迟不是带宽）。上游 `a253706` 的 `VICTORY_DRIVER_WATCH` 能提前 2.7–55 秒预告丢设备，可作为这项工作的工具。

抓帧：`frame-5000.png` = 3,066,463 字节（过场画面，完整）。

**状态**：`story 7 / world 8`，700 秒存活，**0 丢设备 0 陷阱**。

---

## 15. 社区情报（2026-11-26 01:20，来自 gta6pconline.com 的跟踪器与其 GitHub 链接）

站点是独立跟踪器（每小时扫仓库、每小时查 GitHub DMCA 日志）。全局：**0 个项目可玩**，36 个努力收录 9 个，评分是 6 阶段（Boot→Menu→Load→World→Move→Play），**75% ≠ 75% 可玩**。三条技术路线：兼容层（我们这条最快出画面）、静态重编译（five-star-recomp 等）、模拟器。

### 15.1 立刻要动的一个风险（已处理一半）

Take-Two 在 **11-24** 发了首份 GTA VI DMCA：`ItsNotRexed/Leonida` **连同 3,007 个 fork 被关**；`VIctory`、`XCL`、`five-star-recomp` 未被点名，仍在线；`fablinoo/palmwave`、`LeonidaReforge/Leonida` 已 404。
→ 我们的 fork 里原有 6 张**游戏截图**（过场、字幕、加载星），**违反上游 `docs/asset-policy.md` 第 1 条**。
→ **已处理**：图片移出仓库（`screenshots-local/` 留在本机），docs 里的引用改成按名字提及，**仓库现在 0 张图片**（只剩 `bcpack-tables.bin` 这个官方例外）。
→ **仍未处理**：**历史提交里还有**。若要彻底清除需 `git filter-repo` 重写全部 hash 并强推（PR #2471/#2478 基于上游 main，不受影响）。操作者决定是否做。

### 15.2 四个值得抄的方向（按价值）

**① paired-wave64：`fxceless/victory-fork` PR #854（open，23 文件 +4587/−1332）**
> 32-lane GPU 上把 wave64 程序**成对**翻译；230 个原本翻译失败的程序通过；36 个原本"按半宽近似"的 compute 现在算出 64 lane 的结果
> Compute 通过 2,695→**2,729**（失败 39→5）；Mesh 8,657→8,694（失败 108→71）

Flamingo fork 合并后自称 **"no pipeline refused"**。
👉 **这是我们在 WARP 上看到 458 次 wave64 拒绝的解法**。合并它之后，WARP 世界才第一次"可以被判断"。

**② 开放世界丢设备的嫌疑：光线追踪 compute 管线 —— `ThatRecompDev/five-star-recomp`（★217，全场最高）**
> 把 **RT compute pass 的管线做成 stand-in（除非 `--raytracing`）**，止住了"进世界 25–35 秒必丢设备"，跑出**首次 18 分钟世界无移除**

👉 与该项目的静态重编译路线无关，这个"先禁用某类管线再测"的方法可以照搬到我们的基线上（我们已有"改前 6/6 死、改后 700–900 秒活"的对照）。

**③ VRAM 满时回退更小 mip —— `ka1qux/BRVIctory-ka1qux`（★76）**
README 写明 **"smaller-mip fallback when VRAM fills"**；最新提交 "ray tracing is on by default（`VICTORY_RAYS=0` 关）"、守卫块改成位集 + 1 MiB 区域。
👉 我们量到的"纹理双份 10 GB"问题的**社区临时解法**，可作为有预算缓存实现前的缓解。

**④ 开放世界的现实帧率参照 —— `PastiiJay/klbf-lab`（★83）**
RX 9070 XT：**开放世界自由行走 5–8 fps**（77 分钟），从新游戏玩到第二个任务（"Gone Fishing"），日夜循环可用。
👉 我们的 4.2 fps（4,035–5,645 draws）与它同量级；上游 9.6 fps 是 3,850 draws 的第一个房间。

### 15.3 其它值得知道的仓库

| 仓库 | ★ | 一句话 |
|---|---|---|
| `realblastex/flamingo` | 14 | victory-fork 的调优 fork，24 分钟跑 8.6 fps 平均、零拒管线、**合并了 PR #854** |
| `pragyaangaur/VIctory-macOS` | — | CrossOver + D3DMetal，M5 Pro 世界帧 2.4–2.9 s |
| `Belobug/VIctory-Belobug-AMD` | — | RX 9070 XT 亮世界 3–5 fps，深度环境光 + 并行回拷 |
| `DexNom/VIctory` | 10 | RX 7900 XTX 室内 3.52–4.05 fps；`--rt` 实验测得 969 ms/帧 |
| `LooperSalty/AnyXboxX` | — | 模拟器 + 捆绑 VIctory 运行时，Win 4.8–6.9 fps |
| `xcl-dev/xcl` | — | 菜单 30 fps，NVIDIA 未合并分支世界 ~5 fps（RTX 5090） |
| `R0Y00/Xbox2Windows` | — | 静态重编译到 C++/DXIL，仅到加载 |
| `Maybox2Windows`/`PercyScarlett`/`OpenScarlett` | — | 兼容层，首屏/亮过场 2–3 fps |

### 15.4 对我们"30 fps 时间表"的修正输入

- 现在**全网最好的"第一个房间"是 9.6–10.3 fps（≈100 ms）**，我们的卡上是 4.2 fps（238 ms，场景更重）
- **开放世界最好成绩是 5–8 fps**（klbf-lab，RX 9070 XT）
- 因此上一轮推算里"开放世界 10–20 fps 需 3–5 周"仍成立，但**"全游 30 fps"的瓶颈现在更明确地落在：paired-wave64（正确性）+ RT 管线（稳定性）+ 纹理内存（长跑）**这三件的组合上，而不是单点优化
