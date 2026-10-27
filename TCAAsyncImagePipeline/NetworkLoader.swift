import Foundation
import UIKit
/// An actor that performs real network operations and decode work.
/// It tracks metrics like request counts and maximum concurrent requests.
/// It also simulates transient failures for specific URLs to demonstrate retry behavior.
actor NetworkLoader: Sendable {
    private enum LatencyPolicy {
        // Natural latency comes from URLSession; this is the artificial stagger.
        static let perRequestIncrementSeconds: Double = 0.5
    }
    
    // curated list of real image URLs from picsum.photos for reproducibility
    static let imageURLs: [URL] = [
        URL(string: "https://picsum.photos/id/1025/800/600")!,
        URL(string: "https://picsum.photos/id/1011/800/600")!,
        URL(string: "https://picsum.photos/id/1003/800/600")!,
        URL(string: "https://picsum.photos/id/1015/800/600")!,
        URL(string: "https://picsum.photos/id/1020/800/600")!,
    ]
    
    private var totalRequests: Int = 0
    private var currentConcurrentRequests: Int = 0
    private var maxConcurrentRequests: Int = 0
    private var failureURLs: Set<URL> = []
    private var requestSequence: Int = 0
    
    /// Loads and decodes an image from the network.
    nonisolated func fetch(url: URL) async throws -> DecodedImage {
        try await _fetch(url: url)
    }
    
    private func _fetch(url: URL) async throws -> DecodedImage {
        try Task.checkCancellation()

        // Check if this URL should fail (simulating transient failure)
        if failureURLs.contains(url) {
            failureURLs.remove(url)  // One-time failure
            throw PipelineError.transientFailure(url: url)
        }
        
        // Track concurrent request count
        totalRequests += 1
        currentConcurrentRequests += 1
        maxConcurrentRequests = max(maxConcurrentRequests, currentConcurrentRequests)
        defer { currentConcurrentRequests -= 1 }
        
        AppDiagnostics.log("[NetworkLoader] Starting fetch for: \(url.absoluteString)")
        
        do {
            let addedLatency = nextAddedLatencySeconds()
            if addedLatency > 0 {
                let nanos = UInt64(addedLatency * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanos)
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            AppDiagnostics.log("[NetworkLoader] Received \(data.count) bytes from \(url.lastPathComponent)")

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw PipelineError.networkError("HTTP \(statusCode) for \(url.lastPathComponent)")
            }

            guard !data.isEmpty else {
                throw PipelineError.networkError("Empty response body for \(url.lastPathComponent)")
            }

            try Task.checkCancellation()
            let decoded = try decodeImage(data, url: url)
            AppDiagnostics.log("[NetworkLoader] ✓ Successfully decoded \(decoded.byteCount) bytes for \(url.lastPathComponent)")
            return decoded
        } catch is CancellationError {
            AppDiagnostics.log("[NetworkLoader] ✗ Cancelled: \(url.lastPathComponent)")
            throw CancellationError()
        } catch let error as PipelineError {
            AppDiagnostics.log("[NetworkLoader] ✗ PipelineError: \(error.description)")
            throw error
        } catch {
            AppDiagnostics.log("[NetworkLoader] ✗ Error: \(error.localizedDescription)")
            throw PipelineError.networkError("Failed to fetch \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
    
    /// Simulates a transient failure for the next fetch of this URL.
    /// Used for demonstrating failure eviction and retry scenarios.
    nonisolated func simulateFailure(for url: URL) async {
        await _simulateFailure(for: url)
    }
    
    private func _simulateFailure(for url: URL) {
        failureURLs.insert(url)
    }
    
    /// Returns current metrics for the loader.
    nonisolated func metrics() async -> (totalRequests: Int, maxConcurrent: Int, currentConcurrent: Int) {
        await _metrics()
    }
    
    private func _metrics() -> (totalRequests: Int, maxConcurrent: Int, currentConcurrent: Int) {
        (totalRequests, maxConcurrentRequests, currentConcurrentRequests)
    }
    
    /// Resets all metrics.
    nonisolated func reset() async {
        await _reset()
    }
    
    private func _reset() {
        totalRequests = 0
        currentConcurrentRequests = 0
        maxConcurrentRequests = 0
        failureURLs.removeAll()
        requestSequence = 0
    }

    private func nextAddedLatencySeconds() -> Double {
        requestSequence += 1
        let added = Double(requestSequence) * LatencyPolicy.perRequestIncrementSeconds
        AppDiagnostics.log("[NetworkLoader] Added artificial latency: +\(String(format: "%.2f", added))s (request #\(requestSequence))")
        return added
    }
}

/// Decodes image data with concurrent work, isolated from the UI actor.
/// This demonstrates that expensive compute should be moved off MainActor.
nonisolated
func decodeImage(_ data: Data, url: URL) throws -> DecodedImage {
    guard !data.isEmpty else {
        throw PipelineError.decodeError("No image data received for \(url.lastPathComponent)")
    }

    // Verify image bytes can be decoded into an image object.
    guard UIImage(data: data) != nil else {
        throw PipelineError.decodeError("Failed to decode image bytes for \(url.lastPathComponent)")
    }
    
    // Compute checksum
    let checksum = data.reduce(0) { $0 &+ UInt32($1) }
    return DecodedImage(
        url: url,
        imageData: data,
        byteCount: data.count,
        checksum: Int(checksum)
    )
}
