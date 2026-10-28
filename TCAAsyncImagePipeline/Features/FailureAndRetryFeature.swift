import ComposableArchitecture
import Foundation

@Reducer
struct FailureAndRetryFeature {
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
                    await client.setLogHandler(.retry) { event in
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
                return runFailureRetryExperiment(client: client)
                    .cancellable(id: "retry_experiment", cancelInFlight: true)

            case .resetTapped:
                state.isRunning = false
                state.events.removeAll()
                state.gallery.removeAll()
                state.metrics = nil

                let client = imagePipelineClient
                return .merge(
                    .cancel(id: "retry_experiment"),
                    .run { _ in await client.reset(.retry) }
                )

            case .cancelTapped:
                state.isRunning = false
                return .cancel(id: "retry_experiment")

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

    private func runFailureRetryExperiment(client: ImagePipelineClient) -> Effect<Action> {
        .run { send in
            let url = NetworkLoader.imageURLs[2]
            await client.simulateFailure(.retry, url)

            let first = await client.fetch(.retry, url)
            await send(.appendEvent(LogEvent(timestamp: Date(), message: "Attempt 1: \(first.source.description)", level: .warning)))

            try? await Task.sleep(nanoseconds: 500_000_000)
            let second = await client.fetch(.retry, url)
            await send(.appendEvent(LogEvent(timestamp: Date(), message: "Attempt 2: \(second.source.description)", level: second.image == nil ? .error : .success)))

            if let image = second.image {
                await send(.appendGalleryItem(GalleryItem(image: image)))
            }

            await send(.setMetrics(await client.getMetrics(.retry)))
            await send(.setRunning(false))
        }
    }
}
