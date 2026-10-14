# Graph extraction (agent -> personal knowledge graph)

Job 2 of 3. The personal agent writes knowledge into the graph through
`GraphJournalService.apply()` after its turns. No recall / prompt injection (job 3), no sync, no iOS.

## Flow

1. `AIAgentManager.chat()` finishes and returns the answer (the error path returns earlier and never extracts).
2. `scheduleGraphExtraction` (`AIAgentManager+GraphExtraction.swift`) checks, in order:
   `GraphExtractionPolicy.shouldExtract`, then the privacy switch (BEFORE any model call).
3. A fire-and-forget `Task.detached(priority: .utility)` makes a SECOND model call with NO tools, using the
   model `chat()` already resolved from the user's provider/key settings. The user never waits for it.
4. `GraphExtractionParser.parse` strips markdown fences and validates the whole payload.
5. `GraphExtractionOperations.operations` builds one batch with `GraphOperation.upsertNode/upsertEdge`
   (nodes first, then edges); ONE `apply([ops])` call writes it. Unchanged nodes/edges are skipped.

## Skip rules (`GraphExtractionPolicy.shouldExtract`)

Extract only if all hold:

- the turn did not fail;
- the user text is not empty;
- it is not a greeting / small talk: every word of the user text is a small-talk word
  (`hi`, `thanks`, `how are you`, `ok`, ...; see `smallTalkWords`);
- if the turn used tools, the user text must contain an explicit personal-fact cue
  (`my name is`, `i live`, `my wife`, ...; see `personalCues`). Tool-only requests such as
  "read the last messages from Bob" carry no personal content and are skipped.

Turns without tools that pass these are sent; the model may still answer `{"nodes":[],"edges":[]}`.
The rules are a deliberately cheap heuristic (no model call to decide).

## Privacy switch

Profile -> Advanced, row "Remember things from AI agent chats", UserDefaults key `graphExtractionEnabled`,
default ON. A missing Bool reads `false`, so `GraphExtractionSettings.registerDefaults()` runs at launch and
`isEnabled` also treats a missing key as true. Checked before the extraction model call.

## Schema v1

Node types: `Person`, `Place`, `Thing`, `Topic`.
Relation types: `knows`, `lives_in`, `works_at`, `works_on`, `interested_in`, `owns`, `related_to`, `located_in`.

Node payload: `{"type": "<Type>", "properties": {"name": "<display name>", "aliases": ["<old name>"], ...free string properties}}`.
Edge payload: `{"src","dst","type": "<relation>","properties": {...}}`. Property keys `name` and `aliases` are
reserved for nodes (a model-supplied one invalidates the payload). When an entity is seen with a different display
name (same normalized name), the old name is kept in `aliases`; existing properties are kept, new values win.
Merging nodes is out of scope. Entity resolution v1 = exact match on normalized name + type = same id.

## Model output format and validation

```json
{"nodes":[{"type":"Person","name":"Alice","properties":{"role":"sister"}}],
 "edges":[{"source":{"type":"Person","name":"Alice"},"relation":"lives_in","target":{"type":"Place","name":"Paris"},"properties":{}}]}
```

The WHOLE payload is dropped (and logged with `print`, which `AppLogger` captures) if: it is not a JSON object,
`nodes` is missing, any node/edge is malformed, a type or relation is unknown, a name is empty after
normalization or longer than 200 characters, a property value is not a string/number/bool, an edge endpoint is not
among the extracted nodes, or there are more than 50 nodes / 100 edges. Empty output or `{"nodes":[]}` is a silent
no-op. Nothing partial is ever written, nothing force-unwraps.

## Deterministic ids

```
namespace = 4dcb6314-9c48-5148-b515-af314187e2fa     (= UUIDv5(NAMESPACE_DNS, "graph.sphinx.chat"); never change)
normalize(name) = Unicode NFKC -> lowercase -> split on whitespace/newlines, drop empties, join with one space
node id = UUIDv5(namespace, "<nodeType>:<normalize(name)>")
edge id = UUIDv5(namespace, "<sourceId>:<relationType>:<destinationId>")
```

- `<nodeType>` is exactly `Person` | `Place` | `Thing` | `Topic`; `<relationType>` exactly the snake_case
  value above. Ids are lowercase, hyphenated UUID strings in the edge name. Names are UTF-8.
- UUIDv5 per RFC 4122 section 4.3: SHA-1 over the 16 namespace bytes followed by the UTF-8 name,
  take the first 16 bytes, set byte 6 high nibble to 5 and byte 8 top two bits to `10`.
  (Swift: `Insecure.SHA1`; Python `uuid.uuid5` gives the same result.)
- Lowercasing is the platform's default full lowercase mapping (Swift `lowercased()`, Python `lower()`);
  both agree on the vectors below.

### Test vectors (also asserted in `GraphExtractionTests`)

| type | input name | normalized | id |
|---|---|---|---|
| Person | `Alice` | `alice` | `82522da3-8cb7-5883-91a7-5124738e74e8` |
| Person | `  ALICE   ` | `alice` | `82522da3-8cb7-5883-91a7-5124738e74e8` |
| Person | `Alice  Smith` | `alice smith` | `fde501d2-3812-5d61-b796-8655f9149734` |
| Place | `Paris` | `paris` | `2d0c2181-9fdc-5e0f-8f4a-b297ad6c25ad` |
| Place | `Ｐａｒｉｓ` (fullwidth) | `paris` | `2d0c2181-9fdc-5e0f-8f4a-b297ad6c25ad` |
| Thing | `ﬁle cabinet` (U+FB01 ligature) | `file cabinet` | `ca9860c5-aca5-5c79-ac9f-7d51cc5ecaa0` |
| Thing | `file cabinet` | `file cabinet` | `ca9860c5-aca5-5c79-ac9f-7d51cc5ecaa0` |
| Person | `José Müller` (precomposed) | `josé müller` | `6a102b2d-7c6c-5059-acce-664621026118` |
| Person | `张伟` | `张伟` | `b79b7fb2-7e3a-5cc5-85c4-bd5ed3c1b828` |
| Topic | `Machine<TAB>Learning` | `machine learning` | `977b6346-1a8c-5872-9da1-45e97be0e49e` |

Edge ids:

| source | relation | destination | id |
|---|---|---|---|
| Person `Alice` (`82522da3-…`) | `lives_in` | Place `Paris` (`2d0c2181-…`) | `1b123321-1220-53ec-8662-0714da9b4253` |
| Person `Alice Smith` (`fde501d2-…`) | `knows` | Person `Alice` (`82522da3-…`) | `2a5ca767-5e7f-5eba-82f1-21c5cc9ec744` |

The first edge's name string is
`82522da3-8cb7-5883-91a7-5124738e74e8:lives_in:2d0c2181-9fdc-5e0f-8f4a-b297ad6c25ad`.

## Launch wiring and account wipe

- `PersonalGraph.service` is the single shared `GraphJournalService` (Ladybug file lock).
  `AppDelegate.applicationDidFinishLaunching` registers the switch default and calls
  `PersonalGraph.startInBackground()` (`start()` in a detached utility task, never on the main thread).
- `UserData.clearData()` also calls `PersonalGraph.destroyStoreInBackground()` -> `GraphJournalService.destroyStore()`
  -> `GraphStore.destroy()`, which closes Ladybug (releasing the file) and deletes `graph.lbug` and its sidecars
  without reopening. `reset()` is not used because it reopens and recreates an empty file.
  The next `apply` after a wipe finds the store closed and rebuilds it from the (by then empty) journal.

## Not verified (no Xcode in the authoring environment)

Build, tests, UI placement of the Profile row, the real model output quality, and the Swift 6 concurrency
warnings were not run. Vectors were computed with Python and cross-checked against the Swift implementation by reading only.
