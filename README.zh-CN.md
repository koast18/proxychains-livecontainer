# proxychains-livecontainer

一个用于 **LiveContainer（iOS 18.6.2）** 的单一自挂钩 dylib，让 LiveContainer 里运行的
所有 App 的 TCP 网络请求都通过 **HTTP 代理**（HTTP CONNECT）转发。

基于：

- [rofl0r/proxychains-ng](https://github.com/rofl0r/proxychains-ng) tag **v4.17**
- [Qusic/proxychains-ios](https://github.com/Qusic/proxychains-ios) 作为 iOS 集成参考

原来的 proxychains-ios 依赖 Cydia Substrate（`MSHookFunction`），而 LiveContainer 通常
不需要越狱 / Substrate。本项目改用 proxychains-ng 在 macOS 12+ 上使用的 dyld interpose
机制：dylib 自带 `__DATA,__interpose` 段，由 LiveContainer 提前加载即可全局生效。
另外还额外 hook 了 `connectx()`，覆盖 Apple 新版 Network.framework / NSURLSession
可能使用的连接路径。

## 构建

需要 macOS + Xcode 命令行工具：

```sh
cd livecontainer-proxychains
make
```

产物：`libproxychains_livecontainer.dylib`（默认 arm64，ad-hoc 签名）。

如果需要更详细的 debug 日志，可以构建 debug 版：

```sh
make clean
make DEBUG=1
```

产物为 `libproxychains_livecontainer_debug.dylib`。GitHub Release 里会同时提供普通版和 debug 版。

如需重新拉取上游 v4.17 并重新应用补丁：

```sh
./scripts/setup.sh
```

## 使用 GitHub Actions 构建

仓库自带 `.github/workflows/build.yml`。推送 `v0.1.0` 这样的 tag 后，会在 macOS runner
上自动编译，并把 dylib 上传到 GitHub Release：

```sh
git tag v0.1.0
git push origin v0.1.0
```

也可以手动在 Actions 页面触发；非 tag 触发时产物会作为 workflow artifact 提供。

## 安装到 LiveContainer

1. 把 `libproxychains_livecontainer.dylib` 放到 LiveContainer 的 dylib 注入目录，
   并设置为对所有宿主 App 注入。
2. 把 `proxychains.conf` 放到 dylib 同目录，或：
   - `$HOME/Documents/proxychains.conf`
   - `$HOME/Library/Preferences/proxychains.conf`
   - `$HOME/.proxychains/proxychains.conf`
   - `$HOME/config/settings/proxychains.conf`
   - `$HOME/Documents/config/proxychanins/proxychains.conf`
   - `$HOME/Documents/config/proxychains/proxychains.conf`
   - dylib 同目录
   - dylib 的 `../config/proxychanins/proxychains.conf`
   - dylib 的 `../config/proxychains/proxychains.conf`
   - `/etc/proxychains.conf`
3. 编辑 `proxychains.conf`，把代理改成你的 HTTP 代理：

```
[ProxyList]
http 192.168.1.10 8080
```

4. 重启 LiveContainer / 宿主 App。

## 诊断

dylib 会把日志写入：

```
$HOME/Documents/proxychains.log
```

也可以通过环境变量 `PROXYCHAINS_LOG_FILE` 指定其他路径。

- 如果没生效，先看 `proxychains.log`：
  - `DLL init: proxychains-ng ...`：dylib 已被加载。
  - `dylib path: ...`：显示实际加载的 dylib 路径。
  - `config file found: ...`：说明找到了 `proxychains.conf`。
  - `Dynamic chain ... OK`：说明某条 TCP 连接已成功走代理。
  - `couldnt find configuration file`：配置文件不在搜索路径中。
- 如果日志文件完全不存在，说明 dylib 可能没有被注入到宿主 App 进程。
- 如果找到了配置但没有代理连接日志，可能是 App 走了未 hook 的路径（例如带非 NULL 连接 ID 的 `connectx`、UDP/QUIC 或私有网络栈）。
- 也可以看 LiveContainer / 系统日志里以 `[proxychains]` 开头的输出。

## 说明

- 使用 `-DMONTEREY_HOOKING` 编译，无需 Substrate。
- 同时使用 dyld interpose 和 fishhook 运行时重绑定；即使 LiveContainer 是在 App 启动后才 `dlopen()` 注入 dylib，也能尽量 hook 到网络函数。
- 找不到配置时不会让 App 崩溃，而是直连放行。
- 默认排除 loopback，避免代理自身和 LiveContainer 内部被递归代理。
- `connectx` 为尽力而为：带非 NULL 连接 ID 的调用会直接放行，避免破坏 Apple Network.framework 状态。
- 许可证：GPLv2。
