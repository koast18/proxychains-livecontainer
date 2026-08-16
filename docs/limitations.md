# Known limitations and unproxyable traffic types

This document describes what the current `libproxychains_livecontainer.dylib`
can and cannot intercept, based on testing with Alook 20.3 and general iOS
networking architecture.

## WKWebView support

Alook is a WKWebView-based browser. On iOS, WKWebView page loading is not done in
the app's main process. It is handled by a separate system process:

```
com.apple.WebKit.WebContent
```

A plain libSystem hook in the app process cannot see WebContent traffic.
However, starting with iOS 17, WebKit exposes:

```
WKWebsiteDataStore.proxyConfigurations
```

This lets the app process tell WebKit to use an HTTP CONNECT proxy for all
WKWebViews that share that data store. The dylib now:

1. Applies the proxy to `[WKWebsiteDataStore defaultDataStore]`.
2. Swizzles `+[WKWebsiteDataStore nonPersistentDataStore]` so new non-persistent
   stores also get the proxy.
3. Swizzles `-[WKWebViewConfiguration setWebsiteDataStore:]` so custom stores
   assigned to WKWebView configurations also get the proxy.

This is the practical way to cover WKWebView page loads without injecting into
the WebContent process.

### Caveats

- Requires iOS 17 or newer (the user's iOS 18.6 is fine).
- If an app builds a `WKWebsiteDataStore` through a private path not covered by
  the swizzles above, it may still bypass the proxy.
- WebKit may cache the network process / data store configuration; if a web view
  is created before the dylib is loaded, restarting the app is needed.

## General types of traffic the current dylib cannot proxy

| Gap | Reason |
|---|---|
| WKWebView page loads | Covered on iOS 17+ via `WKWebsiteDataStore.proxyConfigurations`; not covered if the app uses a private/uncached data store path |
| App Extensions | Share/Action/Today/Widget extensions run in separate extension processes |
| XPC services / helper processes | Separate processes not injected by LiveContainer |
| UDP / QUIC / HTTP3 | proxychains only handles TCP `connect()` |
| ICMP / raw IP | Not TCP, not handled |
| `connectx()` with non-NULL IDs | The hook intentionally passes these through to avoid corrupting Network.framework state |
| Direct syscalls | Apps that call `syscall(SYS_connect)` / `SYS_connectx` directly bypass libSystem symbols |
| Connections already open before injection | Existing sockets are not migrated to the proxy |
| Local-network exclusions | Config `localnet` entries are intentionally sent direct |
| Private/self-contained network stacks | Apps embedding their own TCP/IP stack or using unusual APIs may not call hooked libSystem symbols |

## Bypass surface and current countermeasures

| Potential bypass | How it can happen | Current status / solution |
|---|---|---|
| WKWebView page loads | WebContent process | Solved on iOS 17+ via `WKWebsiteDataStore.proxyConfigurations` |
| Private/custom WKWebsiteDataStore paths | App creates stores through non-default/non-persistent methods not swizzled | Partially solved; can add more swizzles (`dataStoreForIdentifier:`, `_WKWebsiteDataStoreConfiguration`) if needed |
| UDP / QUIC / HTTP3 | App uses UDP-based transports, not TCP CONNECT | Can be forced to TCP by enabling `block_non_tcp` (drops UDP/QUIC); for full UDP proxying use HTTP/3 relay proxy config or VPN |
| Direct `syscall(SYS_connect)` / `SYS_connectx` | App bypasses libSystem wrappers | Not currently hooked; can add `syscall()`/`syscall_async` hooks in a future version |
| `connectx()` with non-NULL `pcid`/`connid`/`ext` | Network.framework / NWConnection paths | Currently passed through; can be improved by applying proxy at NWConnection level or using `nw_proxy_config` more broadly |
| App Extensions | Share/Action/Today/Widget run in separate processes | Not covered; requires per-process injection or VPN |
| XPC / helper processes | App spawns or talks to XPC services | Not covered; requires per-process injection or VPN |
| Background `NSURLSession` tasks | Handled by `nsurlsessiond` outside the app process | Not covered; needs VPN/system-level proxy |
| Already-established sockets | Opened before dylib injection | Not migrated; restart the app after enabling the dylib |
| Local network / localhost | Config `localnet` bypass | Intentional; remove localnet entries if you want those proxied too |
| Private/embedded network stacks | App implements its own TCP/IP in userspace | Cannot be hooked at libSystem level; use VPN/network-level redirection |

## Recommendations

- To verify the dylib works, use an app/feature whose network requests are made
  in the main app process (e.g. a simple URLSession-based app, or Alook's own
  download manager if it uses main-process networking).
- For WKWebView-based browsers, use v0.1.5+ so the dylib sets
  `WKWebsiteDataStore.proxyConfigurations`. If that still does not work for a
  particular app, the app is likely using a data store path not covered by the
  swizzles, and a VPN-based proxy solution remains the most robust fallback.
