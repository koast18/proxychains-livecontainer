# proxychains-livecontainer

A single self-hooking dylib for **LiveContainer on iOS 18.6.2** that makes TCP
network requests from every app running inside LiveContainer go through an
**HTTP proxy** (HTTP CONNECT).

It is based on:

- [rofl0r/proxychains-ng](https://github.com/rofl0r/proxychains-ng) at tag **v4.17**
- [Qusic/proxychains-ios](https://github.com/Qusic/proxychains-ios) as the iOS integration reference

The original proxychains-ios loader depends on Cydia Substrate (`MSHookFunction`).
LiveContainer normally runs without jailbreak / Substrate, so this project uses the
same dyld interposing technique that proxychains-ng uses on macOS 12+:
the dylib carries a `__DATA,__interpose` section and is loaded early by LiveContainer.
It also hooks `connectx()` in addition to `connect()`, covering Apple's newer
Network.framework/NSURLSession socket path.

## Features

- One dylib: `libproxychains_livecontainer.dylib`
- No Substrate / jailbreak dependency
- Uses dyld interposing **and** fishhook runtime rebinding, so it also works when
  LiveContainer loads the dylib with `dlopen()` after the app is already running
- Sets `WKWebsiteDataStore.proxyConfigurations` so WKWebView-based apps (browsers)
  can also use the HTTP proxy on iOS 17+
- Hooks:
  - `connect`
  - `connectx` (when built with `MONTEREY_HOOKING`, the default)
  - `getaddrinfo` / `gethostbyname` / `getnameinfo` / `gethostbyaddr`
  - `sendto` (for TCP fast-open)
  - `close` / `close_range`
- HTTP proxy support from proxychains-ng 4.17
- Missing/invalid config does **not** kill the host app; proxying is disabled
  until a valid config is provided.

## Build

Requires macOS with Xcode command line tools.

```sh
cd livecontainer-proxychains
make
```

Output:

```
libproxychains_livecontainer.dylib
```

To re-fetch the pristine upstream v4.17 and re-apply the LiveContainer patch:

```sh
./scripts/setup.sh
```

The Makefile defaults to `arm64`, iOS deployment target 15.0, and ad-hoc codesigns
the dylib. To override:

```sh
make ARCH=arm64 IOS_DEPLOYMENT_TARGET=15.0
```

To build the verbose debug dylib (writes much more detail to the log file):

```sh
make clean
make DEBUG=1
```

Debug output file: `libproxychains_livecontainer_debug.dylib`. GitHub Releases
contain both the normal and debug dylibs.

## Use as part of another dylib

You can compile this project into your own tweak/dylib instead of loading the
standalone dylib.

Build the static archive:

```sh
make static
```

Then link `libproxychains_livecontainer.a` into your dylib. Make sure your final
dylib also links:

```sh
-framework Foundation -Wl,-weak_framework,WebKit -Wl,-weak_framework,Network
```

and is compiled with the same `MONTEREY_HOOKING` flags. The constructor inside
`libproxychains.c` will initialize proxychains automatically when your dylib is
loaded. The config file will be searched relative to your combined dylib.

## Build with GitHub Actions

This repository includes `.github/workflows/build.yml`. Pushing a tag like `v0.1.0`
builds the dylib on a macOS runner and uploads it to a GitHub Release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

You can also run the workflow manually from the Actions tab; the artifact is then
available as a workflow artifact instead of a Release.

## Install into LiveContainer

1. Copy `libproxychains_livecontainer.dylib` into LiveContainer's dylib/tweak
   injection directory (usually the LiveContainer app's `Documents` or the
   "Load Dylibs" folder). Make sure LiveContainer is configured to inject it
   into **all hosted apps**.
2. Copy `proxychains.conf` next to the dylib, or to one of:
   - `$HOME/Documents/proxychains.conf`
   - `$HOME/Library/Preferences/proxychains.conf`
   - `$HOME/.proxychains/proxychains.conf`
   - `/etc/proxychains.conf`
3. Edit `proxychains.conf` and set your HTTP proxy:

```
[ProxyList]
http 192.168.1.10 8080
```

4. Relaunch LiveContainer / the hosted app. All TCP connections from hosted apps
   should now go through the HTTP proxy.

## Configuration

The config format is the standard proxychains-ng format. A sample is in
[`proxychains.conf`](./proxychains.conf).

The dylib searches for the config in this order:

1. `PROXYCHAINS_CONF_FILE` environment variable
2. current working directory
3. `$HOME/.proxychains/proxychains.conf`
4. `$HOME/config/settings/proxychains.conf`
5. `$HOME/Documents/proxychains.conf`
6. `$HOME/Library/Preferences/proxychains.conf`
7. `$HOME/Documents/config/proxychanins/proxychains.conf`
8. `$HOME/Documents/config/proxychains/proxychains.conf`
9. same directory as the dylib
10. `../config/proxychanins/proxychains.conf` relative to the dylib
11. `../config/proxychains/proxychains.conf` relative to the dylib
12. `SYSCONFDIR` and `/etc`

If no config is found, the dylib logs a message and passes traffic through
unmodified instead of crashing the app.

To prevent non-TCP traffic (UDP, QUIC/HTTP3, ICMP, raw sockets) from bypassing
the proxy, add this line to `proxychains.conf`:

```
block_non_tcp
```

This makes the dylib drop non-TCP socket sends/connects instead of letting them
go direct. It can break UDP-based features (games, VoIP, video calls), so only
enable it when you want a strict no-leak mode.

## How it works

- The proxychains-ng library is compiled with `-DMONTEREY_HOOKING`.
- Its replacement functions (`pxcng_connect`, `pxcng_getaddrinfo`, etc.) are
  registered in `__DATA,__interpose`.
- In addition, fishhook rebinds the same symbols at runtime, which covers the
  LiveContainer case where the dylib is `dlopen()`ed after the app is already
  running.
- `connect()` and `connectx()` calls are redirected through proxychains' core,
  which opens a TCP connection to the HTTP proxy and performs an HTTP CONNECT
  tunnel to the real destination.
- DNS hooks (`proxy_dns`) can optionally return internal IPs and send the real
  hostname to the proxy, avoiding local DNS leaks.

## Known limitations

See [docs/limitations.md](./docs/limitations.md) for details about traffic that cannot be proxied (app extensions, UDP/QUIC, etc.). WKWebView page loads are now covered on iOS 17+ through `WKWebsiteDataStore.proxyConfigurations`.

## Troubleshooting

The dylib writes diagnostics to a log file. By default it uses:

```
$HOME/Documents/proxychains.log
```

You can override it with the `PROXYCHAINS_LOG_FILE` environment variable.

- If nothing is proxied, first open `proxychains.log` and check:
  - `DLL init: proxychains-ng ...` → the dylib was loaded.
  - `dylib path: ...` → shows which copy of the dylib LiveContainer loaded.
  - `config file found: ...` → confirms your `proxychains.conf` was located.
  - `Dynamic chain ... OK` → a proxied TCP connection succeeded.
  - `couldnt find configuration file` → the config is not in a searched path.
- If the log file does not exist at all, the dylib is probably not being
  injected/loaded into the hosted app process.
- If `config file found` appears but no proxy chain lines appear, the app may be
  using a code path the dylib does not hook (for example `connectx` with
  non-NULL connection IDs, UDP/QUIC, or a custom network stack).
- Run a hosted app that prints stderr, or check LiveContainer's system log /
  console for lines starting with `[proxychains]`.
- Use a proxy server that supports HTTP CONNECT (most HTTP proxies do).
- The `connectx` hook is best-effort: calls that use non-NULL connection IDs are passed through to avoid corrupting Apple's Network.framework state.
- Loopback (`127.0.0.1`, `::1`) is excluded in the sample config so the proxy
  itself and LiveContainer internals are not recursively proxied.

## License

GPLv2, same as proxychains-ng.
