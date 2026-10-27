import Foundation

/// An actor that coordinates duplicate request deduplication.
/// It owns the in-flight task dictionary and ensures that duplicate callers share a single underlying operation.
/// This is the central deduplication pattern: Entry can be either in-progress work or a ready result.
actor DownloadCoordinator: Sendable {
    
    enum Entry {
        case inProgress(Task<DecodedImage, Error>)
        case ready(DecodedImage)
    }
    
    private var inFlight: [URL: Entry] = [:]
    private(set) var newWorkCount: Int = 0
    private(set) var sharedInFlightCount: Int = 0
    
    /// Attempts to find or create an in-flight task for the given URL.
    /// Returns a tuple of (task, isNewWork).
    func retrieveOrCreate(
        url: URL,
        creator: @Sendable @escaping () async throws -> DecodedImage
    ) -> (Task<DecodedImage, Error>, isNew: Bool) {
        // Check if we already have something for this URL
        if let entry = inFlight[url] {
            switch entry {
            case .inProgress(let task):
                // There's already in-flight work; reuse it
                sharedInFlightCount += 1
                return (task, false)
            case .ready(let image):
                // Already completed; create a new task that immediately returns the result
                let immediateTask: Task<DecodedImage, Error> = Task {
                    return image
                }
                return (immediateTask, false)
            }
        }
        
        // No existing work; create new
        let newTask: Task<DecodedImage, Error> = Task {
            try await creator()
        }
        newWorkCount += 1
        inFlight[url] = .inProgress(newTask)
        return (newTask, true)
    }
    
    /// Marks in-flight work as complete with a successful result.
    nonisolated func markReady(url: URL, image: DecodedImage) async {
        await _markReady(url: url, image: image)
    }
    
    private func _markReady(url: URL, image: DecodedImage) {
        inFlight[url] = .ready(image)
    }
    
    /// Evicts a failed entry so that retry attempts start fresh.
    /// This is critical for correct retry semantics.
    nonisolated func evictFailed(url: URL) async {
        await _evictFailed(url: url)
    }
    
    private func _evictFailed(url: URL) {
        inFlight.removeValue(forKey: url)
    }
    
    /// Clears all in-flight state.
    nonisolated func clear() async {
        await _clear()
    }
    
    private func _clear() {
        inFlight.removeAll()
        newWorkCount = 0
        sharedInFlightCount = 0
    }
    
    /// Returns current in-flight count for metrics.
    nonisolated func inFlightCount() async -> Int {
        await _inFlightCount()
    }
    
    private func _inFlightCount() -> Int {
        inFlight.count
    }
}
