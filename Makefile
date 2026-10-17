# cooloo client - single binary: CLI + v0.3 modular workbench
# bare `cooloo` -> short help; --gui -> GUI (SDL3+Lua); subcommands -> CLI.
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99
PREFIX  ?= /usr/local
CMAKE   := $(shell command -v cmake 2>/dev/null || echo /opt/homebrew/bin/cmake)
BUILD   := build

# --- SDL3 static sub-build (vendored source, video+events only, sw rendering)
SDL_MAC     := $(BUILD)/sdl3-mac
SDL_MAC_LIB := $(SDL_MAC)/libSDL3.a
SDL_WIN     := $(BUILD)/sdl3-win
SDL_WIN_LIB := $(SDL_WIN)/libSDL3.a

SDL_CMAKE_FLAGS := -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=OFF -DSDL_STATIC=ON \
	-DSDL_TEST_LIBRARY=OFF -DSDL_TESTS=OFF -DSDL_AUDIO=OFF -DSDL_HAPTIC=OFF \
	-DSDL_JOYSTICK=OFF -DSDL_SENSOR=OFF -DSDL_HIDAPI=OFF -DSDL_POWER=OFF \
	-DSDL_GPU=OFF -DSDL_CAMERA=OFF -DSDL_DIALOG=OFF \
	-DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_VULKAN=OFF \
	-DSDL_INSTALL=OFF

# macOS: SDL3 removed SDL2's Cocoa window framebuffer; SDL_GetWindowSurface
# is served by the texture-framebuffer fallback, which only accepts a
# hardware render driver -> needs the render subsystem + Metal backend.
# (Still our own software canvas; Metal only presents the final bitmap.)
MACOS_MIN ?= 11.0
NATIVE_PLATFORM_FLAGS := $(if $(filter Darwin,$(shell uname -s)),-mmacosx-version-min=$(MACOS_MIN))
SDL_MAC_CMAKE_FLAGS := $(SDL_CMAKE_FLAGS) -DCMAKE_OSX_DEPLOYMENT_TARGET=$(MACOS_MIN) -DSDL_RENDER=ON -DSDL_METAL=ON
# Windows: the GDI window framebuffer is always available, keep render off.
SDL_WIN_CMAKE_FLAGS := $(SDL_CMAKE_FLAGS) -DSDL_RENDER=OFF -DSDL_METAL=OFF

NOISE_SRC := src/noise_xx.c src/vendor/monocypher.c
LUA_SRC   := $(filter-out src/vendor/lua/lua.c src/vendor/lua/luac.c,$(wildcard src/vendor/lua/*.c))
CLIENT_SRC := src/net.c src/config.c src/record.c $(NOISE_SRC)
CLI_SRC := src/main.c src/win_console.c src/cli.c src/machine.c
CORE_SRC  := $(CLI_SRC) $(CLIENT_SRC)
RUNTIME_SRC := modules/runtime/runner.c modules/runtime/process.c
TEXT_GUI_SRC := src/gui.c src/font.c src/luabind.c modules/platform/api.c
GUI_SRC   := $(TEXT_GUI_SRC) $(RUNTIME_SRC)
EMBED_SRC := $(BUILD)/embedded_workbench.c src/embedded_font.c
EDITOR_SRC := apps/editor/main.c $(TEXT_GUI_SRC) $(LUA_SRC) $(BUILD)/embedded_editor.c src/embedded_font.c
WORKBENCH_CLI_SRC := apps/workbench/main.c src/record.c modules/runtime/runner.c $(LUA_SRC) $(BUILD)/embedded_workbench_cli.c
WORKBENCH_LUA := $(shell find modules adapters apps -name '*.lua')
CFLAGS += -Imodules/platform -Imodules/runtime
ALL_SRC   := $(CORE_SRC) $(GUI_SRC) adapters/cooloo/script.c adapters/cooloo/cache.c $(LUA_SRC) $(EMBED_SRC)
HEADERS   := $(wildcard src/*.h) $(wildcard modules/*/*.h) $(wildcard adapters/*/*.h) $(wildcard src/vendor/lua/*.h) src/vendor/stb_truetype.h

# SDL3 public headers are self-contained; no generated-config include needed
SDL_MAC_INC := -Isrc/vendor/sdl3/include -Isrc/vendor/lua
SDL_WIN_INC := -Isrc/vendor/sdl3/include -Isrc/vendor/lua
MAC_LIBS  := $(SDL_MAC_LIB) -framework Cocoa -framework Carbon -framework IOKit \
	-framework CoreFoundation -framework CoreVideo \
	-framework UniformTypeIdentifiers -framework Metal -framework QuartzCore \
	-liconv -lm
WIN_LIBS  := $(SDL_WIN_LIB) -lwinmm -lole32 -loleaut32 -limm32 -lversion -luuid \
	-ladvapi32 -lsetupapi -lshell32 -lgdi32 -luser32 -lkernel32 -lws2_32 \
	-static -static-libgcc -lm
WIN_CC    := x86_64-w64-mingw32-gcc
WIN_RC    := x86_64-w64-mingw32-windres
WIN_ICON  := $(BUILD)/cooloo-icon.o

all: cooloo

# Portable CLI-only build for isolated Linux integration tests.
cooloo-cli: $(CORE_SRC) $(HEADERS)
	$(CC) $(CFLAGS) $(NATIVE_PLATFORM_FLAGS) -DCOOLOO_CLI_ONLY -Isrc -o $@ $(CORE_SRC)

cooloo: $(ALL_SRC) $(HEADERS) src/embedded_icon.h $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_WORKBENCH -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(ALL_SRC) $(MAC_LIBS)

$(SDL_MAC_LIB):
	mkdir -p $(SDL_MAC)
	cd $(SDL_MAC) && $(CMAKE) $(abspath src/vendor/sdl3) $(SDL_MAC_CMAKE_FLAGS)
	$(CMAKE) --build $(SDL_MAC) --parallel

$(SDL_WIN_LIB):
	mkdir -p $(SDL_WIN)
	cd $(SDL_WIN) && $(CMAKE) $(abspath src/vendor/sdl3) $(SDL_WIN_CMAKE_FLAGS) \
		-DCMAKE_TOOLCHAIN_FILE=$(abspath tools/mingw-toolchain.cmake)
	$(CMAKE) --build $(SDL_WIN) --parallel

src/embedded_font.c: src/vendor/fonts/JetBrainsMono-Regular.ttf tools/embed.py
	python3 tools/embed.py src/vendor/fonts/JetBrainsMono-Regular.ttf $@

$(BUILD)/embedded_workbench.c: $(WORKBENCH_LUA) lua/chat.lua tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@

$(BUILD)/embedded_editor.c: $(WORKBENCH_LUA) tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@ --profile text

$(BUILD)/embedded_workbench_cli.c: $(WORKBENCH_LUA) tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@ --profile cli

cooloo-workbench: $(WORKBENCH_CLI_SRC) $(HEADERS)
	$(CC) $(CFLAGS) $(NATIVE_PLATFORM_FLAGS) -DCOOLOO_RECORD_ONLY -DLUA_USE_POSIX -Isrc -Isrc/vendor/lua -o $@ $(WORKBENCH_CLI_SRC) -lm

cooloo-workbench.exe: $(WORKBENCH_CLI_SRC) $(HEADERS)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_RECORD_ONLY -Isrc -Isrc/vendor/lua -o $@ $(WORKBENCH_CLI_SRC) -static -lm

cooloo-text editor: $(EDITOR_SRC) $(HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(EDITOR_SRC) $(MAC_LIBS)

cooloo-text.exe editor.exe: $(EDITOR_SRC) $(HEADERS) $(SDL_WIN_LIB) $(WIN_ICON)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -mwindows -Isrc $(SDL_WIN_INC) -o $@ $(EDITOR_SRC) $(WIN_ICON) $(WIN_LIBS)

cli.exe: $(CORE_SRC) $(HEADERS)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_CLI_ONLY -Isrc -o $@ $(CORE_SRC) -lws2_32 -ladvapi32 -static

$(BUILD)/lua-runner: modules/runtime/runner.c $(LUA_SRC)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DCOOLOO_RUNNER_ONLY -DLUA_USE_POSIX -Isrc/vendor/lua -o $@ $^ -lm

# Linux development targets (not release artifacts).
SDL_LINUX := $(BUILD)/sdl3-linux
$(SDL_LINUX)/libSDL3.a:
	$(CMAKE) -S src/vendor/sdl3 -B $(SDL_LINUX) $(SDL_CMAKE_FLAGS) -DSDL_RENDER=OFF -DSDL_METAL=OFF
	$(CMAKE) --build $(SDL_LINUX) --parallel

cooloo-text-linux editor-linux: $(EDITOR_SRC) $(HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(EDITOR_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

cooloo-linux: $(ALL_SRC) $(HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_WORKBENCH -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(ALL_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

$(BUILD)/runtime-test-macos: tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DLUA_USE_POSIX $(SDL_MAC_INC) -o $@ tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(MAC_LIBS)

$(BUILD)/runtime-test.exe: tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(SDL_WIN_LIB)
	$(WIN_CC) $(CFLAGS) $(SDL_WIN_INC) -o $@ tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(WIN_LIBS)

test-workbench-macos: cooloo-cli $(BUILD)/lua-runner $(BUILD)/runtime-test-macos editor cooloo
	$(BUILD)/lua-runner --lua-run tests/workbench.lua
	$(BUILD)/lua-runner --lua-run tests/provider.lua
	$(BUILD)/runtime-test-macos $(BUILD)/lua-runner tests/runtime.lua
	COOLOO_TEST_EDITOR=$(CURDIR)/editor COOLOO_TEST_GUI=$(CURDIR)/cooloo python3 tests/workbench_integration.py

$(BUILD)/runtime-test: tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DLUA_USE_POSIX $(SDL_MAC_INC) -o $@ tests/runtime_test.c modules/runtime/process.c $(LUA_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

test-workbench: cooloo-cli $(BUILD)/lua-runner $(BUILD)/runtime-test editor-linux cooloo-linux
	$(BUILD)/lua-runner --lua-run tests/workbench.lua
	$(BUILD)/lua-runner --lua-run tests/provider.lua
	$(BUILD)/runtime-test $(BUILD)/lua-runner tests/runtime.lua
	python3 tests/workbench_integration.py

# Deliberately no GUI, SDL dummy, rendering or desktop tests in this target.
test-workbench-headless: cooloo-workbench $(BUILD)/lua-runner
	$(BUILD)/lua-runner --lua-run tests/workbench_headless.lua
	python3 tests/workbench_cli.py ./cooloo-workbench

# loopback integration against the sibling server repo's coolood
# (planner checkout layout: client and server are sibling submodules)
test: cooloo-cli
	CC="$(CC)" CFLAGS="$(CFLAGS)" python3 tests/config_test.py
	CC="$(CC)" CFLAGS="$(CFLAGS)" python3 tests/startup_test.py
	python3 tests/protocol2_test.py
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DLUA_USE_POSIX -I src/vendor/lua tests/lua_test.c $(LUA_SRC) -lm -o $(BUILD)/lua-test
	$(BUILD)/lua-test tests/chat_protocol2.lua
	$(CC) $(CFLAGS) -Isrc tests/cache_test.c src/record.c src/config.c -o $(BUILD)/cache-test
	@tmp=$$(mktemp -d); $(BUILD)/cache-test "$$tmp"; rc=$$?; rm -rf "$$tmp"; exit $$rc

src/embedded_icon.h assets/cooloo.ico assets/cooloo.png: tools/generate_icon.py
	python3 tools/generate_icon.py

$(WIN_ICON): src/cooloo.rc assets/cooloo.ico
	mkdir -p $(BUILD)
	$(WIN_RC) -Isrc -i src/cooloo.rc -o $@

release-windows: cooloo.exe cooloo-text.exe cooloo-workbench.exe cli.exe
cooloo.exe: $(ALL_SRC) $(HEADERS) src/embedded_icon.h $(SDL_WIN_LIB) $(WIN_ICON)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_WORKBENCH -D__USE_MINGW_ANSI_STDIO=1 -mwindows -Isrc $(SDL_WIN_INC) -o $@ $(ALL_SRC) $(WIN_ICON) $(WIN_LIBS)

release-macos: cooloo cooloo-text cooloo-workbench cooloo-cli
	@echo "release-macos: ./cooloo ./cooloo-text ./cooloo-workbench ./cooloo-cli (native $$(uname -m))"

install: cooloo
	install -m 0755 cooloo $(PREFIX)/bin/cooloo

clean:
	rm -f cooloo cooloo.exe cooloo-cli editor editor.exe cli.exe editor-linux cooloo-linux \
		cooloo-text cooloo-text.exe cooloo-text-linux cooloo-workbench cooloo-workbench.exe $(BUILD)/embedded_workbench_cli.c \
		$(BUILD)/embedded_workbench.c $(BUILD)/embedded_editor.c src/embedded_lua.c src/embedded_font.c

distclean: clean
	rm -rf $(BUILD)

.PHONY: all test test-workbench test-workbench-macos test-workbench-headless install clean distclean release-windows release-macos
