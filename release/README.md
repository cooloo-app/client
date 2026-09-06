# release — dev-phase binaries (Git LFS)

预编译二进制，**Git LFS 跟踪**。开发期免搭构建环境，clone 后可直接运行/
拷贝到目标机测试。重新发布流程见文末。

## 二进制

| 文件 | 平台 | 大小 | sha256 |
|---|---|---|---|
| `cooloo-darwin-arm64` | macOS 26 arm64（Apple Silicon） | 2.2MB | `2a838fe5ed41b61ac590edc5145da178109c87a0f37a776ebfbde6f48f9d67f7` |
| `cooloo-windows-x86_64.exe` | Windows 10+ x86_64（mingw 静态，仅系统 DLL） | 3.8MB | `28938ada23cd4e57b73ca723476da797f0829229f2a043ad2b3586e38966e874` |

来源 commit：`83ae4fe`（v3: port GUI to SDL3）。构建日期 2026-09-06。
Linux GUI 本期不交付（owner 决策），无 linux 二进制。

## 使用

```sh
# macOS（Apple Silicon）：下载后直接运行（裸跑 = GUI）
chmod +x cooloo-darwin-arm64
./cooloo-darwin-arm64              # GUI
./cooloo-darwin-arm64 send general "hi"   # CLI 用法不变

# Windows：双击 cooloo-windows-x86_64.exe 或命令行运行（单 exe 双模）
cooloo-windows-x86_64.exe          # GUI（带控制台窗口，设计如此）
cooloo-windows-x86_64.exe send general "hi"
```

- 首次运行自动创建 `~/.config/cooloo/`（identity / known_servers / config）
- 未注册机器会进入注册引导（输 nick → HELLO 注册）
- 校验：`shasum -a 256 <file>` 与上表比对
- Windows 二进制**尚未在真机验证**（无测试机）；macOS 版本协议层实测通过，
  键盘/IME 路径待真机目检（见 planner `progress/handoff/20250906-v2-done.md` §5）

## 重新发布（更新二进制后）

```sh
cd client
make                          # 本机 macOS arm64 构建
make release-windows          # mingw-w64 交叉构建（brew install mingw-w64）
cp cooloo release/cooloo-darwin-arm64
cp cooloo.exe release/cooloo-windows-x86_64.exe
shasum -a 256 release/*       # 更新上表 sha256 与构建日期
git add .gitattributes release/
git commit -m "release: refresh binaries (commit <hash>)"
git push                      # LFS 对象随 push 自动上传
```

> Git LFS 前提：`git lfs install`；克隆时自动检出 LFS 文件
> （`GIT_LFS_SKIP_SMUDGE=1` 可跳过，仅取指针）。
