# cooloo client - single binary: CLI + v0.3 modular workbench
# bare `cooloo` -> short help (Windows desktop -> GUI); --gui -> GUI; commands -> CLI.
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99
PREFIX  ?= /usr/local
CMAKE   := $(shell command -v cmake 2>/dev/null || command -v cmake3 2>/dev/null || echo cmake)
BUILD   := build

GENERATED := $(BUILD)/generated

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

NOISE_SRC := src/client/noise_xx.c vendor/monocypher.c
LUA_SRC   := $(filter-out vendor/lua/lua.c vendor/lua/luac.c,$(wildcard vendor/lua/*.c))
CLIENT_SRC := src/client/net.c src/client/config.c src/client/record.c $(NOISE_SRC)
CLI_SRC := src/cli/main.c src/cli/win_console.c src/cli/cli.c src/cli/machine.c
CORE_SRC  := $(CLI_SRC) $(CLIENT_SRC)
RUNTIME_SRC := src/runtime/runner.c src/runtime/process.c
TEXT_GUI_SRC := src/platform/gui.c src/platform/font.c src/platform/renderer.c src/platform/rencache.c src/platform/luabind.c src/platform/api/api.c src/platform/api/file.c src/platform/api/renderer.c src/platform/api/renderer_font.c
GUI_SRC   := $(TEXT_GUI_SRC) $(RUNTIME_SRC)
EMBED_SRC := $(GENERATED)/embedded_workbench.c $(GENERATED)/embedded_fonts.c
EDITOR_SRC := src/apps/editor/main.c $(TEXT_GUI_SRC) $(LUA_SRC) $(GENERATED)/embedded_editor.c $(GENERATED)/embedded_fonts.c
WORKBENCH_CLI_SRC := src/apps/workbench/main.c src/client/record.c src/runtime/runner.c $(LUA_SRC) $(GENERATED)/embedded_workbench_cli.c
WORKBENCH_LUA := $(shell find lua -name '*.lua')
CFLAGS += -Isrc/client -Isrc/cli -Isrc/platform -Isrc/platform/api -Isrc/runtime -Isrc/adapters/cooloo -Ivendor -I$(GENERATED)
ALL_SRC   := $(CORE_SRC) $(GUI_SRC) src/adapters/cooloo/script.c src/adapters/cooloo/cache.c $(LUA_SRC) $(EMBED_SRC)
HEADERS   := $(shell find src -name '*.h') $(wildcard vendor/lua/*.h) vendor/stb_truetype.h vendor/monocypher.h
GUI_HEADERS := $(GENERATED)/embedded_icon.h $(GENERATED)/embedded_text_icon.h

# SDL3 public headers are self-contained; no generated-config include needed
SDL_MAC_INC := -Ivendor/sdl3/include -Ivendor/lua
SDL_WIN_INC := -Ivendor/sdl3/include -Ivendor/lua
MAC_LIBS  := $(SDL_MAC_LIB) -framework Cocoa -framework Carbon -framework IOKit \
	-framework CoreFoundation -framework CoreVideo \
	-framework UniformTypeIdentifiers -framework Metal -framework QuartzCore \
	-liconv -lobjc -lm
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

cooloo: $(ALL_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_WORKBENCH -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(ALL_SRC) $(MAC_LIBS)

$(SDL_MAC_LIB):
	mkdir -p $(SDL_MAC)
	cd $(SDL_MAC) && $(CMAKE) $(abspath vendor/sdl3) $(SDL_MAC_CMAKE_FLAGS)
	$(CMAKE) --build $(SDL_MAC) --parallel

$(SDL_WIN_LIB):
	mkdir -p $(SDL_WIN)
	cd $(SDL_WIN) && $(CMAKE) $(abspath vendor/sdl3) $(SDL_WIN_CMAKE_FLAGS) \
		-DCMAKE_TOOLCHAIN_FILE=$(abspath tools/mingw-toolchain.cmake)
	$(CMAKE) --build $(SDL_WIN) --parallel

$(GENERATED)/embedded_fonts.c: assets/fonts/font.ttf assets/fonts/icons.ttf assets/fonts/monospace.ttf tools/embed_fonts.py
	mkdir -p $(GENERATED)
	python3 tools/embed_fonts.py $@ assets/fonts/font.ttf assets/fonts/icons.ttf assets/fonts/monospace.ttf

$(GENERATED)/embedded_workbench.c: $(WORKBENCH_LUA) vendor/lite/user-init.lua tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@

$(GENERATED)/embedded_editor.c: $(WORKBENCH_LUA) vendor/lite/user-init.lua tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@ --profile text

$(GENERATED)/embedded_workbench_cli.c: $(WORKBENCH_LUA) tools/embed_workbench.py tools/embed.py
	python3 tools/embed_workbench.py $@ --profile cli

cooloo-workbench: $(WORKBENCH_CLI_SRC) $(HEADERS)
	$(CC) $(CFLAGS) $(NATIVE_PLATFORM_FLAGS) -DCOOLOO_RECORD_ONLY -DLUA_USE_POSIX -Isrc -Ivendor/lua -o $@ $(WORKBENCH_CLI_SRC) -lm

cooloo-workbench.exe: $(WORKBENCH_CLI_SRC) $(HEADERS)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_RECORD_ONLY -Isrc -Ivendor/lua -o $@ $(WORKBENCH_CLI_SRC) -static -lm

cooloo-text editor: $(EDITOR_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(EDITOR_SRC) $(MAC_LIBS)

cooloo-text.exe editor.exe: $(EDITOR_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_WIN_LIB) $(BUILD)/text-icon.o
	$(WIN_CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -mwindows -Isrc $(SDL_WIN_INC) -o $@ $(EDITOR_SRC) $(BUILD)/text-icon.o $(WIN_LIBS)

$(BUILD)/text-icon.o: assets/apps/editor/windows.rc assets/apps/editor/windows.manifest assets/cooloo-text.ico
	mkdir -p $(BUILD)
	$(WIN_RC) -Iassets/apps/editor -i assets/apps/editor/windows.rc -o $@

cli.exe: $(CORE_SRC) $(HEADERS)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_CLI_ONLY -Isrc -o $@ $(CORE_SRC) -lws2_32 -ladvapi32 -static

$(BUILD)/lua-runner: src/runtime/runner.c $(LUA_SRC)
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DCOOLOO_RUNNER_ONLY -DLUA_USE_POSIX -Ivendor/lua -o $@ $^ -lm

# Linux development targets (not release artifacts).
SDL_LINUX := $(BUILD)/sdl3-linux
SDL_LINUX_EXTRA_FLAGS ?=
$(SDL_LINUX)/libSDL3.a:
	$(CMAKE) -S vendor/sdl3 -B $(SDL_LINUX) $(SDL_CMAKE_FLAGS) -DSDL_RENDER=OFF -DSDL_METAL=OFF $(SDL_LINUX_EXTRA_FLAGS)
	$(CMAKE) --build $(SDL_LINUX) --parallel

cooloo-text-linux editor-linux: $(EDITOR_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(EDITOR_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

cooloo-linux: $(ALL_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_WORKBENCH -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(ALL_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

$(BUILD)/runtime-test-macos: tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DLUA_USE_POSIX $(SDL_MAC_INC) -o $@ tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(MAC_LIBS)

$(BUILD)/runtime-test.exe: tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(SDL_WIN_LIB)
	$(WIN_CC) $(CFLAGS) $(SDL_WIN_INC) -o $@ tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(WIN_LIBS)

test-workbench-macos: cooloo-cli $(BUILD)/lua-runner $(BUILD)/renderer-test-macos $(BUILD)/runtime-test-macos editor cooloo
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test-macos tests/workbench.lua
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test-macos tests/notifications.lua
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test-macos tests/workspace_state.lua
	$(BUILD)/lua-runner --lua-run tests/readstate.lua
	$(BUILD)/lua-runner --lua-run tests/provider.lua
	$(BUILD)/runtime-test-macos $(BUILD)/lua-runner tests/runtime.lua
	COOLOO_TEST_EDITOR=$(CURDIR)/editor COOLOO_TEST_GUI=$(CURDIR)/cooloo python3 tests/workbench_integration.py

$(BUILD)/runtime-test: tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DLUA_USE_POSIX $(SDL_MAC_INC) -o $@ tests/runtime_test.c src/runtime/process.c $(LUA_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

test-workbench: cooloo-cli $(BUILD)/lua-runner $(BUILD)/renderer-test $(BUILD)/runtime-test editor-linux cooloo-linux
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test tests/workbench.lua
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test tests/notifications.lua
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test tests/workspace_state.lua
	$(BUILD)/lua-runner --lua-run tests/readstate.lua
	$(BUILD)/lua-runner --lua-run tests/provider.lua
	$(BUILD)/runtime-test $(BUILD)/lua-runner tests/runtime.lua
	python3 tests/workbench_integration.py
	python3 tests/refresh_integration.py

RENDERER_TEST_SRC := tests/renderer_test.c $(filter-out src/apps/editor/main.c,$(EDITOR_SRC))
$(BUILD)/renderer-test: $(RENDERER_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(RENDERER_TEST_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

$(BUILD)/renderer-test-macos: $(RENDERER_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(RENDERER_TEST_SRC) $(MAC_LIBS)

$(BUILD)/renderer-test.exe: $(RENDERER_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_WIN_LIB)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -Isrc $(SDL_WIN_INC) -o $@ $(RENDERER_TEST_SRC) $(WIN_LIBS)

$(BUILD)/rencache-test: tests/rencache_test.c src/platform/rencache.c src/platform/rencache.h src/platform/renderer.h
	$(CC) $(CFLAGS) -Isrc $(SDL_MAC_INC) -o $@ tests/rencache_test.c src/platform/rencache.c

test-renderer: $(BUILD)/renderer-test $(BUILD)/rencache-test
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test tests/renderer.lua
	$(BUILD)/rencache-test

test-renderer-macos: $(BUILD)/renderer-test-macos $(BUILD)/rencache-test
	SDL_VIDEODRIVER=dummy $(BUILD)/renderer-test-macos tests/renderer.lua
	$(BUILD)/rencache-test

# Native SDL event-contract test; injection exists only in this test executable.
EVENT_TEST_SRC := tests/event_bridge_test.c $(filter-out src/apps/editor/main.c,$(EDITOR_SRC))
$(BUILD)/event-bridge-test: $(EVENT_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_LINUX)/libSDL3.a
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -Isrc $(SDL_MAC_INC) -o $@ $(EVENT_TEST_SRC) $(SDL_LINUX)/libSDL3.a -lm -ldl -lpthread

$(BUILD)/event-bridge-test-macos: $(EVENT_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -DLUA_USE_POSIX -mmacosx-version-min=$(MACOS_MIN) -Isrc $(SDL_MAC_INC) -o $@ $(EVENT_TEST_SRC) $(MAC_LIBS)

$(BUILD)/event-bridge-test.exe: $(EVENT_TEST_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_WIN_LIB)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_EDITOR_ONLY -Isrc $(SDL_WIN_INC) -o $@ $(EVENT_TEST_SRC) $(WIN_LIBS)

test-event-bridge: $(BUILD)/event-bridge-test
	SDL_VIDEODRIVER=dummy $(BUILD)/event-bridge-test tests/event_bridge.lua

test-event-bridge-macos: $(BUILD)/event-bridge-test-macos
	SDL_VIDEODRIVER=dummy $(BUILD)/event-bridge-test-macos tests/event_bridge.lua

# Native file fault tests are standalone and use only temporary fixture paths.
$(BUILD)/file-write-test: tests/file_write_test.c src/platform/api/file.c src/platform/api/file.h $(LUA_SRC)
	$(CC) $(CFLAGS) $(NATIVE_PLATFORM_FLAGS) -Ivendor/lua -o $@ tests/file_write_test.c $(LUA_SRC) -lm

$(BUILD)/file-write-test.exe: tests/file_write_test.c src/platform/api/file.c src/platform/api/file.h $(LUA_SRC)
	$(WIN_CC) $(CFLAGS) -Ivendor/lua -o $@ tests/file_write_test.c $(LUA_SRC) -static -lm

# Deliberately no GUI, SDL dummy, rendering or desktop tests in this target.
test-workbench-headless: cooloo-workbench $(BUILD)/lua-runner
	$(BUILD)/lua-runner --lua-run tests/ui_state.lua
	$(BUILD)/lua-runner --lua-run tests/threads.lua
	$(BUILD)/lua-runner --lua-run tests/workspace_models.lua
	$(BUILD)/lua-runner --lua-run tests/sidebar_width.lua
	$(BUILD)/lua-runner --lua-run tests/folder_sync.lua
	$(BUILD)/lua-runner --lua-run tests/workbench_headless.lua
	$(BUILD)/lua-runner --lua-run tests/readstate.lua
	python3 tests/workbench_cli.py ./cooloo-workbench

# loopback integration against the sibling server repo's coolood
# (planner checkout layout: client and server are sibling submodules)
test: cooloo-cli
	CC="$(CC)" CFLAGS="$(CFLAGS)" python3 tests/config_test.py
	CC="$(CC)" CFLAGS="$(CFLAGS)" python3 tests/startup_test.py
	python3 tests/protocol2_test.py
	python3 tests/trust_test.py
	mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -DLUA_USE_POSIX -I vendor/lua tests/lua_test.c $(LUA_SRC) -lm -o $(BUILD)/lua-test
	$(BUILD)/lua-test tests/chat_protocol2.lua
	$(CC) $(CFLAGS) -Isrc tests/cache_test.c src/client/record.c src/client/config.c -o $(BUILD)/cache-test
	@tmp=$$(mktemp -d); $(BUILD)/cache-test "$$tmp"; rc=$$?; rm -rf "$$tmp"; exit $$rc

$(GENERATED)/embedded_icon.h assets/cooloo.ico assets/cooloo.png: tools/generate_icon.py
	python3 tools/generate_icon.py --output-dir $(GENERATED) --mark C

$(GENERATED)/embedded_text_icon.h assets/cooloo-text.ico assets/cooloo-text.png: tools/generate_icon.py
	python3 tools/generate_icon.py --output-dir $(GENERATED) --mark T

$(WIN_ICON): assets/apps/cooloo/windows.rc assets/cooloo.ico
	mkdir -p $(BUILD)
	$(WIN_RC) -Iassets/apps/cooloo -i assets/apps/cooloo/windows.rc -o $@

# Offline Windows startup fixtures; GUI dispatch returns 73 without opening SDL.
$(BUILD)/startup-dispatch.exe: tests/startup_gui_stub.c $(CORE_SRC) $(HEADERS)
	mkdir -p $(BUILD)
	$(WIN_CC) $(CFLAGS) -mwindows -o $@ tests/startup_gui_stub.c $(CORE_SRC) -static -lws2_32 -ladvapi32

$(BUILD)/console-input-probe.exe: tests/console_input_probe.c src/cli/win_console.c src/cli/win_console.h
	mkdir -p $(BUILD)
	$(WIN_CC) $(CFLAGS) -mwindows -o $@ tests/console_input_probe.c src/cli/win_console.c -static

$(BUILD)/startup-console-parent.exe: tests/startup_console_parent.c
	mkdir -p $(BUILD)
	$(WIN_CC) -O2 -Wall -Wextra -o $@ $< -static

release-windows: cooloo.exe cooloo-text.exe cooloo-workbench.exe cli.exe
cooloo.exe: $(ALL_SRC) $(HEADERS) $(GUI_HEADERS) $(SDL_WIN_LIB) $(WIN_ICON)
	$(WIN_CC) $(CFLAGS) -DCOOLOO_WORKBENCH -D__USE_MINGW_ANSI_STDIO=1 -mwindows -Isrc $(SDL_WIN_INC) -o $@ $(ALL_SRC) $(WIN_ICON) $(WIN_LIBS)

release-macos: cooloo cooloo-text cooloo-workbench cooloo-cli
	@echo "release-macos: ./cooloo ./cooloo-text ./cooloo-workbench ./cooloo-cli (native $$(uname -m))"

install: cooloo
	install -m 0755 cooloo $(PREFIX)/bin/cooloo

clean:
	rm -f cooloo cooloo.exe cooloo-cli editor editor.exe cli.exe editor-linux cooloo-linux \
		cooloo-text cooloo-text.exe cooloo-text-linux cooloo-workbench cooloo-workbench.exe
	rm -rf $(GENERATED)

distclean: clean
	rm -rf $(BUILD)

.PHONY: test-renderer test-renderer-macos all test test-workbench test-workbench-macos test-workbench-headless test-event-bridge test-event-bridge-macos install clean distclean release-windows release-macos
