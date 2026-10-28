import ComposableArchitecture
import Foundation

@Reducer
struct BoundedPrefetchFeature {
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
                    await client.setLogHandler(.bounded) { event in
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
                return runBoundedPrefetchExperiment(client: client)
                    .cancellable(id: "bounded_experiment", cancelInFlight: true)

            case .resetTapped:
                state.isRunning = false
                state.events.removeAll()
                state.gallery.removeAll()
                state.metrics = nil

                let client = imagePipelineClient
                return .merge(
                    .cancel(id: "bounded_experiment"),
                    .run { _ in await client.reset(.bounded) }
                )

            case .cancelTapped:
                state.isRunning = false
                return .cancel(id: "bounded_experiment")

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

    private func runBoundedPrefetchExperiment(client: ImagePipelineClient) -> Effect<Action> {
        .run { send in
            await send(.appendEvent(LogEvent(timestamp: Date(), message: "Starting bounded prefetch experiment", level: .info)))
            let urls = Array(NetworkLoader.imageURLs.prefix(4))
            let fetches = await client.fetchBatch(.bounded, urls, 2)

            for fetch in fetches {
                let hasImage = fetch.image != nil
                await send(.appendEvent(LogEvent(timestamp: Date(), message: fetch.source.description, level: hasImage ? .success : .error)))
                if let image = fetch.image {
                    await send(.appendGalleryItem(GalleryItem(image: image)))
                }
            }

            await send(.setMetrics(await client.getMetrics(.bounded)))
            await send(.setRunning(false))
        }
    }
}
