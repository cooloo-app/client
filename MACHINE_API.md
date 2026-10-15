# CLI machine API — schema 1 (client v0.2.3)

Opt in with `cooloo --json <command>`. Existing human output and `read --raw` remain
available. This is an output adapter around the existing C Native client, not a new
server protocol or long-running RPC service. Use server v0.2.2 for delegation/SENT.

## Invocation

Global flags must precede the command: `--json`, `--tofu`/`-y`, `--as <owner-id>`.
GUI-only flags are not message flags. `--gui` explicitly selects the default GUI;
combining it with a command or --json is an error. `version` is local/offline.
Use argv arrays, never shell command strings; SEND stdin preserves UTF-8 bytes including
newlines (1–4096 bytes, no NUL). Machine stdin/stdout use binary mode on Windows.
COOLOO_CONFIG and COOLOO_HOST retain their ordinary meaning; no automatic registration.

Machine mode never prompts for TOFU. Unknown server -> server-untrusted, changed pin ->
server-key-changed. Explicit --tofu permits first-use trust only. AS failure terminates
without fallback. WHOAMI/register are login operations: --as with these is rejected.

## Output

UTF-8 JSONL on stdout, one event per line, every event has schema=1 and type. Strings
are JSON escaped; additive fields are allowed, consumers must ignore unknown fields.
Diagnostics only on stderr. Stream message events flush immediately. Exit 0 succeeds,
1 is runtime failure, 2 is usage failure. Errors normally have code/message; crashes,
external termination and broken output pipes may have no error event.

| Command | Events / fields |
|---|---|
| version | result: binary_version, schema_versions, capabilities |
| keygen | result: id |
| whoami [--register nickname] | result: id, nickname ("-" unregistered) |
| create nickname / avatar slot child-id nickname | result: id, nickname |
| meta id | result: id, kind, owner ("-" if none), slot (integer), nickname |
| rename / room-mode / delegate | result |
| send / join | result: end_offset |
| rooms | room(id,nickname)* then end |
| read id offset | message* then end(next_offset) |
| follow id offset | message* until failure/cancellation, no normal end |
| sent peer offset | message* then end(scan_offset), including empty matches |

Message: `{"schema":1,"type":"message","end_offset":123,"message":{"ts":1,"from":"...","to":"...","content":"..."}}`.
Error: `{"schema":1,"type":"error","code":"forbidden","message":"..."}`.
Machine history/chat/help are not supported. Use ordinary help for human documentation.

## Cursors and failures

READ/FOLLOW machine mode never writes metadata/message caches. FOLLOW requires an explicit
nonnegative byte cursor; ordinary human FOLLOW still resumes its local cache. Every
message retains the server's actual offset, never a JSON re-encoding approximation.
Business callers save offsets only after successful processing; no exactly-once promise.
Filtered SENT scan_offset is independent from the last matching message, and sparse data
must not enter the normal contiguous cache. Finite operations require a terminal event
AND exit 0; partial output or EOF alone is not success.

Server errors preserve their code. Local codes include invalid-argument, identity-missing,
identity-create-failed, server-untrusted, server-key-changed, network-error, protocol-error,
identity-selection-failed. SEND without an acknowledgement after transmission begins is
send-outcome-unknown: the server might have persisted it. Never blindly retry. SDK timeout
while sending is likewise conservatively unknown. No automatic retry/keepalive/reconnect.
Python deadlines control subprocess lifetime; the blocking native CLI itself has no new
network deadline flag. FOLLOW may close on the server idle timeout.

See python-sdk repository for subprocess API and wheel distribution. Client version alone
does not establish remote server feature support. No wire format/server changes required.
