#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <WebKit/WebKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../vendor/proxychains-ng/src/common.h"

extern void proxychains_write_log(char *str, ...);

static nw_proxy_config_t g_lc_proxy_config;

static int lc_parse_proxy(char *host, size_t hostlen,
                          char *port, size_t portlen,
                          char *user, size_t userlen,
                          char *pass, size_t passlen) {
    char buf[1024];
    char path[1024];
    const char *conf = get_config_path(getenv("PROXYCHAINS_CONF_FILE"), path, sizeof(path));
    FILE *f;
    int in_list = 0;
    int found = 0;

    if (!conf)
        return 0;
    f = fopen(conf, "r");
    if (!f)
        return 0;

    while (fgets(buf, sizeof(buf), f)) {
        char *p = buf;
        char *nl;
        char type[32] = {0};
        char h[256] = {0};
        char pt[16] = {0};
        char u[128] = {0};
        char pw[128] = {0};
        int n;

        while (*p == ' ' || *p == '\t')
            p++;
        if (*p == '\n' || *p == '\r' || *p == '\0' || *p == '#')
            continue;

        nl = strchr(p, '\n');
        if (nl) *nl = 0;
        nl = strchr(p, '\r');
        if (nl) *nl = 0;

        if (!in_list) {
            if (strcmp(p, "[ProxyList]") == 0)
                in_list = 1;
            continue;
        }

        n = sscanf(p, "%31s %255s %15s %127s %127s", type, h, pt, u, pw);
        if (n >= 3 && strcmp(type, "http") == 0) {
            snprintf(host, hostlen, "%s", h);
            snprintf(port, portlen, "%s", pt);
            if (n >= 4)
                snprintf(user, userlen, "%s", u);
            else
                user[0] = 0;
            if (n >= 5)
                snprintf(pass, passlen, "%s", pw);
            else
                pass[0] = 0;
            found = 1;
            break;
        }
    }

    fclose(f);
    return found;
}

static int lc_create_proxy_config(void) {
    char host[256];
    char port[16];
    char user[128];
    char pass[128];
    nw_endpoint_t ep;

    if (g_lc_proxy_config)
        return 1;
    if (!lc_parse_proxy(host, sizeof(host), port, sizeof(port),
                        user, sizeof(user), pass, sizeof(pass)))
        return 0;
    if (!@available(iOS 17.0, *))
        return 0;

    ep = nw_endpoint_create_host(host, port);
    if (!ep)
        return 0;

    g_lc_proxy_config = nw_proxy_config_create_http_connect(ep, NULL);
    nw_release(ep);
    if (!g_lc_proxy_config)
        return 0;

    if (user[0])
        nw_proxy_config_set_username_and_password(g_lc_proxy_config, user, pass[0] ? pass : NULL);

    return 1;
}

static void lc_apply_proxy_to_store(id store) {
    NSArray *configs;

    if (!store)
        return;
    if (![store respondsToSelector:@selector(setProxyConfigurations:)])
        return;
    if (!lc_create_proxy_config())
        return;

    if (@available(iOS 17.0, *)) {
        configs = [NSArray arrayWithObjects:(id)g_lc_proxy_config, nil];
        [store setProxyConfigurations:configs];
    }
}

static IMP orig_setWebsiteDataStore;
static void lc_setWebsiteDataStore(id self, SEL _cmd, id store) {
    ((void (*)(id, SEL, id))orig_setWebsiteDataStore)(self, _cmd, store);
    lc_apply_proxy_to_store(store);
}

static IMP orig_nonPersistentDataStore;
static id lc_nonPersistentDataStore(id self, SEL _cmd) {
    id store = ((id (*)(id, SEL))orig_nonPersistentDataStore)(self, _cmd);
    lc_apply_proxy_to_store(store);
    return store;
}

void livecontainer_install_webkit_proxy(void) {
    Class wds;
    Class cfg;
    Method m;
    id (*msg)(id, SEL) = (id (*)(id, SEL))objc_msgSend;

    if (!lc_create_proxy_config()) {
        proxychains_write_log("[proxychains] webkit proxy: no usable HTTP proxy found, WKWebView proxy disabled\n");
        return;
    }

    wds = NSClassFromString(@"WKWebsiteDataStore");
    if (wds) {
        proxychains_write_log("[proxychains] webkit proxy: applying HTTP proxy to WKWebsiteDataStore\n");
        id defaultStore = msg(wds, sel_registerName("defaultDataStore"));
        lc_apply_proxy_to_store(defaultStore);

        m = class_getClassMethod(wds, sel_registerName("nonPersistentDataStore"));
        if (m) {
            orig_nonPersistentDataStore = method_getImplementation(m);
            method_setImplementation(m, (IMP)lc_nonPersistentDataStore);
        }
    }

    if (!wds)
        proxychains_write_log("[proxychains] webkit proxy: WKWebsiteDataStore unavailable\n");

    cfg = NSClassFromString(@"WKWebViewConfiguration");
    if (cfg) {
        m = class_getInstanceMethod(cfg, sel_registerName("setWebsiteDataStore:"));
        if (m) {
            orig_setWebsiteDataStore = method_getImplementation(m);
            method_setImplementation(m, (IMP)lc_setWebsiteDataStore);
        }
    }
}
