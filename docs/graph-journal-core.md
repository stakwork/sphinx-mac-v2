# Graph journal core (local storage only)

Job 1 of 3 for the personal knowledge graph. No agent hooks, recall, sync or iOS.

## Design

- **Journal = source of truth**: Core Data entity `GraphJournalEntry`
  (`clientId`, `seq` Int64, `timestamp`, `opType` Int16 <-> `GraphOpType`, `entityId` UUID,
  `payload` JSON `Data` with the full resulting properties, `schemaVersion` Int16).
  Append-only: rows are never updated, deleted or truncated by graph code. Deletes are
  tombstone rows (`nodeDelete` / `edgeDelete`). Edge payloads carry `src`, `dst` (node UUIDs) and `type`.
- **Ladybug = rebuildable cache** (`graph.lbug`), tables `GNode(id STRING PK, kind, payload)` and
  `GEdge(FROM GNode TO GNode, id STRING, type, payload)`. Ids are app-created UUIDs.
- **`GraphStore` protocol** (`Managers/Graph/GraphStore.swift`): open/close/reset/perform(mutations)/snapshot.
  `LadybugGraphStore` is one adapter; `GraphJournalService` depends only on the protocol
  (tests use `InMemoryGraphStore`).
- **`GraphJournalService.apply(_:)`** is the only write path (single op or batch). It derives
  `GraphMutation`s, appends all journal rows in one Core Data save, then applies the same
  mutations in one store transaction. `(clientId, seq)` is idempotent: a duplicate returns
  `.duplicate` and writes nothing. `clientId == nil` -> local client id; `seq == nil` -> next seq for
  that client (explicit values are for sync replay later). An invalid payload rejects the whole batch
  before anything is written.
- All store and journal work runs on one serial `DispatchQueue`; the Ladybug adapter asserts
  `!Thread.isMainThread`.
- **Rebuild**: if the store opens as newly created while the journal has rows, or fails to open, or a store
  write fails after the journal save, the store is reset (the `.lbug` file and every `.lbug.*` sidecar
  are deleted) and the journal is replayed in order timestamp, clientId, seq (global timeline across
  clients; ties deterministic), in pages of 500 with one store transaction per page. Replay only reads
  the journal and writes the store, so it is not a second journal write path. Tombstones replay to
  deletion (`DETACH DELETE` removes a node's edges).
- **File location**: `Application Support/<bundle id>/Graph/graph.lbug`. The app is sandboxed
  (`com.apple.security.app-sandbox` in the app entitlements), so this is inside the app's own container.
  No App Group or shared location.

## Core Data

New model version `com_stakwork_sphinx_desktop 14.xcdatamodel` (copy of 13 + the entity, codegen
`none`), `.xccurrentversion` and the project's version group updated. Class files follow the
`DataSync` layout (`CoreData/GraphJournalEntry/…+CoreDataClass.swift` and `…+CoreDataProperties.swift`).
`CoreDataManager.persistentContainer` already sets `NSMigratePersistentStoresAutomaticallyOption` and
`NSInferMappingModelAutomaticallyOption` (`CoreDataManager.swift:24-25`), so adding an entity is a
lightweight migration like earlier versions. `DataSync` is not reused. No uniqueness constraint was
added on (clientId, seq): idempotency is enforced by the service on its serial queue, and a Core Data
constraint would rely on the merge policy to resolve violations; a fetch index on (clientId, seq) was added.

## clientId findings (`UserData.accountUUID`)

- Defined at `Configuration/UserData.swift:27-35`: read from `UserDefaults.Keys.accountUUID`
  (`Extensions/UserDefaults.swift:13`); if absent, a new `UUID().uuidString` is generated and stored on the
  spot. It is therefore **never nil/empty** at first launch. It lives in UserDefaults, not Keychain or Core Data.
- Reinstall: UserDefaults are in the app container, so a clean reinstall normally yields a new id (and the
  Core Data journal is gone with it too, so id and journal stay consistent). Not verified on a real reinstall.
- Reset/logout: `UserData.clearData()` (`UserData.swift:288-294`) calls `clearCoreDataStore()` (deletes ALL
  entities' objects via `deleteAllObjects`, `NSManagedObjectContext.swift:18`, **including the journal**) and then
  `UserDefaults.resetUserDefaults()` (`UserDefaults.swift:98-123`, removes the whole persistent domain, so a
  new accountUUID is generated). So on account reset the journal and the id are wiped together and a
  fresh client starts at seq 1. That means the "journal is never truncated" rule holds for graph code, but the
  existing account wipe does delete it; it does not clear `graph.lbug`. **Follow-up**: the wipe should also
  call the store's `reset()` so the cache does not outlive the journal (not done: out of scope / no wiring yet).
- Risk if the two ever diverge (UserDefaults kept but Core Data wiped): the same clientId would restart at
  seq 1 and peers would treat those ops as duplicates. The current reset path wipes both, so it is
  suitable; no fallback id was added. `AccountUUIDClientIdProvider` throws `emptyClientId` defensively.

## Not wired

Nothing instantiates `GraphJournalService` in the app yet; the caller must run `start()` once off the main
thread and keep a single instance (Ladybug takes a file lock).

## Known limitation

If the process dies between the journal save and the store transaction, the cache is behind the journal
until the next rebuild; nothing detects that yet (no applied-seq watermark in Ladybug). Replay is idempotent,
so a catch-up pass can be added later.

## Could not verify (Linux, no Xcode)

- `xcodebuild` compile of any new Swift (re-read only), Swift 6 strict-concurrency warnings.
- Hand-edited `project.pbxproj` entries (ids are hand-made) and the new `.xcdatamodel` loading in Xcode.
- Running the tests, and the lightweight migration on a real v13 store.
- Ladybug behaviour: the exact Cypher (`MERGE … SET`, `DETACH DELETE`, `BEGIN TRANSACTION`/`COMMIT`/`ROLLBACK`,
  `CREATE … IF NOT EXISTS`, rel table with an `id` property) and whether a garbage `.lbug` file throws at
  `Database(...)` init. The Swift API calls follow the upstream swift-ladybug sources
  (`Database(_:)`, `Connection`, `query`, `prepare`/`execute`, `getNext`/`getValue`); there is no Swift Ladybug code
  left in this repo (the Phase 0 harness was removed), so these could not be copied from existing code.
