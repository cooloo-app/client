# Client message threads

Threads are a GUI client convention, supported in rooms and the merged private
inbox. The server stores/transports unchanged plain text: no thread API, server
counter, notification or permission changes. Existing Protocol 3 UUIDs are used;
offsets remain download/read cursors, never permanent references.

## Reply and display

Place the history cursor inside one message, then use **Alt+R** or **Chat: Reply
In Thread** in the command palette. A selection spanning messages or separators
is rejected. The palette snapshots the UUID before taking focus. Replying to a
reply targets its root. Existing draft text stays; switching a draft to another
thread asks for confirmation. Header insertion is undoable and saved in
`draft.txt`. Pending sends cannot change target.

Roots retain their original position; replies move below the root, ordered by
server timestamp, then UUID for ties. Threads are flat and fully expanded, with
a left guide and no extra blank line between replies. Guides and indentation
are renderer decorations, not copied text. **Chat: Copy Message Source** copies
the selected message's original text, including its header. Ordinary selection
copies displayed text. There is no reply counter, context menu, hover button or
new-reply/jump notification. Existing conversation-level read behavior remains.

Private inbox records are partitioned by peer: a root cannot collect a reply
from a different private participant. Reply SEND targets the root's peer, not
the user's own inbox; the original authorization checks still apply. Private
history discovery still uses the existing incoming-cache / filtered SENT flow;
threads do not bypass permissions or fetch arbitrary other inboxes.

## Text convention

```text
@thread/1 msg:550e8400e29b41d4a716446655440000

Reply body
```

Only an exact initial version-1 header, a canonical 32-character lowercase
UUIDv4 and an empty separator line are recognized. LF and CRLF pairs are
accepted. Unknown versions, malformed IDs, missing separators, code blocks and
headers preceded by a backslash remain literal, including the backslash when
displayed/copied. Only one initial header is interpreted; another header inside
the body is literal text. Received empty replies remain visible; sending an
empty body is rejected. References to replies, cycles, self-references and
cross-peer references are not followed recursively. Missing roots show an
explicit unavailable marker and readable body; roots loaded later regroup.

## History and sending

The adapter pages the authenticated conversation cache on the existing worker,
200 records per completion, and builds an in-memory UUID index. Live messages
and recovered SENT records extend it. All locally indexed replies count, even
outside the ordinary latest-2000 display window. A visible reply whose root is
outside that window materializes its cached root and sibling replies. The
source log, cursor and read watermark are not reordered. Selection and reading
scroll anchors map through message UUIDs. The index is reset on identity,
reconnect and stream-generation changes. It is not a durable on-disk index;
memory scales with locally cached history. Disk paging is asynchronous, but
rendering one exceptionally large externally-created thread still costs time.

Ctrl+Enter uses the common GUI send boundary. It trims ASCII whitespace
(space/tab/CR/LF and other Lua `%s` whitespace) from the **start and end** of the
body. Internal blank lines, code indentation and paragraph spacing are kept;
the mandatory header separator is reconstructed. The 4096-byte limit includes
the header and separator. Whitespace-only messages are rejected. No CLI, SDK or
server payload normalization is introduced.

At 8 known replies the ninth is allowed; at 9 the next is blocked with
`此讨论已有 9 条跟帖，建议整理后作为新消息发送`. Cache indexing must finish before
sending a reply. UUID-based pending/ACK reservations prevent a send acknowledged
before live echo from freeing a slot. Explicit same-message unknown retries
remain idempotent through the existing provider. Concurrent/older clients can
exceed nine; every received reply is still displayed. The rule is local, not a
global quota or lock.

Blocked/rejected/unknown sends do not rewrite or clear the draft or selection.
The submitted payload is trimmed without mutating the saved draft; ACK compares
the **original draft version**, so it clears only unchanged text and never a
new edit. No automatic retries or automatic thread summaries are added.

## Verification scope

`make test-workbench-headless`, `build/lua-runner --lua-run tests/provider.lua`
and `SDL_VIDEODRIVER=dummy build/renderer-test tests/workbench.lua` cover parsing,
projection, peer isolation, worker pagination, routing, local limits, trim/ACK,
wrapped hit testing, undo, UUID scroll anchoring and command-palette discovery.
These are local automated tests, not real two-client network or Windows/macOS
desktop acceptance. Native clipboard, fonts, IME and Alt+R on both desktop
platforms still require human validation. Release binaries are not refreshed by
this source change.
