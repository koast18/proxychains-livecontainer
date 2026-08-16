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
7. same directory as the dylib
8. `SYSCONFDIR` and `/etc`

If no config is found, the dylib logs a message and passes traffic through
unmodified instead of crashing the app.

## How it works

- The proxychains-ng library is compiled with `-DMONTEREY_HOOKING`.
- Its replacement functions (`pxcng_connect`, `pxcng_getaddrinfo`, etc.) are
  registered in `__DATA,__interpose`.
- LiveContainer loads the dylib before hosted app code runs, so dyld interposes
  those libSystem symbols process-wide.
- `connect()` and `connectx()` calls are redirected through proxychains' core,
  which opens a TCP connection to the HTTP proxy and performs an HTTP CONNECT
  tunnel to the real destination.
- DNS hooks (`proxy_dns`) can optionally return internal IPs and send the real
  hostname to the proxy, avoiding local DNS leaks.

## Troubleshooting

- If nothing is proxied, confirm the dylib is actually loaded by LiveContainer
  and that `proxychains.conf` is readable.
- Run a hosted app that prints stderr, or check LiveContainer's system log /
  console for lines starting with `[proxychains]`.
- Use a proxy server that supports HTTP CONNECT (most HTTP proxies do).
- The `connectx` hook is best-effort: calls that use non-NULL connection IDs are passed through to avoid corrupting Apple's Network.framework state.
- Loopback (`127.0.0.1`, `::1`) is excluded in the sample config so the proxy
  itself and LiveContainer internals are not recursively proxied.

## License

GPLv2, same as proxychains-ng.
