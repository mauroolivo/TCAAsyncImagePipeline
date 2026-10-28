import ComposableArchitecture
import Foundation

@Reducer
struct ImagePipelineFeature {
    @ObservableState
    struct State {
        var duplicate = ExperimentState()
        var bounded = ExperimentState()
        var retry = ExperimentState()
        var cancellation = ExperimentState()
    }

    enum Action {
        case onAppear(ExperimentKind)
        case runTapped(ExperimentKind)
        case resetTapped(ExperimentKind)
        case cancelTapped(ExperimentKind)
        case appendEvent(ExperimentKind, LogEvent)
        case appendGalleryItem(ExperimentKind, GalleryItem)
        case setMetrics(ExperimentKind, PipelineMetrics?)
        case setRunning(ExperimentKind, Bool)
    }

    private let pipelines = PipelineRegistry()

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear(let kind):
                let keyPath = keyPath(for: kind)
                guard !state[keyPath: keyPath].didInstallLogHandler else { return .none }
                state[keyPath: keyPath].didInstallLogHandler = true

                let pipeline = pipelines.pipeline(for: kind)
                return .run { send in
                    await pipeline.setLogHandler { event in
                        Task { await send(.appendEvent(kind, event)) }
                    }
                    await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "GalleryModel initialized, pipeline ready", level: .info)))
                }

            case .runTapped(let kind):
                let keyPath = keyPath(for: kind)
                state[keyPath: keyPath].isRunning = true
                state[keyPath: keyPath].events.removeAll()
                state[keyPath: keyPath].gallery.removeAll()
                state[keyPath: keyPath].metrics = nil

                let pipeline = pipelines.pipeline(for: kind)
                switch kind {
                case .duplicate:
                    return runDuplicateExperiment(kind: kind, pipeline: pipeline)
                        .cancellable(id: cancelID(for: kind), cancelInFlight: true)
                case .bounded:
                    return runBoundedPrefetchExperiment(kind: kind, pipeline: pipeline)
                        .cancellable(id: cancelID(for: kind), cancelInFlight: true)
                case .retry:
                    return runFailureRetryExperiment(kind: kind, pipeline: pipeline)
                        .cancellable(id: cancelID(for: kind), cancelInFlight: true)
                case .cancellation:
                    return runCancellationExperiment(kind: kind, pipeline: pipeline)
                        .cancellable(id: cancelID(for: kind), cancelInFlight: true)
                }

            case .resetTapped(let kind):
                let keyPath = keyPath(for: kind)
                state[keyPath: keyPath].isRunning = false
                state[keyPath: keyPath].events.removeAll()
                state[keyPath: keyPath].gallery.removeAll()
                state[keyPath: keyPath].metrics = nil

                let pipeline = pipelines.pipeline(for: kind)
                return .merge(
                    .cancel(id: cancelID(for: kind)),
                    .run { _ in await pipeline.reset() }
                )

            case .cancelTapped(let kind):
                state[keyPath: keyPath(for: kind)].isRunning = false
                return .cancel(id: cancelID(for: kind))

            case let .appendEvent(kind, event):
                let keyPath = keyPath(for: kind)
                state[keyPath: keyPath].events.append(event)
                if state[keyPath: keyPath].events.count > 100 {
                    state[keyPath: keyPath].events.removeFirst()
                }
                return .none

            case let .appendGalleryItem(kind, item):
                state[keyPath: keyPath(for: kind)].gallery.append(item)
                return .none

            case let .setMetrics(kind, metrics):
                state[keyPath: keyPath(for: kind)].metrics = metrics
                return .none

            case let .setRunning(kind, isRunning):
                state[keyPath: keyPath(for: kind)].isRunning = isRunning
                return .none
            }
        }
    }

    private func runDuplicateExperiment(kind: ExperimentKind, pipeline: AsyncImagePipeline) -> Effect<Action> {
        .run { send in
            await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "=== DUPLICATE REQUEST EXPERIMENT START ===", level: .info)))
            let urls: [URL] = [NetworkLoader.imageURLs[0], NetworkLoader.imageURLs[1], NetworkLoader.imageURLs[0]]

            await withTaskGroup(of: PipelineFetch.self) { group in
                for url in urls {
                    group.addTask { await pipeline.fetch(url: url) }
                }
                for await result in group {
                    let hasImage = result.image != nil
                    await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "\(result.source.description) - \(String(format: "%.2fs", result.duration))", level: hasImage ? .success : .error)))
                    if let image = result.image {
                        await send(.appendGalleryItem(kind, GalleryItem(image: image)))
                    }
                }
            }

            let metrics = await pipeline.getMetrics()
            await send(.setMetrics(kind, metrics))
            await send(.setRunning(kind, false))
        }
    }

    private func runBoundedPrefetchExperiment(kind: ExperimentKind, pipeline: AsyncImagePipeline) -> Effect<Action> {
        .run { send in
            await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "Starting bounded prefetch experiment", level: .info)))
            let urls = Array(NetworkLoader.imageURLs.prefix(4))
            let fetches = await pipeline.fetchBatch(urls: urls, maxConcurrent: 2)

            for fetch in fetches {
                let hasImage = fetch.image != nil
                await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: fetch.source.description, level: hasImage ? .success : .error)))
                if let image = fetch.image {
                    await send(.appendGalleryItem(kind, GalleryItem(image: image)))
                }
            }

            await send(.setMetrics(kind, await pipeline.getMetrics()))
            await send(.setRunning(kind, false))
        }
    }

    private func runFailureRetryExperiment(kind: ExperimentKind, pipeline: AsyncImagePipeline) -> Effect<Action> {
        .run { send in
            let url = NetworkLoader.imageURLs[2]
            await pipeline.simulateFailure(for: url)

            let first = await pipeline.fetch(url: url)
            await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "Attempt 1: \(first.source.description)", level: .warning)))

            try? await Task.sleep(nanoseconds: 500_000_000)
            let second = await pipeline.fetch(url: url)
            await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "Attempt 2: \(second.source.description)", level: second.image == nil ? .error : .success)))

            if let image = second.image {
                await send(.appendGalleryItem(kind, GalleryItem(image: image)))
            }

            await send(.setMetrics(kind, await pipeline.getMetrics()))
            await send(.setRunning(kind, false))
        }
    }

    private func runCancellationExperiment(kind: ExperimentKind, pipeline: AsyncImagePipeline) -> Effect<Action> {
        .run { send in
            let url = NetworkLoader.imageURLs[3]
            let taskA = Task { await pipeline.fetch(url: url) }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let taskB = Task { await pipeline.fetch(url: url) }

            try? await Task.sleep(nanoseconds: 150_000_000)
            taskA.cancel()
            let resultB = await taskB.value

            await send(.appendEvent(kind, LogEvent(timestamp: Date(), message: "Caller B: \(resultB.source.description)", level: resultB.image == nil ? .error : .success)))
            if let image = resultB.image {
                await send(.appendGalleryItem(kind, GalleryItem(image: image)))
            }

            await send(.setMetrics(kind, await pipeline.getMetrics()))
            await send(.setRunning(kind, false))
        }
    }

    private func keyPath(for kind: ExperimentKind) -> WritableKeyPath<State, ExperimentState> {
        switch kind {
        case .duplicate: return \.duplicate
        case .bounded: return \.bounded
        case .retry: return \.retry
        case .cancellation: return \.cancellation
        }
    }

    private func cancelID(for kind: ExperimentKind) -> String {
        switch kind {
        case .duplicate: return "duplicate_experiment"
        case .bounded: return "bounded_experiment"
        case .retry: return "retry_experiment"
        case .cancellation: return "cancellation_experiment"
        }
    }
}

extension ImagePipelineFeature {
    struct ExperimentState {
        var events: [LogEvent] = []
        var gallery: [GalleryItem] = []
        var isRunning = false
        var metrics: PipelineMetrics?
        var didInstallLogHandler = false
    }

    enum ExperimentKind: CaseIterable, Hashable {
        case duplicate
        case bounded
        case retry
        case cancellation

        var title: String {
            switch self {
            case .duplicate: return "Duplicate Requests"
            case .bounded: return "Bounded Prefetch"
            case .retry: return "Failure & Retry"
            case .cancellation: return "Cancellation"
            }
        }

        var description: String {
            switch self {
            case .duplicate: return "Submit 3 requests, including a duplicate. Shows in-flight deduplication."
            case .bounded: return "Load 4 images with max 2 concurrent. Shows bounded concurrency."
            case .retry: return "Trigger failure, then retry. Shows eviction semantics."
            case .cancellation: return "Cancel one waiter, let shared work complete for another."
            }
        }

        var actionTitle: String {
            switch self {
            case .duplicate: return "Run Duplicate Requests"
            case .bounded: return "Run Bounded Prefetch"
            case .retry: return "Run Failure & Retry"
            case .cancellation: return "Run Cancellation"
            }
        }

        var tabTitle: String {
            switch self {
            case .duplicate: return "Duplicate"
            case .bounded: return "Bounded"
            case .retry: return "Retry"
            case .cancellation: return "Cancel"
            }
        }

        var tabImage: String {
            switch self {
            case .duplicate: return "doc.on.doc"
            case .bounded: return "arrow.down.circle"
            case .retry: return "arrow.clockwise.circle"
            case .cancellation: return "hand.raised.circle"
            }
        }
    }
}

private struct PipelineRegistry: Sendable {
    private let duplicate = AsyncImagePipeline()
    private let bounded = AsyncImagePipeline()
    private let retry = AsyncImagePipeline()
    private let cancellation = AsyncImagePipeline()

    func pipeline(for kind: ImagePipelineFeature.ExperimentKind) -> AsyncImagePipeline {
        switch kind {
        case .duplicate: return duplicate
        case .bounded: return bounded
        case .retry: return retry
        case .cancellation: return cancellation
        }
    }
}
