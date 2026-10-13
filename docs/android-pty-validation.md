# Android PTY 验证与构建

## 本轮流程（2026-10-13）

1. 在固定 OpenCode 2.0.12 源码上完成账号并发、失效、retry、compaction、重启恢复回归。
2. 固定 Android Bun 1.4.0 和 Bionic bun-pty 动态库；依赖重装后重新校验并替换内嵌库。
3. 运行源码门禁并核对本轮提交 SHA 的云端类型检查及移动端 validate/E2E。
4. 仅在源码门禁通过后，从提交快照构建，在独立 XDG/数据库目录运行真实 PTY HTTP/WebSocket 冒烟。
5. 保存日志、校验和、源码 SHA 和启动/回退说明；正式 4096 服务不替换。

## 固定依赖

- Android Bun: `artifacts/transplant/android-bun/bun-1.4.0/bun`。
- bun-pty: 0.4.8；FFI 八个符号逐项校验。
- Bionic 库来源：`$HOME/app-work/pty-fix/lib/librust_pty_arm64_bionic.so`，可通过 `BIONIC_PTY_SOURCE` 指定等同文件。
- SHA-256: `1c119d94771daf50742e403731294e5d5d7799073e9eda865c987468450c1aec`。
- 校验后缓存至 `artifacts/transplant/pty-bionic/`；缓存独立于源码 `node_modules`。
- 测试通过 `BUN_PTY_LIB` 使用缓存；构建在最后一次 install 后替换 bun-pty 的 `librust_pty_arm64.so`，使编译产物内嵌 Bionic 库。

## 最小操作

```bash
V2_SRC=/path/to/opencode-2.0.12 bash scripts/test-bionic-pty.sh
VER=2.0.12 V2_SRC=/path/to/committed-source BUILD_ROOT=/path/to/new-output bash scripts/build-bionic.sh
```

构建目录同时保存 `librust_pty_arm64_bionic.so`、`pty.sha256` 和相对路径启动器 `run-opencode.sh`。
启动器拒绝缺失/校验失败的库，避免静默加载不兼容依赖。

## 证据状态

历史诊断构建与 Bun 段错误证据保存在 `$PREFIX/tmp/opencode-repro-2.0.12/`，不覆盖、不作为新源码验收。
完整测试命令、退出码和本轮结果集中写入该目录的验证记录。
persistent-PTY 使用独立的 `opencode-pty` 可执行文件；bun-pty Bionic 库不能替代它。
移动端当前 Terminal 页使用标准 `/api/pty`，依赖 `bun-pty`；源码定向的
7 项真实 PTY 测试仅验证这一路径。`/api/experimental/session/*/pty` 与
插件 persistent-PTY 使用另一个守护进程（协议 7、连接所有权、接管、输出回放、
Ghostty VT 快照）；验证这组可选能力需要 Android/Bionic 版 `opencode-pty`，
不能把已验证的 bun-pty 动态库当作守护进程可执行文件。当前 V2 编译脚本
会把 Linux arm64 glibc 守护进程嵌入产物；标准 PTY 通过并不证明这部分可用。

独立守护进程采用 `anomalyco/opencode-pty` v0.1.13 固定源码
（tag `v0.1.13` 指向提交 `42ef5b055f972196ea61aaea7a5e4a87405b29f0`）；其官方发布
流程固定 Zig 0.15.2，所依赖的 `libghostty-vt-sys` 0.2.1 从 Ghostty
提交 `a887df42c56f6de86c0fe6da9c4eeca37931e083` 读取 `build.zig.zon`。
首次缺失的 `uucode` 原始地址是
`https://deps.files.ghostty.org/uucode-0.2.0-ZZjBPqZVVABQepOqZHR7vV_NcaN-wats0IB6o-Exj6m9.tar.gz`，
锁定的 Zig 包内容哈希为
`uucode-0.2.0-ZZjBPqZVVABQepOqZHR7vV_NcaN-wats0IB6o-Exj6m9`。
本机 `curl` 对官方地址收到 200，下载文件 SHA-256 是
`d0abee0f4f8bd6eae3c051777e16e7c42d8964aaaa015591c4e565703f465f95`；
Zig 0.15.2 对文件计算的内容哈希与锁定值一致。Zig 直接联网报告
`TemporaryNameServerFailure`（连 GitHub 地址也失败），而系统解析及
`curl` 可用；因此用隔离目录保存官方压缩包，再用 `zig fetch` 校验并写入
本机 Zig 缓存，保留 `fetch-ghostty-locked.py` 与下载/编译日志作证据。
此下载错误不能算作独立守护进程编译或实验接口验证通过。
另已核对传递依赖：`vaxis` 的 `zigimg` 从固定 GitHub 提交的归档取得，
`git+https` 固定提交的 `uucode` 则使用同一仓库同一提交的 GitHub
归档；两者均由 Zig 0.15.2 验证与各自的锁定包内容哈希一致。
后续检查还需验证 Android 链接所用 sysroot：Ghostty 的
`pkg/android-ndk/build.zig` 在 Android 目标上查找 NDK 中的头文件、
crt 与库，并默认选 `linux-x86_64` 主机布局。本机 Android SDK 未发现
Google NDK；Termux 已安装 `ndk-sysroot`，但其目录不是 Ghostty 预期的
NDK 布局。即使全部锁定包下载完成，也不能在未验证链接输入和产物
运行前声称守护进程可用。
隔离试验使用复现目录中的 `prepare-termux-ndk-layout.py`，将已安装的
Termux `ndk-sysroot`、`ndk-multilib`、C++ 头文件和 CRT 通过符号链接
映射为 Ghostty 所需目录；另以同目录的 Zig 0.15.2 启动包装器显式
指定 `aarch64-linux-android`，不更改 Zig/Ghostty/Cargo 锁文件，也不
安装到正式服务。此映射仍需通过 `cargo check --locked`、正式链接与
实际运行三阶段验证，不可视作原版 Google NDK 的等价替代。
首轮映射到 API 24 的 CRT 路径不符合 Zig 实际选择的 Android API 29；
日志报 `crtbegin_so.o` 缺失及 `-lc/-lm/-ldl` 查找失败。映射现改为
API 29，并从 Termux 已安装的 Bionic multilib 链入对应库；保留失败
日志以区分依赖解析、libc 发现和最终链接问题。
API 29 下 `cargo check --locked --target aarch64-linux-android` 已通过，
但 `cargo build --locked --release` 仍在 Ghostty 0.15.2 的 release
链接阶段以 101 退出（`compile lib ghostty-vt ReleaseFast ... 1 errors`，
参见 `logs/stability/pty-bionic-release-v013-sysroot29.stderr.log`）。
按本轮范围决定，实验性 persistent-PTY 暂缓、不再追加修复或重试；
没有可交付的 Bionic `opencode-pty` 可执行文件。标准 `/api/pty` 当前
源码的真实测试另行通过 7/7，记录在
`logs/stability/standard-pty-current-source-final.stdout.log`。
只有实际运行且断言通过的测试计为通过；平台阻碍、跳过和待人工验收单独记录。

## 2026-10-13 提交快照构建结果

- 后端审查提交 `29675a6ff2fe30c8a9b250e0f2fd0502114769ea` 的 Fork
  `check / typecheck` 成功；移动端提交 `183905b57ec01b0a0206f9abfd96fcb4de0813b5`
  的 PR `validate` 成功（101 个 web E2E 通过）。
- 从后端提交的独立 worktree 构建返回 0；最后一次依赖安装后替换的
  `bun-pty` 内嵌库通过固定 SHA 校验。候选二进制 SHA-256：
  `4b8bbd9bae09045977ede36e7ebc5d0db0f8b584df54f7386faf86c00f5be94d`；
  sidecar SHA-256：`1c119d94771daf50742e403731294e5d5d7799073e9eda865c987468450c1aec`。
  候选文件和完整日志仅保存在隔离目录
  `$PREFIX/tmp/opencode-repro-2.0.12/artifacts/final-29675a/`、
  `logs/stability/delivery-20261013.md`。
- 构建脚本使用此前按版本缓存的 Web UI `dist`，目前不能独立证明它
  来源于本次提交；源码 worktree 中除依赖安装修改的三份 package/lock
  文件外没有其他跟踪文件变化。
- 在独立 `XDG_*` 数据目录和临时 loopback 端口首次启动这份新产物，
  `serve` 于监听前报 `Bad system call`（SIGSYS）。已有的
  `openat2_shim.so` 仅作一次针对性诊断仍失败；未开始 HTTP/WebSocket
  PTY 冒烟，没有最终可交付的运行产物。保留日志，不再无改动重试
  此失败路径；正式 4096 服务不切换。

Android `logcat` 对新产物的 SIGSYS 明确报告禁用的 syscall **436**
(`close_range`)；原 shim 只处理 437/452，所以第一次重试无效。现在
`openat2_shim.c` 仅针对实际出现的 `CLOSE_RANGE_CLOEXEC` 以
`/proc/self/fd` + `fcntl(FD_CLOEXEC)` 替代；其他模式返回 `ENOSYS`，
不假装已关闭文件描述符。候选二进制配合隔离编译的新 shim 已能启动，
并完成标准 PTY 创建、列表、票据、删除，但票据 WebSocket 升级返回
HTTP 500，服务端日志为 `abortHandshake` 内 `TypeError`，实际输入/输出
未验证。相应记录位于 `final-bionic-close-range-ws-29675a.*.log` 和
`runtime/final-29675a/data/opencode/log/opencode.log`；不能宣称修复
全部完成。构建脚本已改为从源码编译并校验相对路径的 runtime shim，
正式服务保持不变。之前生成的候选文件没有这项 launcher 修复，仍不交付。

## 2026-10-13 WebSocket 原因与重新构建约束

隔离的同一 PTY 请求在后端 `29675a6ff` 的源码及编译候选上均返回
WebSocket HTTP 500；旧的源码目录可以通过，但其后端源码不是该提交。
完整堆栈分别保存在 `runtime/exact-source-29675a/data/opencode/log/opencode-local.log`
和 `runtime/final-29675a/data/opencode/log/opencode.log`。在 Effect Node HTTP
升级路径插桩，证实请求携带有效 WebSocket headers，且 `ws` 的
`completeUpgrade()` 调用 Bun `server.upgrade()` 返回 false；随后
`abortHandshake()` 因缺少 response 又抛 TypeError，这只是二次错误。
根因是新加的 Location 中间件在升级前 `await fs.stat`，错过 Android Bun
1.4.0 的同步升级窗口。后端 `a53d48db1` 将升级请求改为同步 `statSync`，
非升级 HTTP 请求仍保持原来的异步校验；隔离源码同一请求已通过标准
PTY WebSocket 输入输出，详见 `exact-source-ws-sync-precheck.*.log`。

旧版按版本缓存的 Web UI `dist` 无法核实生成源码和过程，保留作证据，
不能复用于最终候选。`build-bionic.sh` 的新 UI 缓存按版本及 Git 提交
双重索引，`WEB_UI_FRESH=1` 必须在全新源码 worktree 中实际执行 Vite，
只在有 `built in` 完成标记和 `dist/index.html` 时容许 Android Bun 的
退出超时。构建记录包含 `web-ui-build.log`、`web-ui-source.sha` 和逐文件
SHA-256。Android syscall shim 在构建期处理 install/openat2/fchmodat2，
运行期还需处理禁用的 `close_range(436)`；仅 `CLOSE_RANGE_CLOEXEC` 模式
由 `/proc/self/fd` 和 libc `fcntl` 处理，其余模式 `ENOSYS`，并在启动器
中按相对路径核验 shim 校验和后 `LD_PRELOAD`。隔离 C 测试记录在
`close-range-shim-targeted-29675a.stdout.log`。必须从最终提交重新构建、
在隔离目录复测升级及重连后才能交付；正式 4096 服务保持不变。
