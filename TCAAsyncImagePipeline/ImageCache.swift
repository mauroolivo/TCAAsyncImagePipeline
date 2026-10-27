import Foundation

/// An actor that owns cached decoded images.
/// This isolation boundary ensures that cache mutations are safe under concurrency.
actor ImageCache: Sendable {
    private var storage: [URL: DecodedImage] = [:]
    
    /// Looks up a previously cached decoded image by URL.
    nonisolated func read(url: URL) async -> DecodedImage? {
        await _read(url: url)
    }
    
    private func _read(url: URL) -> DecodedImage? {
        storage[url]
    }
    
    /// Inserts a decoded image into the cache.
    nonisolated func insert(_ image: DecodedImage) async {
        await _insert(image)
    }
    
    private func _insert(_ image: DecodedImage) {
        storage[image.url] = image
    }
    
    /// Clears the entire cache.
    nonisolated func clear() async {
        await _clear()
    }
    
    private func _clear() {
        storage.removeAll()
    }
    
    /// Returns current cache size for diagnostics.
    nonisolated func size() async -> Int {
        await _size()
    }
    
    private func _size() -> Int {
        storage.count
    }
}
