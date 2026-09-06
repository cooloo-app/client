# cooloo client - single binary: v1 CLI + v2 GUI (04 doc D27-D31)
# bare `cooloo` / `cooloo gui` -> GUI (SDL3+Lua); subcommands -> v1 CLI.
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
SDL_MAC_CMAKE_FLAGS := $(SDL_CMAKE_FLAGS) -DSDL_RENDER=ON -DSDL_METAL=ON
# Windows: the GDI window framebuffer is always available, keep render off.
SDL_WIN_CMAKE_FLAGS := $(SDL_CMAKE_FLAGS) -DSDL_RENDER=OFF -DSDL_METAL=OFF

NOISE_SRC := src/noise_xx.c src/vendor/monocypher.c
LUA_SRC   := $(filter-out src/vendor/lua/lua.c src/vendor/lua/luac.c,$(wildcard src/vendor/lua/*.c))
CORE_SRC  := src/main.c src/cli.c src/net.c src/config.c $(NOISE_SRC)
GUI_SRC   := src/gui.c src/font.c src/luabind.c
EMBED_SRC := src/embedded_lua.c src/embedded_font.c
ALL_SRC   := $(CORE_SRC) $(GUI_SRC) $(LUA_SRC) $(EMBED_SRC)
HEADERS   := $(wildcard src/*.h) $(wildcard src/vendor/lua/*.h) src/vendor/stb_truetype.h

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

all: cooloo

cooloo: $(ALL_SRC) $(HEADERS) $(SDL_MAC_LIB)
	$(CC) $(CFLAGS) -Isrc $(SDL_MAC_INC) -o $@ $(ALL_SRC) $(MAC_LIBS)

$(SDL_MAC_LIB):
	mkdir -p $(SDL_MAC)
	cd $(SDL_MAC) && $(CMAKE) $(abspath src/vendor/sdl3) $(SDL_MAC_CMAKE_FLAGS)
	$(CMAKE) --build $(SDL_MAC) --parallel

$(SDL_WIN_LIB):
	mkdir -p $(SDL_WIN)
	cd $(SDL_WIN) && $(CMAKE) $(abspath src/vendor/sdl3) $(SDL_WIN_CMAKE_FLAGS) \
		-DCMAKE_TOOLCHAIN_FILE=$(abspath tools/mingw-toolchain.cmake)
	$(CMAKE) --build $(SDL_WIN) --parallel

src/embedded_lua.c src/embedded_font.c: lua/main.lua lua/chat.lua lua/ui.lua lua/input.lua \
		src/vendor/fonts/JetBrainsMono-Regular.ttf tools/embed.py
	python3 tools/embed.py lua src/vendor/fonts/JetBrainsMono-Regular.ttf \
		src/embedded_lua.c src/embedded_font.c

# loopback integration against the sibling server repo's coolood
# (planner checkout layout: client and server are sibling submodules)
test: cooloo
	sh tests/nettest.sh

release-windows: cooloo.exe
cooloo.exe: $(ALL_SRC) $(HEADERS) $(SDL_WIN_LIB)
	$(WIN_CC) $(CFLAGS) -Isrc $(SDL_WIN_INC) -o $@ $(ALL_SRC) $(WIN_LIBS)

release-macos: cooloo
	@echo "release-macos: ./cooloo (native $$(uname -m))"

install: cooloo
	install -m 0755 cooloo $(PREFIX)/bin/cooloo

clean:
	rm -f cooloo cooloo.exe src/embedded_lua.c src/embedded_font.c

distclean: clean
	rm -rf $(BUILD)

.PHONY: all test install clean distclean release-windows release-macos
