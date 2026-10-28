import ComposableArchitecture
import Foundation

@Reducer
struct CancellationFeature {
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
                    await client.setLogHandler(.cancellation) { event in
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
                return runCancellationExperiment(client: client)
                    .cancellable(id: "cancellation_experiment", cancelInFlight: true)

            case .resetTapped:
                state.isRunning = false
                state.events.removeAll()
                state.gallery.removeAll()
                state.metrics = nil

                let client = imagePipelineClient
                return .merge(
                    .cancel(id: "cancellation_experiment"),
                    .run { _ in await client.reset(.cancellation) }
                )

            case .cancelTapped:
                state.isRunning = false
                return .cancel(id: "cancellation_experiment")

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

    private func runCancellationExperiment(client: ImagePipelineClient) -> Effect<Action> {
        .run { send in
            let url = NetworkLoader.imageURLs[3]
            let taskA = Task { await client.fetch(.cancellation, url) }
            try? await Task.sleep(nanoseconds: 100_000_000)
            let taskB = Task { await client.fetch(.cancellation, url) }

            try? await Task.sleep(nanoseconds: 150_000_000)
            taskA.cancel()
            let resultB = await taskB.value

            await send(.appendEvent(LogEvent(timestamp: Date(), message: "Caller B: \(resultB.source.description)", level: resultB.image == nil ? .error : .success)))
            if let image = resultB.image {
                await send(.appendGalleryItem(GalleryItem(image: image)))
            }

            await send(.setMetrics(await client.getMetrics(.cancellation)))
            await send(.setRunning(false))
        }
    }
}
