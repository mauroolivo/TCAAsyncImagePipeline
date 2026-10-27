import Foundation

/// Represents a successfully decoded image with metadata.
public struct DecodedImage: Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    public let imageData: Data
    public let byteCount: Int
    public let checksum: Int
    
    public nonisolated var filename: String { url.lastPathComponent }
    
    public nonisolated init(url: URL, imageData: Data, byteCount: Int, checksum: Int) {
        self.id = UUID()
        self.url = url
        self.imageData = imageData
        self.byteCount = byteCount
        self.checksum = checksum
    }
}

/// Describes where a fetch result came from in the pipeline.
public enum FetchSource: Sendable {
    case cacheHit
    case newWork
    case sharedInFlight
    case failed(String)
    
    var description: String {
        switch self {
        case .cacheHit:
            return "cache hit"
        case .newWork:
            return "new work"
        case .sharedInFlight:
            return "shared in-flight"
        case .failed(let reason):
            return "failed: \(reason)"
        }
    }
}

/// The result of a single fetch operation through the pipeline.
public struct PipelineFetch: Sendable {
    let url: URL
    let source: FetchSource
    let image: DecodedImage?
    let duration: TimeInterval
    
    var succeeded: Bool {
        if case .failed = source {
            return false
        }
        return image != nil
    }
}

/// Errors that can occur in the pipeline.
public enum PipelineError: Error, Sendable, CustomStringConvertible {
    case transientFailure(url: URL)
    case networkError(String)
    case decodeError(String)
    
    public var description: String {
        switch self {
        case .transientFailure(let url):
            return "Transient failure for \(url.lastPathComponent)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .decodeError(let msg):
            return "Decode error: \(msg)"
        }
    }
}

/// Event logged during pipeline operations.
public struct LogEvent: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let timestamp: Date
    public let message: String
    public let level: Level
    
    public enum Level: String, Sendable {
        case info
        case success
        case warning
        case error
    }
}

/// Metrics exposed by the pipeline for observability.
public struct PipelineMetrics: Sendable {
    public let totalFetches: Int
    public let newWorkStarts: Int
    public let sharedInFlightHits: Int
    public let cacheHits: Int
    public let failures: Int
    public let maxConcurrentRequests: Int
    public let currentInFlightCount: Int
}

/// Wrapper for gallery display that ensures each displayed item has a unique ID,
/// even when displaying the same DecodedImage multiple times (e.g., duplicate requests).
public struct GalleryItem: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let image: DecodedImage
}
