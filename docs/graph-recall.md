# Graph recall (personal knowledge graph -> agent)

Job 3 of 3. The personal agent reads what extraction stored (`graph-extraction.md`): a passive summary in
the system prompt each turn, and an active tool. No sync, no iOS. Write path and what extraction writes are unchanged.

## Read API (`GraphStore`)

All run on the journal service's serial queue (`GraphJournalService.findNodes/neighbors/rankedNodes`), never on the main thread. None writes.

- `findNodes(query:limit:)`: normalized name or alias equals the normalized query (exact group first), then contains it.
  Normalization is `GraphIdentifiers.normalize` (the one that derives node ids). Each group sorted by lowercase name, then id.
- `neighbors(of:hops:)`: breadth-first, both edge directions, `hops` clamped to 1...2. Every node and edge is reported once, so cycles are fine.
- `rankedNodes()`: all nodes with degree and relations, degree desc, name, id.

Both `LadybugGraphStore` and the in-memory test store implement them via the pure functions in `GraphReadQueries.swift`
over the store's node/edge data (Ladybug reads through `snapshot()`; no new Cypher; fine for a small personal graph).

## Ranking

Degree (edge count) desc, then latest journal timestamp for the entity desc, then name, then id.
The timestamp is read from the existing journal with one grouped Core Data fetch (`max(timestamp)` group by `entityId`),
`GraphJournalService.latestJournalTimestamps()`. A node's recency is the newest of its own rows and its incident edges' rows
(extraction skips unchanged nodes, so "mentioned again" often only adds an edge). Nothing is added to node properties, no
per-mention write, **no model/schema version change and no new index** (the journal is scanned once per turn; add an
`entityId` index in a later model version if it ever gets large).

## Passive summary

Before each turn `chat(_:)` builds `turnSystemPrompt = systemPrompt + graphSummarySection()`.
The constant `systemPrompt` is first and unchanged; the section is appended after it.

```
Personal knowledge about the user (remembered from earlier chats; may be incomplete or outdated):
- Alice (Person, aka Ally): role: sister; knows Bob; lives_in Paris
```

Caps (constants in `GraphRecall`): at most 15 facts (`maxFacts`, one line per top node, up to 3 relations each),
160 characters per fact, 1200 characters for the whole section (trailing facts are dropped). Empty graph, no service,
read error or timeout: nothing is added.

## Tool `recall_personal_knowledge`

Input `query` (string) and optional `hops` (1 or 2, default 1; anything else is clamped). Matches names and aliases
(exact first, then substring), returns at most 5 matches with their relations as lines like `Alice lives_in Paris`
(15 relations per match), and the whole output is capped at 3000 characters. The description tells the model to use it
for questions about the user's own people, places, things and topics. Registered in the `tools` dictionary in `chat(_:)`.

## Failure behaviour

A read failure is logged (`print`, captured by `AppLogger`, like the rest of the graph code) and the turn continues without graph
context. The summary build waits at most 1.5 s (`summaryTimeoutSeconds`); on timeout the turn proceeds without it.
The tool answers "Personal knowledge is unavailable right now." on failure. No force unwraps, no `try!`.

## Settings

No new setting: recall is always on. `graphExtractionEnabled` ("Remember things from AI agent chats") gates **only extraction**;
turning it off stops new writes but already stored knowledge is still recalled.

## Prompt caching

The agent calls `generateText(model:tools:system:messages:)` (SwiftAISDK, Anthropic and OpenAI providers) with no
`providerOptions`, `cache_control`/`cacheControl`, or explicit prompt-cache keys anywhere in `AIAgentManager*` or the app (a grep for
`cache_control`, `cacheControl`, `ephemeral`, `prompt caching` only hits unrelated Strut `URLSession` code). So the app does not
request caching itself. If a provider caches prefixes automatically (OpenAI does for long identical prefixes), keeping the
constant system prompt first and the per-turn section last keeps that prefix identical; the suffix only changes the tail.
Tool definitions are sent with the request too and `query_hive_graph`'s description already varies per turn (nickname/orgs),
so there is no stable cache to protect today. No cache breakpoint was added because the code has no cache-control support.
Anthropic caching, if added later, should put its breakpoint at the end of `systemPrompt` and send the graph section as a separate block after it.

## Not verified

No Xcode/Swift on the authoring host: nothing was compiled, tests were not run, the hand-edited `project.pbxproj` entries
were not opened in Xcode, and the grouped Core Data fetch on a real SQLite store was not run.
