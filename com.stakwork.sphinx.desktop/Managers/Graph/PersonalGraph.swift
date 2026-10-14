//
//  PersonalGraph.swift
//  sphinx
//
//  Owner of the ONE shared GraphJournalService (Ladybug takes a file lock, so there
//  must be a single instance per process).
//
import Foundation

enum PersonalGraph {

    /// nil only if the Application Support location cannot be resolved.
    static let service: GraphJournalService? = {
        guard let url = try? LadybugGraphStore.defaultFileURL() else {
            print("PersonalGraph: could not resolve graph file location")
            return nil
        }
        return GraphJournalService(
            container: CoreDataManager.sharedManager.persistentContainer,
            store: LadybugGraphStore(fileURL: url),
            clientIdProvider: AccountUUIDClientIdProvider()
        )
    }()

    /// Call once at launch. Creates the service on the calling thread (cheap, no I/O)
    /// and opens the store off the main thread.
    static func startInBackground() {
        guard let service = service else { return }
        Task.detached(priority: .utility) {
            do {
                try await service.start()
            } catch {
                print("PersonalGraph: start failed – \(error)")
            }
        }
    }

    /// Account wipe: closes Ladybug and deletes graph.lbug (+ sidecars). Fire-and-forget.
    static func destroyStoreInBackground() {
        guard let service = service else { return }
        Task.detached(priority: .utility) {
            do {
                try await service.destroyStore()
            } catch {
                print("PersonalGraph: wipe failed – \(error)")
            }
        }
    }
}
