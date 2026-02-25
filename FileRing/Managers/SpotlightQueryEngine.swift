//
//  SpotlightQueryEngine.swift
//  FileRing
//
//  Shared NSMetadataQuery execution engine used by SpotlightManager and AppSpotlightManager
//

import Foundation
import os.log

/// Context for a single in-flight Spotlight query
final class SpotlightQueryContext {
    let query: NSMetadataQuery
    let continuation: CheckedContinuation<[NSMetadataItem], Error>
    var timeoutTask: Task<Void, Never>?

    init(query: NSMetadataQuery, continuation: CheckedContinuation<[NSMetadataItem], Error>) {
        self.query = query
        self.continuation = continuation
    }
}

/// Token to relay the query identifier into the cancellation handler
private final class SpotlightCancellationToken: @unchecked Sendable {
    var identifier: ObjectIdentifier?
}

/// Parameters that describe a single Spotlight query
struct SpotlightQueryDescriptor {
    let searchScopes: [Any]
    let predicate: NSCompoundPredicate
    let sortDescriptors: [NSSortDescriptor]
    let timeoutSeconds: Int
}

/// Shared engine that manages NSMetadataQuery lifecycle:
/// creation, notification handling, timeout, cancellation, and cleanup.
@MainActor
class SpotlightQueryEngine: NSObject {
    private var activeQueries: [ObjectIdentifier: SpotlightQueryContext] = [:]

    /// Execute a Spotlight query described by `descriptor` and return raw metadata items.
    func execute(_ descriptor: SpotlightQueryDescriptor) async throws -> [NSMetadataItem] {
        let cancellationToken = SpotlightCancellationToken()

        let signpostID = OSSignpostID(log: .pointsOfInterest)
        os_signpost(.begin, log: .pointsOfInterest, name: "SpotlightQuery", signpostID: signpostID)

        let items = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = NSMetadataQuery()
                let identifier = ObjectIdentifier(query)

                let context = SpotlightQueryContext(query: query, continuation: continuation)
                activeQueries[identifier] = context
                cancellationToken.identifier = identifier

                query.searchScopes = descriptor.searchScopes
                query.predicate = descriptor.predicate
                query.sortDescriptors = descriptor.sortDescriptors

                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(queryDidFinishGathering),
                    name: .NSMetadataQueryDidFinishGathering,
                    object: query
                )

                query.start()

                let timeoutSeconds = descriptor.timeoutSeconds
                context.timeoutTask = Task { [weak self, weak query] in
                    guard let query = query else { return }
                    guard let self = self else { return }
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                        if Task.isCancelled { return }
                        await self.handleTimeout(for: query)
                    } catch {
                        // Task cancelled, no-op
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                guard let id = cancellationToken.identifier else { return }
                self.cancelQuery(with: id, error: CancellationError())
            }
        }

        os_signpost(.end, log: .pointsOfInterest, name: "SpotlightQuery", signpostID: signpostID, "Found %d raw items", items.count)
        return items
    }

    // MARK: - Notification Handling

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery else { return }

        let identifier = ObjectIdentifier(query)
        guard let context = activeQueries.removeValue(forKey: identifier) else { return }

        context.timeoutTask?.cancel()
        query.disableUpdates()

        var items: [NSMetadataItem] = []
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem {
                items.append(item)
            }
        }

        query.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        context.continuation.resume(returning: items)
    }

    // MARK: - Timeout & Cancellation

    private func handleTimeout(for query: NSMetadataQuery) async {
        cancelQuery(with: ObjectIdentifier(query), error: SpotlightError.timeout)
    }

    private func cancelQuery(with identifier: ObjectIdentifier, error: Error) {
        guard let context = activeQueries.removeValue(forKey: identifier) else { return }

        context.timeoutTask?.cancel()

        let query = context.query
        query.disableUpdates()
        query.stop()

        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)

        context.continuation.resume(throwing: error)
    }

    // MARK: - Cleanup

    @MainActor deinit {
        for (_, context) in activeQueries {
            context.timeoutTask?.cancel()
            context.query.disableUpdates()
            context.query.stop()
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: context.query)
            context.continuation.resume(throwing: SpotlightError.queryFailed("Deinit before completion"))
        }
        activeQueries.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}
