# Makefile for building libproxychains_livecontainer.dylib
# for iOS LiveContainer (iOS 18, arm64).
#
# Requirements: macOS with Xcode command line tools.
# Usage:
#   make
#   make install DESTDIR=...
#
# The output is a single self-hooking dylib. It uses dyld interposing
# (same mechanism as proxychains-ng on macOS Monterey+) plus fishhook runtime
# rebinding, so it works both when loaded early and when LiveContainer dlopen()s
# it after the app is already running. No MobileSubstrate/CydiaSubstrate needed.

ARCH ?= arm64
IOS_DEPLOYMENT_TARGET ?= 15.0
SDKROOT ?= $(shell xcrun --sdk iphoneos --show-sdk-path)
CC ?= $(shell xcrun --sdk iphoneos --find clang)
CODESIGN ?= codesign

VENDOR := vendor/proxychains-ng
SRC := $(VENDOR)/src
FISHHOOK_DIR := fishhook

PRODUCT := libproxychains_livecontainer.dylib
CONFIG  := proxychains.conf

OBJS := \
	$(FISHHOOK_DIR)/fishhook.o \
	$(SRC)/version.o \
	$(SRC)/core.o \
	$(SRC)/common.o \
	$(SRC)/libproxychains.o \
	$(SRC)/allocator_thread.o \
	$(SRC)/rdns.o \
	$(SRC)/hostsreader.o \
	$(SRC)/hash.o \
	$(SRC)/debug.o

CPPFLAGS := -D_GNU_SOURCE -D_DARWIN_C_SOURCE -DIS_MAC=1 -DMONTEREY_HOOKING -DSUPER_SECURE \
	-DGN_NODELEN_T=socklen_t -DGN_SERVLEN_T=socklen_t -DGN_FLAGS_T=int \
	-DHAVE_CLOCK_GETTIME

CFLAGS := -std=c99 -Wall -O2 -fPIC \
	-Ifishhook -isysroot $(SDKROOT) -arch $(ARCH) -miphoneos-version-min=$(IOS_DEPLOYMENT_TARGET)

LDFLAGS := -dynamiclib -arch $(ARCH) -isysroot $(SDKROOT) \
	-miphoneos-version-min=$(IOS_DEPLOYMENT_TARGET) \
	-Wl,-install_name,@rpath/$(PRODUCT) \
	-Wl,-current_version,4.17.0 -Wl,-compatibility_version,4.0.0 \
	-Wl,-dead_strip_dylibs

all: $(PRODUCT) sign

$(PRODUCT): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

$(FISHHOOK_DIR)/fishhook.o: $(FISHHOOK_DIR)/fishhook.c $(FISHHOOK_DIR)/fishhook.h
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

$(SRC)/version.o: $(SRC)/version.h

$(SRC)/%.o: $(SRC)/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

sign: $(PRODUCT)
	$(CODESIGN) --force --sign - $(PRODUCT)

clean:
	rm -f $(PRODUCT) $(OBJS) $(FISHHOOK_DIR)/fishhook.o

install: all
	install -d $(DESTDIR)/Library/MobileSubstrate/DynamicLibraries $(DESTDIR)/usr/lib
	install -m 755 $(PRODUCT) $(DESTDIR)/Library/MobileSubstrate/DynamicLibraries/$(PRODUCT)
	install -m 755 $(PRODUCT) $(DESTDIR)/usr/lib/$(PRODUCT)
	install -m 644 $(CONFIG) $(DESTDIR)/etc/proxychains.conf

.PHONY: all sign clean install
