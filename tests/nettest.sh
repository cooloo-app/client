#!/bin/sh
# nettest.sh - client repo loopback integration (handoff §7, T4).
# Drives the real CLI against the sibling server repo's coolood on
# 127.0.0.1 with isolated COOLOO_HOME / COOLOO_CONFIG dirs.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SERVER_DIR=${SERVER_DIR:-$ROOT/../server}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/cooloo-client-test.XXXXXX")
PORT=$((21000 + RANDOM % 20000))

if [ ! -x "$SERVER_DIR/coolood" ]; then
    make -C "$SERVER_DIR" coolood >/dev/null 2>&1 || {
        echo "cannot build $SERVER_DIR/coolood"; exit 1; }
fi

export COOLOO_HOME=$TMP/home
export COOLOO_CONFIG=$TMP/cfg1
export COOLOO_HOST=127.0.0.1:$PORT
mkdir -p "$COOLOO_HOME/rooms"

"$SERVER_DIR/coolood" -b 127.0.0.1 -p "$PORT" >"$TMP/daemon.log" 2>&1 &
DPID=$!
trap 'kill $DPID 2>/dev/null; wait $DPID 2>/dev/null; rm -rf "$TMP"' EXIT

CLI="$ROOT/cooloo"
pass=0
fail=0
check() { # check <name> <file> <pattern>
    if grep -q "$3" "$2" 2>/dev/null; then
        echo "ok   - $1"
        pass=$((pass + 1))
    else
        echo "FAIL - $1 (want: $3)"
        sed 's/^/       got: /' "$2" 2>/dev/null | head -5
        fail=$((fail + 1))
    fi
}
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
bad() { echo "FAIL - $1"; fail=$((fail + 1)); }

sleep 0.5

echo "== keygen / identity"
"$CLI" keygen >"$TMP/k1" 2>&1
check "keygen prints fingerprint" "$TMP/k1" '^fingerprint: [0-9a-f]\{64\}$'
MODE=$(stat -f%Lp "$TMP/cfg1/identity" 2>/dev/null || stat -c%a "$TMP/cfg1/identity" 2>/dev/null)
[ "$MODE" = "600" ] && ok "identity mode 0600" || bad "identity mode 0600 (got $MODE)"
if "$CLI" keygen >"$TMP/k2" 2>&1; then
    bad "second keygen refused"
else
    check "second keygen refused" "$TMP/k2" 'already exists'
fi

echo "== TOFU"
if "$CLI" -y rooms >"$TMP/t1" 2>&1; then
    ok "-y auto-trust connects"
else
    bad "-y auto-trust connects"
    sed 's/^/       got: /' "$TMP/t1" | head -3
fi
grep -q "127.0.0.1:$PORT [0-9a-f]\{64\}" "$TMP/cfg1/known_servers" \
    && ok "known_servers pinned" || bad "known_servers pinned"
cp "$TMP/cfg1/known_servers" "$TMP/ks.bak"
sed -i '' 's/[0-9a-f]$/0/' "$TMP/cfg1/known_servers" 2>/dev/null || \
    sed -i 's/[0-9a-f]$/0/' "$TMP/cfg1/known_servers"
if "$CLI" rooms >"$TMP/t2" 2>&1; then
    bad "fingerprint mismatch refused"
else
    check "fingerprint mismatch refused" "$TMP/t2" 'FINGERPRINT CHANGED'
fi
cp "$TMP/ks.bak" "$TMP/cfg1/known_servers"
rm -f "$TMP/cfg1/known_servers"
printf 'y\n' | "$CLI" rooms >"$TMP/t3" 2>&1
check "interactive TOFU prompt" "$TMP/t3" 'trust and pin it'
grep -q "127.0.0.1:$PORT" "$TMP/cfg1/known_servers" \
    && ok "prompt pinned server" || bad "prompt pinned server"

echo "== register"
"$CLI" whoami >"$TMP/r1" 2>&1
check "whoami unregistered" "$TMP/r1" 'not registered'
"$CLI" whoami --register alice >"$TMP/r2" 2>&1
check "register alice" "$TMP/r2" '^NICK alice$'
"$CLI" whoami >"$TMP/r3" 2>&1
check "whoami -> alice" "$TMP/r3" '^alice$'

echo "== second identity bob"
COOLOO_CONFIG=$TMP/cfg2 "$CLI" keygen >/dev/null 2>&1
COOLOO_CONFIG=$TMP/cfg2 "$CLI" -y whoami --register bob >"$TMP/r4" 2>&1
check "register bob" "$TMP/r4" '^NICK bob$'

echo "== send / read"
"$CLI" send general "hello world" >"$TMP/s1" 2>&1
check "send -> OK offset" "$TMP/s1" '^OK [0-9]'
"$CLI" read general 0 >"$TMP/s2" 2>&1
check "read human format" "$TMP/s2" '^[0-9][0-9]:[0-9][0-9] <alice> hello world$'
"$CLI" read --raw general 0 >"$TMP/s3" 2>&1
check "read --raw offset format" "$TMP/s3" '^[0-9]* [0-9]* alice hello world$'
printf 'line1\nline2\n' | "$CLI" send general >"$TMP/s4" 2>&1
check "multiline stdin send" "$TMP/s4" '^OK [0-9]'
"$CLI" read general -1 >"$TMP/s5" 2>&1
check "multiline line1" "$TMP/s5" 'line1$'
check "multiline line2 indented" "$TMP/s5" '^      line2$'
"$CLI" read general -2 >"$TMP/s6" 2>&1
check "read -2 has both messages" "$TMP/s6" 'hello world'

echo "== follow + offset persistence + reconnect resume"
"$CLI" follow general >"$TMP/f1" 2>&1 &
FPID=$!
sleep 1.5
COOLOO_CONFIG=$TMP/cfg2 "$CLI" send general "from bob" >/dev/null 2>&1
sleep 2
kill $FPID 2>/dev/null; wait $FPID 2>/dev/null
check "follow caught bob" "$TMP/f1" 'from bob'
grep -q '^offset.general [0-9]' "$TMP/cfg1/config" \
    && ok "offset persisted" || bad "offset persisted"
"$CLI" follow general >"$TMP/f2" 2>&1 &
FPID=$!
sleep 1.5
kill $FPID 2>/dev/null; wait $FPID 2>/dev/null
if grep -q 'from bob' "$TMP/f2"; then
    bad "resume does not replay old messages"
else
    ok "resume does not replay old messages"
fi

echo "== chat"
( sleep 1; printf 'chat says hi\n'; sleep 2 ) | "$CLI" chat general >"$TMP/c1" 2>&1 &
CPID=$!
sleep 2
COOLOO_CONFIG=$TMP/cfg2 "$CLI" send general "bob in chat" >/dev/null 2>&1
wait $CPID
check "chat shows bob message" "$TMP/c1" 'bob in chat'
check "chat prompt present" "$TMP/c1" '^> '

echo
echo "client nettest: passed $pass, failed $fail"
[ "$fail" -eq 0 ]
