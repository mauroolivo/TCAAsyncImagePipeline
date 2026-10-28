import ComposableArchitecture
import Foundation

@Reducer
struct DuplicateRequestsFeature {
    @Dependency(\.imagePipelineClient) var imagePipelineClient

    @ObservableState
    struct State {
        var events: [LogEvent] = []
        var gallery: [GalleryItem] = []
        var isRunning = false
        var metrics: PipelineMetrics?
        var didInstallLogHandler = false
    }

    @CasePathable
    enum Action {
        case onAppear
        case runTapped
        case resetTapped
        case cancelTapped
        case appendEvent(LogEvent)
        case appendGalleryItem(GalleryItem)
        case setMetrics(PipelineMetrics?)
        case setRunning(Bool)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.didInstallLogHandler else { return .none }
                state.didInstallLogHandler = true

                let client = imagePipelineClient
                return .run { send in
                    await send(.appendEvent(LogEvent(timestamp: Date(), message: "GalleryModel initialized, pipeline ready", level: .info)))

                    let (stream, continuation) = AsyncStream<LogEvent>.makeStream()
                    await client.setLogHandler(.duplicate) { event in
                        continuation.yield(event)
                    }

                    for await event in stream {
                        await send(.appendEvent(event))
                    }
                }

            case .runTapped:
                state.isRunning = true
                state.events.removeAll()
                state.gallery.removeAll()
                state.metrics = nil

                let client = imagePipelineClient
                return runDuplicateExperiment(client: client)
                    .cancellable(id: "duplicate_experiment", cancelInFlight: true)

            case .resetTapped:
                state.isRunning = false
                state.events.removeAll()
                state.gallery.removeAll()
                state.metrics = nil

                let client = imagePipelineClient
                return .merge(
                    .cancel(id: "duplicate_experiment"),
                    .run { _ in await client.reset(.duplicate) }
                )

            case .cancelTapped:
                state.isRunning = false
                return .cancel(id: "duplicate_experiment")

            case let .appendEvent(event):
                state.events.append(event)
                if state.events.count > 100 {
                    state.events.removeFirst()
                }
                return .none

            case let .appendGalleryItem(item):
                state.gallery.append(item)
                return .none

            case let .setMetrics(metrics):
                state.metrics = metrics
                return .none

            case let .setRunning(isRunning):
                state.isRunning = isRunning
                return .none
            }
        }
    }

    private func runDuplicateExperiment(client: ImagePipelineClient) -> Effect<Action> {
        .run { send in
            await send(.appendEvent(LogEvent(timestamp: Date(), message: "=== DUPLICATE REQUEST EXPERIMENT START ===", level: .info)))
            let urls: [URL] = [NetworkLoader.imageURLs[0], NetworkLoader.imageURLs[1], NetworkLoader.imageURLs[0]]

            await withTaskGroup(of: PipelineFetch.self) { group in
                for url in urls {
                    group.addTask { await client.fetch(.duplicate, url) }
                }
                for await result in group {
                    let hasImage = result.image != nil
                    await send(.appendEvent(LogEvent(timestamp: Date(), message: "\(result.source.description) - \(String(format: "%.2fs", result.duration))", level: hasImage ? .success : .error)))
                    if let image = result.image {
                        await send(.appendGalleryItem(GalleryItem(image: image)))
                    }
                }
            }

            let metrics = await client.getMetrics(.duplicate)
            await send(.setMetrics(metrics))
            await send(.setRunning(false))
        }
    }
}
