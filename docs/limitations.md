# Known limitations and unproxyable traffic types

This document describes what the current `libproxychains_livecontainer.dylib`
can and cannot intercept, based on testing with Alook 20.3 and general iOS
networking architecture.

## Why Alook browser page loads are not proxied

Alook is a WKWebView-based browser. On iOS, WKWebView page loading is not done in
the app's main process. It is handled by a separate system process:

```
com.apple.WebKit.WebContent
```

LiveContainer injects the dylib into the hosted app's main process. It does not
normally inject into WebContent. Therefore:

- The dylib is loaded and fishhook is installed in the Alook main process.
- The main process's own `connect()` / `NSURLSession` traffic can be proxied.
- Actual web page loads, subresources, XHR/fetch inside WKWebView happen in
  WebContent and are **not** seen by the dylib.

This is why the browser still sees the original IP even though the dylib logs
show successful loading and configuration.

### What can still be proxied in Alook

Features that use the main process networking stack, for example:

- Direct `NSURLSession` requests made by the app itself
- Download tasks handled by the app process
- Plain BSD socket connections made by the app process

### How to cover WKWebView traffic

A userspace dylib hooking only the app process cannot cover WebContent. Practical
options are:

1. Inject the dylib into `com.apple.WebKit.WebContent` as well (requires
   LiveContainer / the injection mechanism to support injecting into child
   processes; not generally available).
2. Use a system-wide / network-level proxy:
   - HTTP proxy configured through a VPN (`NEPacketTunnelProvider`)
   - iptables/pf/firewall-level redirection (requires jailbreak/root)
   - a proxy running on the same network configured as the iOS system proxy
3. For a custom app, replace WKWebView with a networking stack that runs in the
   same process, or proxy at the server/CDN layer.

## General types of traffic the current dylib cannot proxy

| Gap | Reason |
|---|---|
| WKWebView page loads | Networking happens in `WebContent`, a separate process |
| App Extensions | Share/Action/Today/Widget extensions run in separate extension processes |
| XPC services / helper processes | Separate processes not injected by LiveContainer |
| UDP / QUIC / HTTP3 | proxychains only handles TCP `connect()` |
| ICMP / raw IP | Not TCP, not handled |
| `connectx()` with non-NULL IDs | The hook intentionally passes these through to avoid corrupting Network.framework state |
| Direct syscalls | Apps that call `syscall(SYS_connect)` / `SYS_connectx` directly bypass libSystem symbols |
| Connections already open before injection | Existing sockets are not migrated to the proxy |
| Local-network exclusions | Config `localnet` entries are intentionally sent direct |
| Private/self-contained network stacks | Apps embedding their own TCP/IP stack or using unusual APIs may not call hooked libSystem symbols |

## Recommendations

- To verify the dylib works, use an app/feature whose network requests are made
  in the main app process (e.g. a simple URLSession-based app, or Alook's own
  download manager if it uses main-process networking).
- For browsers and WKWebView-based apps, a dylib-only hook is not sufficient.
  Use a VPN-based proxy solution to cover all processes and protocols.
