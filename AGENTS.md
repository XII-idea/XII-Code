# AGENTS.md

本仓库是 **XII Code** —— 基于 VS Code 源码自编译、品牌化的定制版 IDE。
上游：`microsoft/vscode`（MIT 许可）。Electron 可固定 pin 到官方 nightly。

任何 agent 在本仓库工作前，必须先读完本文件；执行时严格遵循其中的约束与命名规范。

---

## 1. 仓库布局（外层仓库 + patch/overlay 模式）

```
XII-Code/
├── AGENTS.md                     # 本文件
├── README.md                     # 人类使用说明
├── VERSIONS.md                   # 每次成功构建：上游 commit + Electron pin + 通道
├── .gitignore                    # 必须排除：vscode/ .build/ out*/ dist/ node_modules/
├── overlay/
│   ├── product.json              # 品牌字段白名单（脚本合并进上游 product.json，不整文件覆盖）
│   └── win32/code.ico            # XII 图标（覆盖上游 resources/win32/code.ico）
├── patches/
│   └── 0001-electron-config.patch  # build/lib/electron.ts 的 companyName/copyright 两行
├── scripts/
│   ├── check-updates.ps1         # 探测 3 个源并输出 JSON（stable / insider / nightly）
│   ├── pin-electron.ps1          # 固定/升级 Electron nightly pin（.npmrc + checksums）
│   ├── prepare.ps1               # clone 上游 → checkout → 品牌合并 → 打补丁
│   ├── build.ps1                 # 编译 + 打包，输出 dist/
│   └── cleanup.ps1               # 清理超过保留期的产物（供 CI 调用）
├── dist/                         # 本地产物（gitignore 排除）
└── .github/workflows/ci.yml      # 定时 + 触发式构建
```

**核心原则**：
- 上游 VS Code 永远以 **clone 形式** 存放在 `vscode/` 子目录（被 gitignore 排除，每次 `prepare.ps1` 重建）。
- 对外暴露的"变更面"只有 `overlay/` 与 `patches/`，其余全部是脚本。这样 rebase 上游时冲突面最小。
- 上游 `product.json` 的 `builtInExtensions` 版本号每周变化，**禁止** 把整个上游 product.json 提交进本仓库。`overlay/product.json` 只写品牌字段，由脚本深度合并。

---

## 2. 双通道规划

| 维度 | Stable 通道 | Insiders 通道 |
|---|---|---|
| 构建来源 | 官方 stable 最新发版 | 官方 insider 最新发版 |
| 构建分支 | `release/1.142`（该版本对应的 release 分支） | `main` |
| 版本显示 | `1.142.0` | `1.143.0-insider`（保留 `-insider` 后缀） |
| 产物命名 | `XII Code Setup <ver>.exe` | `XII Code Insiders Setup <ver>-insider.exe` |
| 数据目录 | `.xii-code` | `.xii-code-insider` |
| Windows 互斥名 | `xii-code` | `xii-code-insider` |
| URL 协议 | `xii-code` | `xii-code-insider` |
| AppUserModelId | `XII.Code` | `XII.Code.Insider` |

两通道 **必须完全隔离**（互斥名、数据目录、GUID、AppUserModelId 各一套），与已安装的官方 VS Code / 官方 Insiders 互不冲突。

---

## 3. 品牌字段白名单（`overlay/product.json` 只允许出现这些 key）

```
nameShort, nameLong, applicationName, dataFolderName, sharedDataFolderName,
win32MutexName, win32DirName, win32NameVersion, win32RegValueName,
win32AppUserModelId, win32ShellNameShort,
win32TunnelServiceMutex, win32TunnelMutex,
win32x64AppId, win32arm64AppId, win32x64UserAppId, win32arm64UserAppId,
darwinBundleIdentifier, darwinProfileUUID, darwinProfilePayloadUUID,
linuxDesktopName, linuxIconName, urlProtocol, reportIssueUrl,
serverApplicationName, serverDataFolderName, tunnelApplicationName
```

**禁止** 出现 `quality` 字段（设成 `stable`/`insider` 会让打包走 appx 分支并因缺少 `win32ContextMenu` 直接崩）。
**禁止** 出现 `updateUrl`（避免与官方更新通道互相覆盖）。
**保留** `licenseName: "MIT"` 与 `licenseUrl` 指向上游，不改动。
四个 `win32*AppId` GUID 必须用 `[guid]::NewGuid()` 全新生成，禁止沿用官方 GUID。
`darwin*UUID` 必须用 `[System.Guid]::NewGuid()` 全新生成。

---

## 4. 硬性技术约束（违反任何一条都会让构建失败）

### 4.1 `.npmrc`（Electron pin）
- 保留 `target="46.0.0-nightly.20261005"`（或当前 pin 值）与 `ms_build_id="..."` 两行。
- **禁止** 删除 `ms_build_id` 行：`build/lib/electronVersion.ts` 用正则 `/^ms_build_id="(.*)"$/m.exec(npmrc)![1]` 读取，删了直接抛异常。OSS 构建不使用该值但必须存在。
- `disturl="https://electronjs.org/headers"` 与 `runtime="electron"` 不可改。
- 切 nightly 版本时必须同步调用 `scripts/pin-electron.ps1` 重新生成 `build/checksums/electron.txt`（`validateChecksum` 为 true，旧文件会导致下载后立即校验失败）。

### 4.2 工具链（`preinstall.ts` 强校验）
- **Node ≥ 24.18.0 且同大版本**（`.nvmrc` = 24.18.0；用 Node 25 会被拒绝）。
- **npm < 13**（本机若装了 npm 13 会报错）。
- **禁止 yarn**（preinstall 检测 `npm_execpath` 包含 yarn 会直接退）。
- Windows 必须有 **VS2022 或 VS2019 C++ 工具链**（检测 `vs2022_install`/`vs2019_install` 或默认路径；缺了直接退）。
- `cl` 必须在 PATH 或 MSBuild 可发现；CMake / Python 3.12+ 建议也装好。

### 4.3 `product.json` 的 `quality`
- 保持 **未设置**。`buildWin32Setup` 里 `quality = product.quality || 'dev'`；若误设成 `stable`/`insider` 会进 appx 分支并因 `win32ContextMenu` 缺失而 `TypeError`。

### 4.4 商标合规（必须遵守）
- 保留上游 `LICENSE.txt` 与 MIT 许可头。
- **禁止** 使用 "Visual Studio Code"、"VS Code"、"Microsoft" 作为产品名/宣传词。
- 官方 logo 与图标资源不得直接沿用；`resources/win32/code.ico`、`resources/darwin/code.icns`、`resources/linux/code.png` 必须替换为自有 XII 设计。
- 对外分发时 README 必须明确标注 "based on VS Code by Microsoft, licensed under MIT"。

---

## 5. 常用命令速查

```powershell
# 探测三个更新源（JSON 输出，CI 与本地都用）
.\scripts\check-updates.ps1

# 升级 Electron pin（会写 .npmrc + 重新生成 build/checksums/electron.txt）
.\scripts\pin-electron.ps1 -Version "46.0.0-nightly.20261005"

# 准备上游（clone + checkout + 品牌合并 + 打补丁；-Channel 决定分支）
.\scripts\prepare.ps1 -Channel stable    # 或 -Channel insider

# 编译 + 打包（输出到 dist/）
.\scripts\build.ps1 -Channel stable

# 本地冒烟（打包后可选）
node .\scripts\smoke.ps1 -Channel stable

# 清理（CI 用，默认 8h 保留期）
.\scripts\cleanup.ps1 -RetentionHours 8
```

---

## 6. 构建目标名（上游 gulp 任务，已核实）

| 目标 | 命令 |
|---|---|
| win32-x64 未压缩目录 | `npm run gulp -- vscode-win32-x64` |
| win32-x64 用户级 Inno 安装包 | `npm run gulp -- vscode-win32-x64-user-setup` |
| win32-x64 系统级 Inno 安装包 | `npm run gulp -- vscode-win32-x64-system-setup` |
| win32-arm64 系统级 Inno 安装包 | `npm run gulp -- vscode-win32-arm64-system-setup` |
| linux-x64 deb（prepare+build） | `npm run gulp -- vscode-linux-x64-prepare-deb vscode-linux-x64-build-deb` |
| linux-x64 rpm | `npm run gulp -- vscode-linux-x64-prepare-rpm vscode-linux-x64-build-rpm` |
| linux-arm64 deb | `npm run gulp -- vscode-linux-arm64-prepare-deb vscode-linux-arm64-build-deb` |
| linux-arm64 rpm | `npm run gulp -- vscode-linux-arm64-prepare-rpm vscode-linux-arm64-build-rpm` |
| 宿主开发运行 | `scripts\code.bat`（上游） |
| 冒烟测试 | `npm run smoketest` |

**平台矩阵**（由 `build.ps1 -Target` 驱动，CI 每个目标一个 job）：

| 目标 | Runner | 产物 | 安装/包类型 |
|---|---|---|---|
| `win32-x64` | windows-latest | `XII Code Setup <ver>-system.exe` | **系统级** Inno（需管理员） |
| `win32-arm64` | windows-latest（交叉编译） | `XII Code Setup <ver>.exe` | 用户级 Inno |
| `linux-x64` | ubuntu-latest | `*.deb`（amd64）+ `*.rpm`（x86_64） | 系统包 |
| `linux-arm64` | ubuntu-latest（交叉编译） | `*.deb`（arm64）+ `*.rpm`（aarch64） | 系统包 |

- **系统级安装**：`win32-x64` 走 `vscode-win32-x64-system-setup`（AppId 用 `win32x64AppId`，GUID 已在 product.json 配好）。
- **arm64 交叉编译**：x64 runner 上编译 arm64 原生模块（Node 侧按 `process.arch` 选择，`runtime=electron` 头文件按 `target` 取，与 host 无关）。
- **Linux deb/rpm**：上游 gulp 任务已原生支持（`dpkg-deb` + `rpmbuild`），CI 在 `ubuntu-latest` 上 `apt-get install fakeroot devscripts dpkg-dev rpm-build`。

## 7. Electron 大版本自动跟进（autoBumpElectron）

- `ci.yml` 的 `detect` job 支持 **自动推进 electron pin**：默认 `autoBumpElectron=true`。
  当 `check-updates.ps1` 探测到最新 nightly（如 `47.0.0-nightly.*`）与 `overlay/electron-pin.txt` 里的
  `target` 不一致时，detect 步骤会**改写 pin 文件并 commit 回仓库**，随后各 build job 用新 pin 构建。
- 行为可用 dispatch 输入 `autoBumpElectron: true/false` 控制；设 `false` 则 pin 固定不变，
  直到手动 `.\scripts\pin-electron.ps1 -LatestNightly` 后 push。
- **这是有意放开的安全边界**：大版本跨度（ABI/Chromium/V8 全变）可能让 VS Code 原生模块编译失败。
  若某次 bump 后构建失败，回滚方式：把 pin 文件改回上一个成功版本（见 `VERSIONS.md`）再 push。
- 每次成功/失败构建都会追加 `VERSIONS.md` 一行，便于追溯哪个 pin 可用。

---

## 8. CI 设计要点（`.github/workflows/ci.yml`）

### 8.1 触发器
- `schedule: cron '0 */6 * * *'`（每 6h 整点；仅 default branch 的自有仓库可生效，fork 上被 GitHub 禁用）。
- 手动：`workflow_dispatch`（输入通道 + 可选 Electron pin）。
- PR 触发：只跑 `prepare` + 品牌校验，不打包。

### 8.2 探测 + 决策
- 每个定时运行先跑 `check-updates.ps1`，得到 JSON：
  ```json
  { "stable": "1.142.0", "insider": "1.143.0-insider", "nightly": "46.0.0-nightly.20261005",
    "prevStable": "1.141.2", "prevInsider": "1.142.0-insider", "prevNightly": "46.0.0-nightly.20260930",
    "actions": [ "stable", "insider" ]   // 哪些需要构建
  }
  ```
- **任意一个源变了就构建对应目标**：stable 变 → 建 stable；insider 变 → 建 insider；nightly 变 → 两个通道的 `.npmrc` pin 都推到新 nightly，随各通道构建生效。
- 上一次状态存于 **GitHub Actions cache**，key：`upstream-stable` / `upstream-insider` / `electron-nightly`，值 = 探测到的版本字符串。

### 8.3 产物 8h 过期
- 产物只存 **Actions Artifact** + **draft GitHub Release**（不直接挂 release，避免被用户误装）。
- 每次运行开头先跑 `cleanup.ps1 -RetentionHours 8`：找出 `buildTime` 超 8h 的 draft release，调用 `gh release delete`（保留 changelog 文本，只删 asset）。
- 仓库 `.git` 不存任何二进制，空间压力只在 Actions 存储与 release asset 上。
- 若未来要接入 Azure Blob，可在 `cleanup.ps1` 里加一段 lifecycle rule（`maxAgeDays`/`maxAgeInDays` 设 1 天）。

### 8.4 并发与去重
- 同通道同时只能跑一个构建：用 `concurrency: group: 'xii-build-${{ matrix.channel }}'`。
- nightly 探测失败（GitHub 404 或 Electron 仓库当天没发）不阻塞 stable/insider 构建，只记 warning。

### 8.5 失败回退
- 某次 nightly pin 导致构建失败 → `VERSIONS.md` 里有上一次成功的 pin，手动 `workflow_dispatch` 时填回那个版本即可。
- 禁止"自动回退"：失败时让 job 失败并保留 log，由人工判断。

---

## 8. 产物与版本记录规范

每次成功构建后，**必须** 更新 `VERSIONS.md`（一行一条）：

```
| 时间(UTC) | 通道 | 上游 commit | 上游 tag | Electron pin | 产物 | 备注 |
|---|---|---|---|---|---|---|
| 2026-10-19 12:34 | stable | a0e7521b | 1.142.0 | 46.0.0-nightly.20261005 | XII Code Setup 1.142.0.exe | 首次 nightly 基线 |
```

产物文件名规范（与 `build.ps1` 输出一致）：
- `XII Code Setup <upstream_version>.exe`（stable）
- `XII Code Insiders Setup <upstream_version>-insider.exe`（insider）

---

## 9. 给 agent 的硬性规则（重复强调）

1. **不要** 直接修改 `vscode/` 下的任何文件（那是 clone，会被重建；要改就改 `overlay/` 或 `patches/`）。
2. **不要** 把 `vscode/`、`.build/`、`out/`、`dist/`、`node_modules/` 提交进本仓库。
3. **不要** 删除 `.npmrc` 的 `ms_build_id` 行。
4. **不要** 在 `overlay/product.json` 加 `quality`、`updateUrl` 字段。
5. **不要** 使用官方 GUID / UUID（`win32*AppId`、`darwinProfile*UUID` 必须全新生成）。
6. **不要** 把 "Visual Studio Code"/"VS Code" 当作品牌词对外使用。
7. 任何品牌字段增删，**必须** 同步更新本文件第 3 节白名单。
8. 任何 CI 行为改动（触发频率、保留期、并发组），**必须** 同步更新本文件第 7 节。
9. 构建成功 **必须** 追加 `VERSIONS.md` 一行，否则视为未完成。
10. 所有 PowerShell 脚本必须 **`Set-StrictMode Latest` + 显式参数校验**，禁止裸用 `$env` 假设。

---

## 11. 阶段与状态（供 agent 快速判断当前进度）

- [ ] 阶段 0：工具链验证 + 官方 43.7.7 基线构建跑通（本机）
- [ ] 阶段 1：品牌化双通道（overlay + patches + 双套 GUID/UUID）
- [ ] 阶段 2：切 nightly pin（`pin-electron.ps1` 首次执行）
- [ ] 阶段 3：CI（ci.yml + 探测 + 8h 清理 + cache key）
- [ ] 阶段 4：平台矩阵（win32-x64 系统级 / win32-arm64 / linux-x64 / linux-arm64 deb+rpm）
- [ ] 阶段 5：electron 大版本自动跟进（autoBumpElectron）
- [ ] 阶段 6（可选）：公开发布合规（代码签名 / SmartScreen / 商标审查）

**当前进度**（2026-10-19）：
- 仓库骨架 + 双通道品牌化已就位（阶段 1）：`overlay/product.json` + `product.insider.json`、`patches/`、全部脚本通过 PS 5.1 语法校验；prepare 合并 / .npmrc 改写 / 幂等性已离线单测通过。
- 阶段 4 平台矩阵已编码进 `build.ps1`（`-Target` 四值）与 `ci.yml`（`detect → matrix → build` 动态矩阵，win 走 windows-latest、linux 走 ubuntu-latest + apt 装 `fakeroot devscripts dpkg-dev rpm-build`）。
- 阶段 5 autoBumpElectron 开关已加入 `ci.yml`（dispatch 输入，默认 `true`）：detect 步探测到最新 nightly 与 pin 不一致时改写 `overlay/electron-pin.txt` 并 commit 回仓库。
- electron pin 已预设为 `46.0.0-nightly.20261005`（阶段 2 的 pin 已落地，真正生效需 CI 跑通）。
- **未提交**：全部改动待你确认后 `git add -A && git commit`；本地无 Node/工具链，阶段 0 基线由 GitHub Actions 承担。

---

## 11. 参考与溯源

- 上游：https://github.com/microsoft/vscode
- Electron nightly 源：https://github.com/electron/nightlies
- Electron 头文件：https://electronjs.org/headers
- 官方更新 API：https://update.code.visualstudio.com/api/releases/{stable|insider}
- 商标参考：VSCodium 的处理方式（MIT 保留 + 禁用 MS 品牌词）
