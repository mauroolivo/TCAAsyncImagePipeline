import ComposableArchitecture
import Foundation

enum ImagePipelineID: Hashable, Sendable {
    case duplicate
    case bounded
    case retry
    case cancellation
}

struct ImagePipelineClient: Sendable {
    var fetch: @Sendable (_ pipelineID: ImagePipelineID, _ url: URL) async -> PipelineFetch
    var fetchBatch: @Sendable (_ pipelineID: ImagePipelineID, _ urls: [URL], _ maxConcurrent: Int) async -> [PipelineFetch]
    var getMetrics: @Sendable (_ pipelineID: ImagePipelineID) async -> PipelineMetrics
    var reset: @Sendable (_ pipelineID: ImagePipelineID) async -> Void
    var setLogHandler: @Sendable (_ pipelineID: ImagePipelineID, _ handler: @escaping @Sendable (LogEvent) -> Void) async -> Void
    var simulateFailure: @Sendable (_ pipelineID: ImagePipelineID, _ url: URL) async -> Void
}

extension DependencyValues {
    var imagePipelineClient: ImagePipelineClient {
        get { self[ImagePipelineClientKey.self] }
        set { self[ImagePipelineClientKey.self] = newValue }
    }
}

private enum ImagePipelineClientKey: DependencyKey {
    private static let registry = PipelineRegistry()

    static let liveValue = ImagePipelineClient(
        fetch: { pipelineID, url in
            let pipeline = await registry.pipeline(for: pipelineID)
            return await pipeline.fetch(url: url)
        },
        fetchBatch: { pipelineID, urls, maxConcurrent in
            let pipeline = await registry.pipeline(for: pipelineID)
            return await pipeline.fetchBatch(urls: urls, maxConcurrent: maxConcurrent)
        },
        getMetrics: { pipelineID in
            let pipeline = await registry.pipeline(for: pipelineID)
            return await pipeline.getMetrics()
        },
        reset: { pipelineID in
            let pipeline = await registry.pipeline(for: pipelineID)
            await pipeline.reset()
        },
        setLogHandler: { pipelineID, handler in
            let pipeline = await registry.pipeline(for: pipelineID)
            await pipeline.setLogHandler(handler)
        },
        simulateFailure: { pipelineID, url in
            let pipeline = await registry.pipeline(for: pipelineID)
            await pipeline.simulateFailure(for: url)
        }
    )
}

private actor PipelineRegistry {
    private var storage: [ImagePipelineID: AsyncImagePipeline] = [:]

    func pipeline(for id: ImagePipelineID) -> AsyncImagePipeline {
        if let existing = storage[id] {
            return existing
        }
        let pipeline = AsyncImagePipeline()
        storage[id] = pipeline
        return pipeline
    }
}
