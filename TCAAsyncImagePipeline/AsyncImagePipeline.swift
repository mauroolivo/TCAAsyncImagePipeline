import Foundation

/// The public façade for the image pipeline.
/// This is the single entry point that orchestrates cache, coordinator, and loader.
/// All public methods return Sendable-safe results.
public actor AsyncImagePipeline: Sendable {
    private let cache: ImageCache
    private let coordinator: DownloadCoordinator
    private let loader: NetworkLoader
    
    private var logHandler: (@Sendable (LogEvent) -> Void)?
    
    public init() {
        self.cache = ImageCache()
        self.coordinator = DownloadCoordinator()
        self.loader = NetworkLoader()
    }
    
    /// Fetches a single image, using cache and deduplication.
    public nonisolated func fetch(url: URL) async -> PipelineFetch {
        await _fetch(url: url)
    }
    
    private func _fetch(url: URL) async -> PipelineFetch {
        let startTime = Date()
        
        // Check cache first
        if let cachedImage = await cache.read(url: url) {
            let duration = Date().timeIntervalSince(startTime)
            log("Cache hit for \(url.lastPathComponent)", level: .success)
            return PipelineFetch(url: url, source: .cacheHit, image: cachedImage, duration: duration)
        }
        
        log("Cache miss for \(url.lastPathComponent), fetching...", level: .info)
        
        // Try to get or create in-flight work
        let (task, isNewWork) = await coordinator.retrieveOrCreate(url: url) { [weak self] in
            do {
                guard let self = self else { throw PipelineError.networkError("Pipeline deallocated") }
                return try await self.loader.fetch(url: url)
            } catch {
                // Evict failed entry so retry works
                if let self = self {
                    await self.coordinator.evictFailed(url: url)
                }
                throw error
            }
        }
        
        // Await the result
        do {
            let image = try await task.value
            
            // Cache the result
            await cache.insert(image)
            
            // Mark as ready in coordinator
            await coordinator.markReady(url: url, image: image)
            
            let duration = Date().timeIntervalSince(startTime)
            let source: FetchSource = isNewWork ? .newWork : .sharedInFlight
            
            if isNewWork {
                log("✓ New work completed for \(url.lastPathComponent) - \(image.byteCount) bytes", level: .success)
            } else {
                log("✓ Shared in-flight result for \(url.lastPathComponent)", level: .success)
            }
            
            return PipelineFetch(url: url, source: source, image: image, duration: duration)
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            let errorMsg = (error as? PipelineError)?.description ?? error.localizedDescription
            log("✗ Fetch failed for \(url.lastPathComponent): \(errorMsg)", level: .error)
            return PipelineFetch(url: url, source: .failed(errorMsg), image: nil, duration: duration)
        }
    }
    
    /// Fetches a batch of images with bounded concurrency.
    /// The concurrency limit prevents overwhelming the system with too many simultaneous requests.
    public nonisolated func fetchBatch(
        urls: [URL],
        maxConcurrent: Int = 2
    ) async -> [PipelineFetch] {
        await _fetchBatch(urls: urls, maxConcurrent: maxConcurrent)
    }
    
    private func _fetchBatch(urls: [URL], maxConcurrent: Int) async -> [PipelineFetch] {
        var results: [URL: PipelineFetch] = [:]
        
        // Use a task group with bounded submission
        await withTaskGroup(of: PipelineFetch.self) { group in
            var urlIterator = urls.makeIterator()
            var submitted = 0
            
            // Submit initial batch up to maxConcurrent
            while submitted < maxConcurrent, let url = urlIterator.next() {
                group.addTask {
                    await self._fetch(url: url)
                }
                submitted += 1
            }
            
            // Process results and submit remaining work
            for await result in group {
                results[result.url] = result
                
                if let nextURL = urlIterator.next() {
                    group.addTask {
                        await self._fetch(url: nextURL)
                    }
                }
            }
        }
        
        // Return results in original order
        return urls.compactMap { url in
            results[url]
        }
    }
    
    /// Returns current pipeline metrics for observability.
    public nonisolated func getMetrics() async -> PipelineMetrics {
        await _getMetrics()
    }
    
    private func _getMetrics() async -> PipelineMetrics {
        let (totalRequests, maxConcurrent, _) = await loader.metrics()
        let newWorkStarts = await coordinator.newWorkCount
        let sharedInFlightHits = await coordinator.sharedInFlightCount
        let cacheSize = await cache.size()
        let inFlightCount = await coordinator.inFlightCount()
        
        return PipelineMetrics(
            totalFetches: totalRequests,
            newWorkStarts: newWorkStarts,
            sharedInFlightHits: sharedInFlightHits,
            cacheHits: cacheSize,
            failures: 0,  // Could track this if needed
            maxConcurrentRequests: maxConcurrent,
            currentInFlightCount: inFlightCount
        )
    }
    
    /// Sets a logging callback for pipeline events.
    public func setLogHandler(_ handler: @Sendable @escaping (LogEvent) -> Void) {
        self.logHandler = handler
    }
    
    /// Resets the entire pipeline (cache, coordinator, loader state).
    /// Useful for repeatable demonstrations.
    public nonisolated func reset() async {
        await _reset()
    }
    
    private func _reset() async {
        await cache.clear()
        await coordinator.clear()
        await loader.reset()
        log("Pipeline reset", level: .info)
    }
    
    /// Simulates a transient failure for testing retry behavior.
    public nonisolated func simulateFailure(for url: URL) async {
        await _simulateFailure(for: url)
    }
    
    private func _simulateFailure(for url: URL) async {
        await loader.simulateFailure(for: url)
    }
    
    private func log(_ message: String, level: LogEvent.Level) {
        let event = LogEvent(timestamp: Date(), message: message, level: level)
        logHandler?(event)
    }
}
