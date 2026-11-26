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

### 15.5 全游 30 fps 的重估（2026-11-26 01:35，替换 15.4 里的旧推算）

坐标：exe 放出约 **59 小时**；**没有任何项目到第 5 步（Move）**；开放世界最好 **5–8 fps**。

**预算**：30 fps = 33.3 ms/帧。现状差距：第一个房间 9.6–10.3 fps（≈100 ms，**需 3×**）、我们的过场 4.2 fps/238 ms（需 7×）、开放世界街道 2.4 fps/420 ms（需 **12×**）、自由行走 5–8 fps（需 4–6×）。**3× 还是最轻场景 + 最强卡的数**。

| 里程碑 | 乐观 | **中位** | 悲观 | 依据 |
|---|---|---|---|---|
| 开放世界 20 分钟不丢设备 | 3–7 天 | **1–2 周** | 3–4 周 | five-star 给出"RT compute 管线"这条线索；`victory-fork` 线仍未归因 |
| 开放世界 ≥10 fps 且光影基本正确 | 2–3 周 | **4–6 周** | 2–3 个月 | **修光影会先抵消一部分优化收益** |
| 城市内稳定 20 fps | 4–6 周 | **2–3 个月** | 4–5 个月 | 需 GPU 侧 2× 真实优化 |
| **全游稳定 30 fps** | **6–10 周** | **3–4 个月** | **6 个月+** | 长尾（任务/过场/流式/存档）完全未知 |

**上调中位的四个理由**
1. 最好成绩 10 fps 出现在最轻场景；开放世界还要再乘 2–3×
2. **正确性欠账是普遍的**（阴影黑、区域黑、recomp 那条线 composite red-only），修它要花 GPU 预算 → 先掉帧
3. 全游场景无一项被验证（无人越过 Move）
4. DMCA 风险会随机削产能（`Leonida` 连带 3,007 fork 已消失）

**加速判据**：出现 ≥15 fps + 光影正确 + 20 分钟以上的开放世界录像；PR #854 类修复合并且**拒绝程序接近 0**（现仍有 ~76）；出现**有预算的纹理缓存**（不是 mip 回退）。
**减速判据**：开放世界丢设备在 `victory-fork` 线仍无归因；再吃一次 DMCA；30 fps 只在 4090/5090 达标。

### 15.6 认领机器人已停摆（实测）

`KevinPratap/VIctory` 的 `forge-status` 分支最后提交：

```
660578e  2026-11-25T13:48:27Z  Claims 2026-11-25 13:48 UTC   ← 最后一次
cc940a4  2026-11-25T06:24:11Z  Forge status …
```

从 13:48 UTC 到现在（01:35 +08:00 = 17:35 UTC）**约 3 小时 47 分**没有新提交，期间监控 14 次（00:24–01:30，每 5 分钟）全部 `sha=5d4c495 / last_comment=7164183778` 无变化。
→ **我们的 `claiming:` 与 `finding:` 两条评论（14:54 UTC）仍在队列里**，不是格式问题。**不需要我们做任何事**；等它恢复会一次性处理积压（`BaggyALPHA` 在同一线程也抱怨过这个滞后）。

## 16. 与上游协作：已发的三条与 FIND-20 的实测（2026-11-26 02:00）

### 16.1 已发到 #1633 的评论

| 评论 | 内容 |
|---|---|
| `7165835494` | 报到 + 五条实测 + 两个 claim |
| `7166001379` | 重叠修正（纹理数字归 `FIND-2`、内存归 `GPU-HOST-MEMORY`、#2471 补 `FIND-3`）+ `claiming: NEW-20` |
| **`7169959253`** | **把测量挂到已有任务下**（`GPU-SNAPSHOT-COST`：回拷 135–183 ms/63–70 MB、2–3 ms/MB、GATHER 无效、copies 无相邻可合并；`FIND-2`：被写字节占 13–23%、每帧 24,821 次/24.8 GB、`0 skipped`；粒度应为 64 KiB 页掩码）+ **`claiming: FIND-20`** |

### 16.2 为什么之前没被处理（**不是我们的格式**）

`KevinPratap/VIctory`（bot 仓库）的 `default_branch = forge-status`；`claims.yml` 只在这条分支上，cron `*/30`。
**Claims 工作流最后一次运行 = 13:48:09Z（success），之后再无运行**；而 **16:03Z 有人推了新分支 `xtask/forge-and-claims`**，新版 bot 把触发改成 `issue_comment:[created,edited,deleted]` —— 即在迁移中，还没落到默认分支。
另外查了 bot 源码 `xtask/src/claims.rs`：`is_id` **要求至少一个连字符**（`GPU` 不是 ID，`GPU-BLACK-WORLD` 是），所以以 `GPU ...` 开头的 `claiming:` 会被当成 one-line claim，不是格式错误。

### 16.3 `FIND-20`（并行下 flaky 的 watch 测试）实测结论

**复现**：`cargo test -p victory-gpu --lib --profile diag --features diagnostics`（默认并行）
- 全量套件：约 **1/8–1/14** 次失败
- **把 `warp_*` 测试集中跑（8 线程，20 次）：8 次失败（40%）** ← 集中后放大
- **失败点会漂移**：`inplace::tests::warp_a_title_buffer_in_place_shows_its_bytes_at_its_offset`（`inplace.rs:1387`，`VirtualFree(MEM_DECOMMIT)` 返回 0）或 `indirect::tests::warp_budget_saturates_without_wraparound_and_preserves_draw_fields`（`indirect.rs:1833`，`assert_eq!(spent, BUDGET_CAP)`）

**结论**：不是某一个测试的 bug，而是**基于 WARP 的测试之间争用进程级 `OnceLock` 缓存**（`indirect::CLAMP`、`inplace` 的 device/rig 缓存等）—— 谁先初始化/谁先释放，另一个就失败。`--test-threads=1` 时未观察到失败。

**下一步（PR 方案，未做）**：
1. 一个 test-only `Mutex` 把 WARP 设备测试串行化（`inplace`、`indirect` 的 warp 测试、`texture::title_memory_tests`）
2. 在 `inplace.rs:1387` 的断言里带 `GetLastError`（区分 `ERROR_INVALID_ADDRESS` 与 `ERROR_BUSY`），让 CI 日志直接说出原因
3. 汇报时把"watch 测试 flaky"更正为"WARP 设备测试互相争用"

### 16.4 FIND-20 追到底：**没有发 PR，因为假设被自己证伪**

写 PR 之前先验证，结果**锁不是解药**：

| 实验 | 结果 |
|---|---|
| 加 test-only mutex（`lib.rs` 的 `test_sync::WARP`）+ 18 个 `warp_*` 测试各持锁 | **16/20 仍失败**（无锁时 15/20）→ **并发假设证伪** |
| 每次跑前删 `%LOCALAPPDATA%\D3DSCache` | 3/4 失败；不删则 2/3 通过 → **着色器缓存假设证伪** |
| 检查是否"没等 GPU" | 两套 Rig 都已 `Signal` + `SetEventOnCompletion` + `WaitForSingleObject` → **假设证伪** |
| **单测独跑（`--test-threads=1`）** | **约 3/4 失败** → **是每进程随机，不是并发** |

**真正失败的断言**（都是"GPU 写出来的值"）：
- `inplace.rs:1387`：`VirtualFree(base+2*K64, K64, MEM_DECOMMIT)` 返回 0
- `indirect.rs:1833`：`assert_eq!(spent, BUDGET_CAP)`，读回 **0**

**重要事实**：这些测试**不在 `Marvisak/VIctory` 的 main 上**（`inplace.rs` 与 `warp_*` 测试来自 fork 那条线），所以修它应该提给 fork，而不是 main。

**已发更正**（`#1633#issuecomment-7171829690`）：FIND-20 的描述要改成"不是 watch 测试、不是并发"；下一步是**在断言处打印 GPU 到底返回了什么**（`spent`/`out_words` 的五个字 + `GetLastError`），并核对 `indirect` 的 rig 是否在某些运行里用了**非 WARP 适配器**（"每进程 60–75%"的失败率更像"用错了设备/管线"，不像竞争）。

**未用的补丁**：`C:\Windows\Temp\pr-warp`（d510ee4）与 `pr-warp-465`（465b94f）两个 worktree 里都有"加锁 + decommit 带 GetLastError"的改动，**没有推送** —— 留作下次继续的起点。

---

## 17. 读这份 handoff 前必看：§1–§14 里已过时的四个点（2026-11-26 03:15 校正）

| 位置 | 过时内容 | 现在的事实 |
|---|---|---|
| §2 仓库状态 | `main = f43e51d` | **`main = 9fe6156`**（远端 owner 同为 `9fe6156`） |
| §2 上游 | `Marvisak main = 67e8ae1`、`fxceless main = 465b94f`（已合并成 36b1207） | **`Marvisak main = 13f91ca`**、**`fxceless main = d510ee4`**（两者都又前进了；36b1207 之后我们只做过文档提交） |
| §2 worktree | 只列了 `pr-logging`、`pr-stride` | 另有 **`C:\Windows\Temp\pr-warp`**（分支 `tests/warp-tests-take-turns`，基于 d510ee4）与 **`pr-warp-465`**（detached 465b94f）—— FIND-20 的未推送补丁在这两个里 |
| §8 测试数 | "547 通过" | 那是某次合并时的全 workspace 数；**`victory-gpu` 单元测试现在是 196 passed / 6 ignored**（含上游新测试），全 workspace 会更多 |

### 另有两件 handoff 里没写、但新会话必须知道的事

1. **push 用的 token 不在文件里**（安全考虑）。命令模板：
   `git push "https://HoLa-Lee:<TOKEN>@github.com/HoLa-Lee/victory-wave-wide-barriers.git" HEAD:main`
   本会话用的是 classic PAT（`ghp_…`，45 字符级），`owner` remote 的 URL 里也存了一份（要清：`git remote set-url owner https://github.com/HoLa-Lee/victory-wave-wide-barriers.git`）。**没有 token 就无法推送**，也无法读 `CLAIMS.md`（需 GitHub API 认证）。
2. **定时任务 `schedule-f4d26af3…`（"继续推进 VIctory 首启流程与上游同步"）是 `paused` 且内容全过时**（还写着 rpcrt4、未推 commit、Z:\settings 调查）。**不要去恢复它**；当前会话靠 goal 轮次推进。

### 还有一条判断口径要继承

`FIND-20` 里那条"不是并发、不是缓存、不是没等 GPU"的结论，是**用三次实验证伪**出来的；同理，本项目里任何"看起来是竞争"的现象，先做**单进程重复**实验再下结论（单测独跑 3/4 失败这一步就推翻了并发的直觉）。

### 17.1 推送用的 token（按操作者要求写在**工作区** HANDOFF，不入库）

```
<TOKEN — kept out of the repository; it lives in the workspace HANDOFF.md only>
```

用法（classic PAT，账户 `HoLa-Lee`，有 repo 作用域）：

```powershell
$token='<TOKEN — kept out of the repository; it lives in the workspace HANDOFF.md only>'
git -C victory-fork-history push "https://HoLa-Lee:$token@github.com/HoLa-Lee/victory-wave-wide-barriers.git" HEAD:main
# PR 分支
git -C C:\Windows\Temp\pr-warp push "https://HoLa-Lee:$token@github.com/HoLa-Lee/victory-wave-wide-barriers.git" tests/warp-tests-take-turns:tests/warp-tests-take-turns
# GitHub API（读 CLAIMS.md、PR、issue）
Invoke-RestMethod "https://api.github.com/repos/Marvisak/VIctory/issues/1633" -Headers @{ 'User-Agent'='dsh'; 'Authorization'="Bearer $token" }
```

注意事项：
- **不要**把这个文件（或其副本）提交到仓库 —— `victory-fork-history/docs/session-handoff.md` 是**去掉了 token 的版本**，每次同步时要保持这一点
- 该 token 只能用于 `HoLa-Lee` 名下仓库与公开 API 读；对 `Marvisak/VIctory` **无写权限**（所以只能开 PR，不能直接评论到别人的 issue 之外的操作——评论可以，issue 评论走公开仓库是允许的）
- 若泄漏：GitHub → Settings → Developer settings → Tokens 里立即 revoke 并重新签发

---

## 18. 本轮（2026-11-26 03:25）：#2478 按分诊改完重推；FIND-20 结案成 PR #1098

### 18.1 PR #2478（纹理刷新步长）——`needs-work` 四条全部处理，head **`c8d6571`**

| 评审要求 | 处理 |
|---|---|
| 放到 `diagnostics` 门控后面 | `due()` 里 `#[cfg(feature = "diagnostics")]`；非 diagnostics 构建直接返回 `true`，连 env 都不读 |
| 检查要在 `refresh_all` 里、`in_parallel` 之前 | `changed` 过滤改成 `due() && maybe_changed()`；`refresh()` 里那份检查删掉，不再把不该刷的纹理交给线程 |
| 恢复行尾换行 | 已恢复；提交的 blob 全 LF（907 行），`git diff --check` 干净 |
| kotekompotek：`EVERY=0` 会走到取模；丢行尾 | `.filter(|&n| n > 0).unwrap_or(1)`，0/1 都等于"每帧" |
| kais7654：clippy 1.98 `manual_is_multiple_of` | 改成 `.is_multiple_of(every)` |

本地实测：`cargo check -p victory-gpu`（默认 feature）通过；`--profile diag --features diagnostics` 通过；`cargo clippy -p victory-gpu --all-targets --all-features -- -D warnings` **0 警告**；`cargo test -p victory-gpu --lib --profile diag --features diagnostics` **196 passed / 2 failed / 1 ignored**（那 2 个是 #1744 view-heap，main 上同样失败）。

PR 正文重写（回应四条 + 验证数字），并回评 kotekompotek / kais7654（评论 `7172061568`）。triage 会针对新 head 再跑一次。

### 18.2 FIND-20 结案：不是并发、不是缓存、不是适配器——是测试锁定了 GPU 不保证的次序

- **适配器始终是 WARP**：`Microsoft Basic Render Driver`，vendor `0x1414`、device `0x8c`、flags `0x2`（两个 harness 现在都会打印）→ "某些运行用了非 WARP 适配器"假设彻底死掉
- **失败的断言不是 `spent`**：`spent == BUDGET_CAP` 每次都过；失败的是 `assert!(i == 1 || i == 2, "the first two real draws fit the budget")`
- **哪个 record 先计费由 GPU 决定**：并行 lane 的 atomic add，先到的 64 组先算。单测独跑 15 次 → record **1/2 中奖 4 次**、**64/65 中奖 11 次**，`spent` 15 次全对
- 另一个候选 `inplace::tests::warp_a_title_buffer_in_place...`（`VirtualFree(MEM_DECOMMIT)` 返回 0）单跑 **20/20 通过**，且打印了 `VirtualQuery` 状态 / `ResetWriteWatch` / `GetLastError` → 不牵连
- **修法**：断言改成"固定事实"——两张 `1<<26` 的 record 放进 `1<<27`；恰好两张保留、其余整张清零；预算饱和不回绕；空的首个 record 不计费；其余字不丢；失败信息带上实际中奖的 record
- **结果**：该测试单跑 **25/25**；`victory-gpu` lib **198 passed / 0 failed / 6 ignored**，并行 4 次 + `--test-threads=1` 4 次全绿（改前 20 次里 13 次失败）

### 18.3 新 PR：**#1098** → `fxceless/victory-fork`

https://github.com/fxceless/victory-fork/pull/1098 —— 1 文件 **+13/−3**，`mergeable=True`，CI 未跑（fork PR 同样要维护者批准）。
`inplace.rs` 与 `warp_*` 测试**只在 fork 那条线上**（Marvisak main 没有），所以提给 fxceless。
为此新开了 fork **`HoLa-Lee/victory-fork`**（`fork=true`，parent `fxceless/victory-fork`），用同一个 token push 分支 `tests/budget-charges-any-two` = `f1f95fe`（基于 `d510ee4`）。

### 18.4 已发 #1633

`7172251680`：FIND-20 的测量表 + 结论 + `done: FIND-20 -> .../pull/1098`。机器人仍停在 `sha=5d4c495`（13:48Z），这条也在队列里。

### 18.5 新 worktree

| 路径 | 内容 |
|---|---|
| `C:\Windows\Temp\pr-budget` | **PR #1098** 的分支 `tests/budget-charges-any-two`（`f1f95fe`，基于 `d510ee4`） |
| `C:\Windows\Temp\find20` | FIND-20 的插桩树（detached `dddbb01`），运行日志在 `find20\logs`（改前）与 `find20\logs2`（带插桩） |
| `C:\Windows\Temp\pr-warp` | **旧的加锁 + GetLastError 补丁还在，已被证伪，不要再推** |

### 18.6 两个新坑

- **PowerShell 执行策略**：`& xxx.ps1` 直接 PSSecurityException → 用 `pwsh -ExecutionPolicy Bypass -File`，或把循环写成内联命令
- **fork 线（`d510ee4`）的 clippy 本来就不干净**：8 个 `manual_is_multiple_of` + 1 个 dead_code，`-D warnings` 直接红。**"clippy 0 警告"只在 main 线（Marvisak）成立**，别拿它当 fork 线的门槛

### 18.7 下一步（更新后的顺序）

1. 盯 **#2471**（`merge-candidate`，只等维护者批 CI）、**#2478**（`c8d6571`，等新 triage）、**#1098**（`f1f95fe`）
2. **NEW-20**（NVIDIA 世界 TDR）认领了但没交付：要卡上跑到世界 + 逐个测开放 PR，任务原文是"先测哪个开放 PR 修了它，再用 `VICTORY_SKIP_PIPELINES` 收窄"
3. **copy-back**（135–183 ms / 63–70 MB 每帧）仍是帧里最大项；§14 已定它是延迟不是带宽
4. 机器人恢复后补：`done: FIND-20 -> #1098`、`#2471`、`#2478`

---

## 19. 本轮（2026-11-26 05:00）：卡上 30 分钟长跑、调试层的四条发现、PR #2790

### 19.1 卡上 30 分钟长跑（新纪录）

`world1`：`VICTORY_FAST=1` + `VICTORY_TEXTURE_STAGE_MB=64` + `VICTORY_INDIRECT_GATHER=1`，1800 秒，§6 键序 + 140 s 之后每 6 秒一次 `Enter` 共 706 个键。

| 项 | 数值 |
|---|---|
| 存活 | **1,800 s，0 丢设备 0 陷阱**（原纪录 700–900 s） |
| 帧 | 中位 **217 ms（4.6 fps）**，最好 **95.7 ms（10.4 fps）**，300 条帧日志 |
| draws 中位 | 4,511（4,088–5,873） |
| 帧构成 | copies 46–64 ms / 138–196 MB；**回拷 124–200 ms / 55–82 MB ← 最大项**；GPU 80–121 ms；textures 0.1–0.3 ms |
| 结论 | 仍然停在过场/字幕，**没进世界**；story_packs=7、world_packs=8 与之前一致。按 `Enter` 刷 30 分钟不推进 |

### 19.2 调试层的四条发现（`dbg1`，`VICTORY_D3D12_DEBUG=1` 跑 240 s）

1. **卡上被拒的管线也是 wave64**：`CreateComputeShader: Shader wants wave lane count of 64 but maximum wave lane count for device is 32`，6 个 compute 管线被拒（`2cc4c197`、`2da4beb3`、`02384a60`、`369cbe90`、`6b82bc7d`、`5dc3b259`），另有 2 个 shader 完全不翻译。→ **paired-wave64（#854 类）不只是 WARP 的事，也是卡上的事**
2. **一个 mesh/pixel 管线因整数 RT 混合被拒**：`slot 2 = R8_UINT` + 该 slot 开了 blending → `E_INVALIDARG`。→ 已修，见 19.3
3. **FIND-9 的数字来自设备本身**：`NumDescriptors 2097152, but the limit for shader visible view heaps is 1000000`。`HEAP_VIEWS`=2^21=2,097,152 > NVIDIA 的 1,000,000
   - `67e8ae1`（main）：两个测试**失败**（196 passed / 2 failed）
   - `36b1207`/`4d94e2f`（含 `31714de` = triippywhale 的 view-heap clamp）：**198 passed / 0 failed / 6 ignored**
   - → FIND-9 的修复就是 `31714de`，不是测试写错
4. **帧里最大的掉帧理由是 RT 结构构建器，且是故意的**：`dropped 227–1412/frame without a host pipeline: a stage of the ray-tracing structure builder, which is off`（`VICTORY_BVH_BUILDER=1` 才开；32-lane 主机建不完整；#2311 见过卡死）
   - ⚠️ **重要的口径修正**：帧行的 `dropped N without a host pipeline` **主要不是几何丢失，是射线**。§18 与旧文里把它当"丢 draw"读会误导

### 19.3 新 PR #2790：整数渲染目标的混合（已实测）

https://github.com/Marvisak/VIctory/pull/2790 —— `crates/victory-gpu/src/pipeline/host.rs`，+166/−2，head `8aa35fb`，`mergeable`。

- `GraphicsState::settle_integer_targets()`：只对**整数格式**的 RT slot 关掉 `BlendEnable`，在 `describe()` 之前、建任何管线之前执行（所以库里管线名仍描述实际状态）；混合因子保留
- 两个测试：① 在**真实设备**上直接建那份状态，断言"拒绝 → 关掉该 slot 混合后能建"（机制前后都在一个测试里）② 逐 slot 钉住（整数丢混合、浮点保留、超 `NumRenderTargets` 不动、settle 两次无变化）
- **卡上 A/B**（同键序同 300 s，旧二进制 `blend0` vs 新 `blend1`）：`host mesh pipeline refused` **20 → 0**，新日志出现 `blending is off for those slots slots=[(2, 62)]`（62 = R8_UINT）；draws 峰值 5,012 → 9,393
- 验证：`cargo test -p victory-gpu --lib --profile diag --features diagnostics` **198 passed / 0 failed / 6 ignored**；`clippy -p victory-gpu --all-features` clean
- 注意：`clippy --all-targets` 在 **main 上本来**就红（`victory-formats` 8 参数 `too_many_arguments`），与本改动无关

### 19.4 两个必须记住的新事实

- **我们自己的 main 上已经有 stride 实现**：`bca7e8f GPU: round-robin texture refreshes…`（作者 `VIctory fork`，即我们自己），**不在 Marvisak main**。所以 #2478 是把同一件事送往 Marvisak；若 Marvisak 合并 #2478，将来再合并时要**放弃 `bca7e8f` 那份、保留合入的带 `diagnostics` 门控版本**
- 卡上二进制现在是 **blend 修复版**（`victory.exe.blendfix`，8/26 04:36）。旧版备份：`C:\Windows\Temp\victory.exe.world1bak`

### 19.5 新 worktree / 产物

| 路径 | 内容 |
|---|---|
| `C:\Windows\Temp\pr-blend` | **PR #2790** 的分支 `gpu/integer-target-blend`（`8aa35fb`，基于 `4d94e2f`） |
| `C:\Windows\Temp\victory.exe.world1bak` | 修复前的卡上二进制（A/B 用） |
| `C:\Windows\Temp\victory.exe.blendfix` | 修复后的卡上二进制（当前装着的） |
| `vlogs\world1.*` | 1,800 s 长跑 |
| `vlogs\dbg1.*` | 调试层 240 s（四条发现的出处） |
| `vlogs\blend0.*` / `blend1.*` | A/B 的两次 300 s |

### 19.6 已发 #1633

`7174212089`：四条发现 + FIND-9 的对照表 + `finding:` 一行（"调试层的拒绝理由会同时说出 wave64、堆上限与整数混合，WARP-only 的 CI 看不到这三点"）。

### 19.7 下一步

1. 盯 #2471（`merge-candidate`）、#2478（`c8d6571`，等新 triage）、#1098、**#2790**
2. `FIND-9`：`31714de` 若没别的路径进 main，就是 `main` 上两个 NVIDIA 测试红的唯一原因——可主动提这个 port，或等 fxceless 合
3. `NEW-20`：现在有了卡侧立足点——**卡上的 compute 拒绝也是 wave64**；下一步该在卡上验 paired-wave64（#854 类）能否把那 6 个管线跑起来
4. 回拷（124–200 ms / 55–82 MB）仍是帧里最大项；`GPU-SNAPSHOT-COST`/PR #1681 是 @avt0m4t48 的地盘，别重复

### 19.8 追加（05:05）：PR #2790 重做成干净 diff + 一条新规矩

- 第一次推的 #2790 是 **+67,983/−1,808**、`mergeable=False`：因为分支从**我们的 main（含 fxceless 合并）**切出，PR 的 base 却是 Marvisak main —— 整个合并都算进了 diff
- 重做：`git fetch marvisak main`（新增 remote `marvisak`）→ 从 `13f91ca` 重切分支 → 手工把改动重打在 **Marvisak 版**的 `pipeline/host.rs` 上（那一版没有 `dxc`/`host()` 测试脚手架，所以 PR 只带**状态测试**，设备级的前后对照写进正文）
- 现在：**1 文件 +107/−3，head `f00d527`，`mergeable=True`**
- ⚠️ **新规矩**：给 **Marvisak/VIctory** 的 PR，分支必须从 `marvisak/main` 切；从我们的 main 切会把 36b1207 那次合并卷进去。给 **fxceless/victory-fork** 的 PR（如 #1098）才从 fork 线切
- 卡上二进制仍是 pr-blend 旧树编的（`victory.exe.blendfix`，含同一份修复 + 设备测试），行为与 PR 里的代码一致
- Marvisak main 上的测试结果：`197 passed / 2 failed / 1 ignored`，**2 failed 就是 FIND-9 那两个**（main 没有 `31714de` 的 clamp），与本改动无关

---

## 20. GitHub 的回复与本轮应对（2026-11-26 06:35）

### 20.1 PR #2471 —— **已被维护方关闭**（`merge-candidate` 之后第二意见翻案）

`Marvisak` 22:10Z 关闭，理由：**info queue 是设备级的，多个 worker 并发拒管线，`log_messages()` 抽到的第一条可能属于别人的管线** —— 归因不成立；而 `log_messages` 本来就把每条消息单独打成 `D3D12: …` 警告。

已回评 `7176348325`：**接受，不申辩**。并给出证据说明"单独那行已经够用"：`VICTORY_D3D12_DEBUG=1` 下我们**没有这个 PR 也**读到了 `R8_UINT` 那条原话，才有的 #2790；同一次运行还读到了 wave64 与 1,000,000 堆上限。`messages` 命名 nit 作废。
→ **教训**：这类"把调试层消息贴到拒绝行"的改动，价值全在归因；归因不可靠时，功能增量是 0。

### 20.2 PR #2478 —— **triage 转为 `merge-candidate`**（head `c8d6571`，20:18Z）

四条评审（diagnostics 门控、`refresh_all` 前置检查、行尾换行、`0` 与 `is_multiple_of`）**全部确认到位**；正文数字被点明"支持动机但评审无法复现"。现在只等维护者批 CI。

### 20.3 PR #2790 —— 两条评审，**一个真实 bug，已修**

- `kotekompotek`：+68k/583 文件不是可评审的改动（那是分支切错了，已重做成单文件）
- `fuzeofficlal`（RTX 5090 实测 + 规格审查）：**`IndependentBlendEnable == FALSE` 的语义被我漏了** —— 默认 FALSE 时 `RenderTarget[0]` 应用到所有已绑定 slot、`RenderTarget[1..]` 被忽略，于是
  1. **漏关**：RT0 浮点且开混合 + RT2 是 `R8_UINT` 且自己 `BlendEnable=false` → 我们什么都不改，设备照样拒
  2. **过宽关**：RT0 是整数且开混合 + RT1 浮点 → 我们关掉 RT0 也把浮点 slot 的混合关掉了

**修法**（`69d483f`，单文件 **+199/−3**）：
- `IndependentBlendEnable == false` 且有整数 slot 且 slot0 在混合时：**把 slot0 的状态复制到全部 slot 并置 `IndependentBlendEnable = true`**，然后只关整数 slot；全部 slot 都是整数时不必独立，直接关 slot0（共享态一起关）
- 还给 `slots()` 补回了被我自己弄丢的文档注释（第一次打补丁时把两段 doc 合并了）

**真实设备验证**（在 fork 线有 `dxc`/`host()` 脚手架的树上做，PR 树没有这套助手）：构造 fuzeofficlal 的"漏关"场景（RT0 `R8G8B8A8_UNORM` 混合开、RT1 `R8_UINT` 自己的 BlendEnable=false、`IndependentBlendEnable=false`）→ 设备**拒绝**；`settle_integer_targets()` 之后 → **建得出来**，并断言 slot0 仍在混合、slot1 不在、独立混合已开。
→ 已回评 `7176318635`。

### 20.4 PR #1098 —— 一条评审，**按建议收紧**

`liuycsbxbxn` 认同"不变量写法"，并指出 **#1110**（同一文件、已开）仍然写 `kept == [1,2] || kept == [64,65]`，**锁了组内 lane 顺序**；两条小建议：
- `assert_eq!(kept_at.len(), 2, …)` 单独成断言（现在做了，`zeroed` 也独立）
- 测量表要有说服力（保留，并把"组内 lane 顺序也不是承诺"写进同一条注释）

→ `bfbb167`（+16/−5），测试 20/20；已回评 `7176346660`：若维护者更愿意要 #1110，我们关掉 #1098。

### 20.5 认领机器人：只恢复了一半

`forge-status` 最新 `974a507 21:50Z Forge status` —— 但那次只改了 `STATUS.md`/`status.json`；**`CLAIMS.md` 仍是 `sha=5d4c495`（13:48Z 的 "Claims" 提交）**，`FIND-9`/`FIND-20`/`NEW-20` 仍显示 `open`、无 holder。→ 我们的 `claiming:`/`done:`/`finding:` 还在队列里，**不是格式问题**。

### 20.6 现在四个 PR 的状态

| PR | head | 状态 |
|---|---|---|
| #2471 | `0cd1a79` | **已关闭**（归因不可靠），已回评接受 |
| #2478 | `c8d6571` | **merge-candidate**，等维护者批 CI |
| #2790 | `69d483f` | 单文件 +199/−3，`IndependentBlendEnable` 已修，等复看 |
| #1098（fxceless） | `bfbb167` | 按评审收紧，等复看 |

---

## 21. 本轮（2026-11-26 07:30）：5 → 3 → 2 → 1 四项做完 + 8 小时监控上线

### 21.1 ⑤ paired-wave64 在卡上的实测：**compute 拒绝 7 → 0**

方法：300 s 开场，同键序同种子，`VICTORY_TEXTURE_REFRESH_EVERY=8` / `STAGE_MB=64` / `GATHER=1`，调试层关。A 臂 = 我们 main + #2790；B 臂 = `fxceless/victory-fork` PR **#854**（head `51700c6`）+ 我们自己两笔（stride、以及删掉它引用的两个诊断计数）。

| | A（main + #2790） | B（#854 paired） |
|---|---|---|
| compute 管线被拒 | **7**（`02384a60`/`2cc4c197`/`2da4beb3`/`369cbe90`/`5dc3b259`/`6b82bc7d`/`6f225b64`） | **0** |
| 完全不翻译的 compute shader | **2**（`926c46ba`、`f133e35e`） | **0** |
| 其它被拒 | 0 | 1（`mesh f5e50eb2108c425b + pixel ce3f0432a08f1d35`，即 #2790 的 R8_UINT 混合，本臂没带 #2790） |
| 丢设备 / 陷阱 | 0 / 0 | 0 / 0 |
| 故事帧数 | 23 | 18 |
| 最高 draws | 9,393 | 9,967 |

**成本**：同样的 draws 下慢 1.5–3.3×（6,116 draws 1,840 ms vs 7,016 draws 1,200 ms；9,967 draws 3,749 ms vs 9,393 draws 1,119 ms），纹理项从 0.3–8 MB/帧涨到 8–275 MB/帧 —— 因为**这些 compute 现在真的在跑**，而它们会写纹理。
→ 已发 #1633（`7177127504`）。**结论：#854 是卡上唯一能让那 7 个管线跑起来的路径；配上 #2790 则"零拒绝管线"的卡上配置成立。**

### 21.2 ③ copy-back 的四分桶：**95% 是在等卡，不是字节工作**

插桩 `Shadow::relay_merge`（本机走 `VICTORY_LATE_WAIT=1` + `VICTORY_RELAY=2`），300 s：

| 每帧 | 数值 |
|---|---|
| 帧行的 "copying back"（= relay 线程 landing 总时间） | **60–127 ms** |
| 其中**等卡（无事可 landing）** | **29–46 ms** |
| 其中**等卡上 fetch 的 piece** | **33–82 ms** |
| 合并的 piece / 写回字节 | 132–171 pieces，**2.2–2.7 MB** |
| 快照锁等待 | **0.00 ms** |
| 锁内做完（拷贝、diff、读 title、merge） | **2.4–2.9 ms** |
| 真正写进 title memory | **0.38–0.52 ms** |

→ **主机侧字节工作只有 ~3 ms/帧**；`GPU-SNAPSHOT-COST` 想做的"在卡上比较"省掉的是那 3 ms，**两个等待一分不减**。真正的杠杆是"每次 landing 少几趟卡上往返"。已发 #1633（`7177276720`）。
→ 顺带纠正一个读数：帧行的 "copying back X MB" 是**看过**的字节数，真正写回只有 2–3 MB。

### 21.3 ② `cargo xtask refusals` → **PR #2892**

`xtask` 上游只有 `policy`；新增子命令把一次运行丢的东西一次说清：被拒管线（按 shader 分组）、调试层原话（有 `VICTORY_D3D12_DEBUG=1` 时）、完全不翻译的 shader（带 converter 原话）、每帧丢弃理由及速率。
用真日志验证：一次运行就把 8 个被拒管线、14 类调试层消息、2 个不翻译 shader、以及"RT builder 每帧 1,412 次"一次列出，还顺带打印出两个 converter 的确切原因（`a lane mask holding lanes elsewhere read as data is not supported` / `a lane mask exchanged where not every lane runs is not supported`）。
测试：`cargo test -p xtask` 8 passed（含 2 个新单测）；`clippy -p xtask --all-targets -D warnings` 干净。**1 文件 + xtask/src/refusals.rs（283 行）+ main.rs（11 行）。**
（原计划是 PowerScript 工具，但 `tools/` **不在 Marvisak main 上**，而 `xtask` 在 —— 所以改成上游口径。）

### 21.4 ① #2790 的画面：**同屏幕的帧像素完全相同**

同基线的两次 300 s（都开 `VICTORY_CAPTURE`，2 的幂帧落盘）：

| 帧 | 不同像素 | 平均差 |
|---|---|---|
| 1–1024（11 张） | **各 0 / 2,073,600** | 0.0000 |
| 2048 | 40,833（1.97%） | 1.3992 |
| 4096 | 228（0.011%） | 0.0022 |

2048 那张不是"改动的视觉差异"：两次运行停在**不同屏幕**（一张韩文 `법적 공지`、一张英文 `LEGAL NOTICES`），键序差了一页。已把差异图与结论回评到 #2790（`7177608229`）。

### 21.5 8 小时监控已上线

- 脚本：`vlogs/monitor/snapshot.ps1`（PS 5.1；token 从 `owner` remote 的 push URL 读，不落盘）
- 每轮采集：我们的 5 个 PR（状态/head/新评论，区分"别人说的"）、三条主干（Marvisak / fxceless / 我们自己）、`CLAIMS.md` sha、#1633 最后 5 条、**22 个 tracker 列出并持续更新的 fork** 的 `pushed_at`、以及 **gta6pconline.com 自己的头条**（每小时的摘要比单个仓库更全）
- 产出：每轮一个 `20261126-HHmm.json` + 追加到 `git-monitor-report.md`（Action 在前、Signals 在后）
- 定时任务：`schedule-d73b3261-87e9-46ae-b5f8-072af1d6a582`，**每 30 分钟 × 16 轮 = 8 小时**，从 08:15 本地时间开始
- 规则：有 ACTION 当轮处理；上游把我们的事做掉了就关/改基；只有主干新提交就只记录；**全都没有时推进一个未认领项**（候选 `FIND-9` / `TEST-MED3-NAN` / `FIND-14` / `FIND-15` / `FIND-19`，先 `claiming:` 再动手）
- 首轮已 bootstrap：现有评论都已回过（#2478 triage 20:18、#2790 fuzeofficlal 21:31、#1098 liuycsbxbxn 22:06）

### 21.6 本轮新增的 worktree / 产物

| 路径 | 内容 |
|---|---|
| `C:\Windows\Temp\wave64-raw` | #854 + stride（能跑的那份），卡上 B 臂由它构建 |
| `C:\Windows\Temp\pr-wave64` | 把 #854 合进我们 main 的尝试：只剩 `lower.rs` 一个冲突，但 `descriptor_data` 被 PR 移进子模块 → 与 main 的同名内联函数重复，**没合完，留作下次** |
| `C:\Windows\Temp\pr-copyback` | copy-back 四桶插桩（未提交，未开 PR —— 结论已发 #1633） |
| `C:\Windows\Temp\pr-xtask` | **PR #2892** 的分支 `tools/xtask-refusals`（`dc7d199`，基于 `13f91ca`） |
| `C:\Windows\Temp\frames-nofix` / `frames-fix` | 各 13 张抓帧（#2790 画面对比） |
| `C:\Windows\Temp\victory.exe.{world1bak,blendfix,wave64,copyback,nofix}` | 各次实验的二进制 |

### 21.7 重要教训

- **Marvisak main（`13f91ca`）本身在这张卡上起不来**：抓帧那轮用 main 裸编，开场就 `device removed (0x887A0004)`；而我们合并 fxceless 后的 main 能跑 1,800 s。→ 给 main 的 PR 都要意识到"main 未合并 fork 的修复，卡上跑不动"，这也是 #1098/#2790 之类的价值所在。
- `git remote get-url owner` 拿到的是 **fetch** URL（无 token），要 `--push`。

---

## 22. 主干预动了（23:27Z）+ #2790 关闭 + 监控第 0 轮就抓到（2026-11-26 08:05）

### 22.1 上游一次合了 62 个文件：`13f91ca` → `63bcca4`

+9,562/−814，含 `#158`（depth bounds 到 host）、`#2493/#2484/#2468/#2462/#2455/#2449/#2448/#2395/#2378` 等，几乎全是 GPU 绑定与 shader 转换修复。

### 22.2 PR #2790 **已关闭**：main 自己做了

`a7cb47c`（Pablo González，PR **#1152**，11-25 22:49Z）新增 `host_blend()`：整数 RT 关混合、共享态时"每个 target 一份、别人保留自己的"——**与我们那版逐条相同，连 `IndependentBlendEnable` 的处理都在**（`blends(i)` 共享时读 slot 0）。
而且**它自带两个测试**（`integer_targets_do_not_blend`、`blend_states_without_integer_blending_are_kept`），覆盖了我们计划补的全部用例 → **没有后续 PR 可做**。
已关（评论 `7177698887`，随后补一条更正 `7177869958`，因为我在关闭评论里误说"要补测试"）。
→ 这条路径的净贡献是：卡上的拒绝原话与丢失 draws 数、关闭前后的**同帧像素对比**、以及 @fuzeofficlal 的 `IndependentBlendEnable` 检查（main 的实现也确实处理了）。

### 22.3 上游 main 现在能在卡上启动了 —— 但慢 15 倍、被拒 155 个管线

| | main `13f91ca` | main `63bcca4` | 我们合并线 |
|---|---|---|---|
| 卡上启动 | **立刻 `device removed 0x887A0004`** | **跑满 300 s，0 丢设备** | 跑满 1,800 s |
| 帧 | — | **0.1–0.3 fps（3,071–7,786 ms），GPU 2,780–5,226 ms** | **4.3–4.8 fps（208–232 ms）** |
| 被拒管线（`xtask refusals`） | — | **155 种**（几乎全是 compute） | **7 种** |
| draws | — | 762–3,296 | 4,000–5,900 |

→ **新口径**：main 的"能启动"是这一批修复带来的；但它的翻译器仍拒 155 个程序，所以只有 0.3 fps。**fork 那条线的转换工作（以及我们的并线）是决定帧率的东西，不是锦上添花。**
→ 这也解释了 #1098/#854 一类工作的真正价值：每减少一个"被拒管线"，卡上就多一段真实工作量、少一段空白。

### 22.4 我们的 main 与上游 main 的合并：**没做，留给专门一轮**

`pr-intake` 里试合 `marvisak/main`：冲突遍布 `README.md`、`apps/victory/{main,run,translate}.rs`、`crates/victory-formats/src/texture.rs`、`victory-game/src/sgd5.rs`、`victory-gpu/{Cargo.toml,capture,copystat,descriptor,...}`、`victory-shader/{native,resource,structure}.rs` —— 62 文件的进厂 + 两边分叉，已 `merge --abort`，工作树回到 `df67a5f`。
**下次要单独一轮做**：先按目录分批（shader → gpu → apps），每批编译通过再进下一批。

### 22.5 监控第 0 轮就兑现了

首轮快照（`vlogs/monitor/20261126-0729.json`）报出 `Marvisak main 13f91ca -> f3578e3`，随后确认 `mergeable_state=dirty`：**#2790 与上游新提交冲突**。如果没有这条，会一直以为 PR 在等评审。实际处理是"上游已经做了 → 关闭"，比"rebase 再推"省了一整轮。
定时任务 `schedule-d73b3261-87e9-46ae-b5f8-072af1d6a582`，每 30 分钟 × 16 轮，从 08:15 起。

### 22.6 现在的四个 PR

| PR | head | 状态 |
|---|---|---|
| #2478 纹理刷新步长 | `c8d6571` | open，`mergeable=True`（能否仍与 `63bcca4` 干净合并待下轮确认） |
| #2892 `xtask refusals` | `dc7d199` | open，+294/−0 |
| #1098（fxceless）预算测试不变量 | `bfbb167` | open，+16/−5 |
| #2790 整数混合 | `69d483f` | **已关闭**（上游 `a7cb47c` 做了，且带测试） |
| #2471 拒绝日志 | `0cd1a79` | 已关闭（归因不可靠） |

---

## 23. 监控第 1–11 轮（2026-11-26 08:15 → 13:15）：五个 PR、两条教训、一个自我事故

定时任务 `schedule-d73b3261-87e9-46ae-b5f8-072af1d6a582`，每 30 分钟一轮（16 轮 = 8 h），脚本 `vlogs/monitor/snapshot.ps1`，逐轮报告在 `vlogs/monitor/git-monitor-report.md`，每轮 JSON 在同目录。

### 23.1 现在挂着的五个 PR（全部 `open` + `mergeable`）

| PR | 内容 | 规模 | 状态 |
|---|---|---|---|
| **#2478** | 纹理刷新步长 `VICTORY_TEXTURE_REFRESH_EVERY` | +29/−3 | triage 已转 `merge-candidate`，等维护者批 CI |
| **#2892** | `cargo xtask refusals <log>` | +313/−0 | 收到 `needs-work` 五条，**全改完**（`b040e48`），等复看 |
| **#2937** | view-heap cap：两个测试带数字跳过（FIND-9） | +28/−3 | 等复看 |
| **#3000** | 空 root-constant 列表不再传给运行时（崩溃修复） | +6/−0 | 等复看 |
| **#3036** | pending copy-back 不写回收内存（FIND-14） | +75/−2 | 等复看 |

已关：#2471（归因不可靠）、#2790（上游 `a7cb47c` 做了，且自带测试）。

### 23.2 本轮真正做出来的东西（按价值）

1. **FIND-14 复现 + 修复（#3036）**：合成测试证明 pending copy-back 会把旧提交的字节写进 title 已回收并复用的地址（`0x99` 落在新分配里）；修法是 `Shadow.gone` + `unregister` 置位 + `copy_back_or_not` 提前返回。**无游戏、无 AMD 卡**即可复现。
2. **崩溃根因（#3000）**：`emit::memory_tests::heap_direct_texture_reads_mark_their_heap_index` 单跑就把进程打成 `0xc0000005`，根因是 harness 把**空的 root-constant 列表**（count 0 + 空 vec 指针）交给 `SetComputeRoot32BitConstants`，NVIDIA 运行时在此崩溃。修后整个 `victory-shader` 套件第一次能跑完：**299 passed / 3 failed / 3 ignored**，那 3 个失败正是被崩溃遮住的 **FIND-11**（@jujumoneylol 的 #2885，不碰）。
3. **FIND-9（#2937）**：卡上实测 `limit for shader visible view heaps is 1000000`、实际拿到 65,540；两个测试改成"读自己拿到的 heap，低于 `HEAP_VIEWS` 就带数字跳过"。

### 23.3 两条教训（写下来省下一次踩坑）

- **这些 worktree 里永不 `git add -A`**：我在旧基上 `git add -A` + amend + force push，PR #2892 一度显示 `64 files / −9,562`（把上游 `63bcca4` 的成果显示成删除）。推之前必须 `git diff --stat marvisak/main..HEAD`，且分支要 rebase 到当前 `marvisak/main`。
- **PS 5.1 写中文**：`Add-Content -Encoding utf8` 在管道里会把中文写成乱码；正确做法是先用 write 工具落一个 UTF-8 文件，再 `[IO.File]` 追加。同理 `Set-Content` 生成的 diff 带 BOM/CRLF 会让 `git apply` 失败，diff 要用 `cmd /c "git diff > file"`。
- 另：**github.com 的 HTTPS 会间歇性拒连**（api.github.com 正常），push 要重试 3–4 次；不要以为分支坏了。

### 23.4 认领表（已恢复）

`CLAIMS.md` 从 `sha=5d4c495`（停摆）恢复到 `aad2c65`：
- `FIND-9` → `in review` #2937（曾被错挂到 #3036，已在 #1633 更正 `7182924568`）
- `FIND-14` → `in review` #3036
- `FIND-11` → `in review` **#2885 by @jujumoneylol**（所以那 3 个 shader 失败不归我们）
- `TEST-MED3-NAN` **在 `63bcca4` 上已不复现**（该测试通过），已在 #1633 说明可关

### 23.5 上游在动什么（监控记录）

`Marvisak/main`：`13f91ca → 63bcca4`，**62 文件 +9,562/−814**（含 #158 depth bounds、#2462/#2455/#2449 绑定修复、以及 `a7cb47c` 整数 RT 混合）。**main 现在能在卡上启动**（`13f91ca` 时立刻 `device removed`），但 **0.1–0.3 fps、155 个被拒管线**（我们合并线是 4.6 fps / 7 个）。
`fxceless/victory-fork`：连续多轮 diagnostics 日志入库（run 281–300），最近一条标题是"表为什么被拒：dynamic slots 的环满了"。

### 23.6 还没做（下一轮候选）

- **把 `marvisak/main` 合进我们的 main**：冲突遍布 20+ 文件（shader/gpu/apps 三层都动），要按 shader → gpu → apps 分批合、每批编译通过再进下一批。**这是目前最大的一块未做工作。**
- harness 的一个真实越界（`slots = d.views.len()` 但每个带资源的 view 写两个描述符）——单独一行修，但单独 PR 的证据要靠 #3000 才能跑起来，暂缓。
- `FIND-15`（NVIDIA 世界 hang 的两个停点）与 `FIND-19`（device slot 0x218 的 `E_NOTIMPL`）都需要游戏侧实验。
