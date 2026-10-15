# Protocol 2 client — v0.2.1

Requires a protocol-2 server. Production uses Protocol 2; the new simple private
room commands require server v0.2.1 or later. No old config/history migration
is provided.

## CLI

```
cooloo keygen                         # print actual public-key ID (64 hex)
cooloo whoami --register <nickname>    # duplicate nicknames allowed
cooloo whoami
cooloo create <nickname>               # create public room, returns its ID
cooloo join <room-id>                  # sends @<room-id> join-request
cooloo room-mode <room-id> public|private
cooloo avatar <001..899> <child-public-id> <nickname>
cooloo rooms
cooloo meta <id-or-alias>
cooloo rename <id-or-alias> <nickname>
cooloo send <id-or-alias> [text...]     # stdin preserves exact bytes
cooloo read [--raw] <id-or-alias> <offset>
cooloo follow <id-or-alias>            # durable catch-up then live stream
```

Simple private rooms require the matching updated server. Approve with:

```sh
cooloo send <room-id> '@<room-id> join-approve <applicant-user-id>'
```

Replace placeholders with complete IDs. Any member may approve; requests must
be more than 24 hours apart and expire after seven days. Owner counts toward the
200-member limit. Private rooms share their full history with members.
**Temporary policy: any registered user may switch any room to public, exposing
all history.** Switching public -> private adds user IDs that have sent messages
in this room, retaining owner and existing members; over 200 rejects conversion.
Registration, reading, or switching mode alone does not grant membership.
Member blocks are reserved, empty, and have no client API yet. No GUI controls
are added; ordinary GUI messages can carry the exact control text.

`-y/--tofu` trusts and pins a previously unknown server; a changed pin fails.
Create a child key in its own `COOLOO_CONFIG` directory, then authorize its public
ID through the parent `avatar` command. Do not register the child as a root
first: an existing identity cannot be claimed as somebody else's child.

Nicknames are presentation attributes. Use IDs for commands, not nicknames.
`read --raw` prints original JSON records. Non-raw CLI output currently displays
sender IDs. Interactive CLI `chat` is temporarily unavailable; use GUI or
separate send/follow terminals. FOLLOW resumes on the next invocation; automatic
retry and idle keepalive are not implemented in this revision.

## Local files

Default root: `~/.cooloo` (Windows HOME, otherwise USERPROFILE).
`COOLOO_CONFIG` overrides it. `COOLOO_HOST=host:port` overrides the server.

```
identity                         # private key
known_servers                    # TOFU fingerprints
config                           # GUI/window/server settings
cache/<server-fingerprint>/<own-public-id>/rooms/<destination-id>/
    .meta                        # server's canonical metadata snapshot
    messages.jsonl               # server's original JSONL bytes
```

Cache writes reject gaps or conflicting duplicates. Full history is synchronized
before following new messages. Only a complete durable prefix advances the
checkpoint. An incomplete final cached line is removed on reopen; malformed
complete lines fail closed. Cache files and server files are directly comparable.
Metadata is a snapshot, not a live change feed. Stop processes before backup;
the directory includes private keys. Windows ACLs inherit from the user profile.

GUI uses the existing C/SDL/Lua architecture. It loads cached history, resumes
READ from the cache end, then FOLLOWs. Display memory is capped at 2000 messages;
older history remains in JSONL, but scrolling older on-disk history is not yet
implemented. Room creation/avatar administration currently use the CLI. The GUI
registration form still restricts nicknames to `[a-z0-9_-]{1,16}` although native
CLI supports up to 64 UTF-8 bytes.

## Build and tests

```
make -C ../server all
make cooloo-cli                  # portable CLI-only build
make test                       # isolated CLI/gate/cache + Lua state tests
```

Platform release validation and remaining limitations are recorded in
`release/README.md`. Windows scripts use an isolated config and optional isolated
protocol-2 test server; never point their network tests at production.
