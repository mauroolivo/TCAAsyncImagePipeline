import Combine
import ComposableArchitecture
import Foundation
import XCTest
@testable import TCAAsyncImagePipeline

@MainActor
final class DuplicateRequestsFeatureTests: XCTestCase {
    func testDuplicateRequestsProducesExpectedDedupMetrics() async {
        let tracker = DedupTracker()

        let store = Store(initialState: DuplicateRequestsFeature.State()) {
            DuplicateRequestsFeature()
        } withDependencies: {
            $0.imagePipelineClient = ImagePipelineClient(
                fetch: { _, url in
                    let source = await tracker.recordAndClassify(url: url)
                    return PipelineFetch(url: url, source: source, image: nil, duration: 0.01)
                },
                fetchBatch: { _, _, _ in [] },
                getMetrics: { _ in
                    await tracker.metrics()
                },
                reset: { _ in
                    await tracker.reset()
                },
                setLogHandler: { _, _ in },
                simulateFailure: { _, _ in }
            )
        }

        struct ViewState: Equatable {
            var isRunning: Bool
            var newWorkStarts: Int?
            var sharedInFlightHits: Int?

            init(state: DuplicateRequestsFeature.State) {
                self.isRunning = state.isRunning
                self.newWorkStarts = state.metrics?.newWorkStarts
                self.sharedInFlightHits = state.metrics?.sharedInFlightHits
            }
        }

        let viewStore = ViewStore(store, observe: ViewState.init)

        let completed = expectation(description: "experiment completes")
        var cancellables = Set<AnyCancellable>()
        viewStore.publisher.isRunning
            .dropFirst()
            .sink { isRunning in
                if !isRunning {
                    completed.fulfill()
                }
            }
            .store(in: &cancellables)

        viewStore.send(.runTapped)
        await fulfillment(of: [completed], timeout: 1.0)

        XCTAssertEqual(viewStore.newWorkStarts, 2)
        XCTAssertEqual(viewStore.sharedInFlightHits, 1)
    }
}

private actor DedupTracker {
    private var seenCounts: [URL: Int] = [:]

    func recordAndClassify(url: URL) -> FetchSource {
        let nextCount = (seenCounts[url] ?? 0) + 1
        seenCounts[url] = nextCount
        return nextCount == 1 ? .newWork : .sharedInFlight
    }

    func metrics() -> PipelineMetrics {
        let newWork = seenCounts.values.filter { $0 >= 1 }.count
        let shared = seenCounts.values.map { max(0, $0 - 1) }.reduce(0, +)
        let total = seenCounts.values.reduce(0, +)

        return PipelineMetrics(
            totalFetches: total,
            newWorkStarts: newWork,
            sharedInFlightHits: shared,
            cacheHits: 0,
            failures: 0,
            maxConcurrentRequests: 0,
            currentInFlightCount: 0
        )
    }

    func reset() {
        seenCounts = [:]
    }
}
