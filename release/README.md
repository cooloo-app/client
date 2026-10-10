# release — dev-phase binaries (Git LFS)

预编译二进制，**Git LFS 跟踪**。开发期免搭构建环境，clone 后可直接运行/
拷贝到目标机测试。重新发布流程见文末。

## 二进制

| 文件 | 平台 | 大小 | sha256 |
|---|---|---|---|
| `cooloo-darwin-arm64` | macOS 26 arm64（Apple Silicon） | 2.4MB | `46e5a12b9991f5c93e5b0dbd095bc5dad19eb2fa848f20cbb2df374ccc53338b` |
| `cooloo-windows-x86_64.exe` | Windows 10+ x86_64（mingw 静态，仅系统 DLL） | 3.9MB | `586f549cdc7b0bca9ca24895e7db0d78abaa57258729f631ba4585d2d2baddd3` |

来源：客户端 tag `v0.1.0`（基于 `0c8241d`；透明橙色 C 图标、Windows GUI
子系统、`--debug` 控制台与标准流兼容、移除 `gui` 子命令）。
在 m106 隔离构建目录生成，未修改远程 checkout。
构建日期 2026-10-10。macOS CLI 集成测试 24/24；Windows 真机启动、窗口大小
图标、控制台有无、TOFU 输入、多行管道 send/read、重定向与退出码测试通过。
Linux GUI 本期不交付（owner 决策），无 linux 二进制。

## 使用

```sh
# macOS（Apple Silicon）：下载后直接运行（裸跑 = GUI）
chmod +x cooloo-darwin-arm64
./cooloo-darwin-arm64              # GUI
./cooloo-darwin-arm64 send general "hi"   # CLI 用法不变

# Windows：双击 cooloo-windows-x86_64.exe 或命令行运行（单 exe 双模）
cooloo-windows-x86_64.exe          # GUI（无控制台窗口，不需要 gui 子命令）
cooloo-windows-x86_64.exe --debug  # GUI + 控制台日志
cooloo-windows-x86_64.exe send general "hi"
# CMD 交互启动若需要同步等待：
start "" /wait cooloo-windows-x86_64.exe --debug
```

- EXE 与窗口图标为透明底橙色 C（`#D9622B`），资源内嵌，无需附带图片。
- Windows Explorer/任务栏会缓存图标；若显示旧图标，先取消旧固定快捷方式再重新固定。
- 首次运行自动创建 `~/.config/cooloo/`（identity / known_servers / config）
- 未注册机器会进入注册引导（输 nick → HELLO 注册）
- 校验：`shasum -a 256 <file>` 与上表比对
- Windows 二进制真机首测发现握手 RNG 缺陷（`/dev/urandom` 不存在 → msg1 生成
  失败，见 `../../progress/handoff/20260906-windows-noise-rng-fix.md`），已于
  2026-09-06 修复；2026-09-07 真机复测再暴露注册流程 D25 竞态 + Windows kv
  持久化两缺陷（见 `../../progress/handoff/20260907-register-race-fix.md`），已
  修复并重出二进制，**注册全流程 Windows 真机验证通过**；macOS 版本协议层
  实测通过（见 planner `progress/handoff/20250906-v2-done.md` §5）

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
