# XII Code

基于 [VS Code](https://github.com/microsoft/vscode) 源码自编译、品牌化的定制版 IDE（上游基于 Microsoft，MIT 许可）。

- 上游：`microsoft/vscode`（MIT License）
- 运行框架：Electron（固定 pin 到官方 nightly，可随时升级/回退）
- 双通道：**Stable**（对应官方 stable 最新发版）与 **Insiders**（对应官方 insider 最新发版），数据目录/互斥名/GUID 完全隔离，可与已安装的官方 VS Code 共存。

> 本项目 "based on VS Code by Microsoft, licensed under MIT"。

## 构建

- 本地构建（需要 Node ≥ 24.18.0 + VS2022 C++ 工具链）：见 `scripts/`
  ```powershell
  .\scripts\prepare.ps1 -Channel stable
  .\scripts\build.ps1 -Channel stable
  ```
- CI（无本地 Node 依赖）：GitHub Actions `ci.yml`，每 6 小时自动探测上游 stable / insider 与 Electron nightly，有更新则构建对应通道，产物 8h 后自动过期。

## 渠道

| 维度 | Stable 通道 | Insiders 通道 |
|---|---|---|
| 构建来源 | 官方 stable 最新发版 | 官方 insider 最新发版 |
| 产物 | `XII Code Setup <ver>.exe` | `XII Code Insiders Setup <ver>-insider.exe` |
| 数据目录 | `.xii-code` | `.xii-code-insider` |

## 参考

- 上游：https://github.com/microsoft/vscode
- Electron nightly 源：https://github.com/electron/nightlies
- 官方更新 API：https://update.code.visualstudio.com/api/releases/{stable|insider}
