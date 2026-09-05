# cooloo client - v1 CLI (POSIX only; Windows arrives with v2 GUI)
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99
PREFIX  ?= /usr/local

NOISE_SRC := src/noise_xx.c src/vendor/monocypher.c
CLI_SRC   := src/main.c src/cli.c src/net.c src/config.c $(NOISE_SRC)

all: cooloo

cooloo: $(CLI_SRC) $(wildcard src/*.h)
	$(CC) $(CFLAGS) -Isrc -o $@ $(CLI_SRC)

# loopback integration against the sibling server repo's coolood
# (planner checkout layout: client and server are sibling submodules)
test: cooloo
	sh tests/nettest.sh

install: cooloo
	install -m 0755 cooloo $(PREFIX)/bin/cooloo

clean:
	rm -f cooloo

.PHONY: all test install clean
