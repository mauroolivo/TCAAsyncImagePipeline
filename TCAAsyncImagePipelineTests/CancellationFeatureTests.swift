import Combine
import ComposableArchitecture
import Foundation
import XCTest
@testable import TCAAsyncImagePipeline

@MainActor
final class CancellationFeatureTests: XCTestCase {
    func testCancellationKeepsSharedWorkAvailableForSecondCaller() async {
        let tracker = CancellationTracker()

        let store = Store(initialState: CancellationFeature.State()) {
            CancellationFeature()
        } withDependencies: {
            $0.imagePipelineClient = ImagePipelineClient(
                fetch: { _, url in
                    await tracker.fetch(url: url)
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
            var sharedInFlightHits: Int?
            var galleryCount: Int

            init(state: CancellationFeature.State) {
                self.isRunning = state.isRunning
                self.sharedInFlightHits = state.metrics?.sharedInFlightHits
                self.galleryCount = state.gallery.count
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

        XCTAssertEqual(viewStore.sharedInFlightHits, 1)
        XCTAssertEqual(viewStore.galleryCount, 1)
    }
}

private actor CancellationTracker {
    private var fetchCount = 0

    func fetch(url: URL) async -> PipelineFetch {
        fetchCount += 1
        if fetchCount == 1 {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        let image: DecodedImage? = fetchCount == 2
            ? DecodedImage(url: url, imageData: Data([1, 2, 3]), byteCount: 3, checksum: 6)
            : nil

        return PipelineFetch(
            url: url,
            source: fetchCount == 1 ? .newWork : .sharedInFlight,
            image: image,
            duration: 0.01
        )
    }

    func metrics() -> PipelineMetrics {
        PipelineMetrics(
            totalFetches: 2,
            newWorkStarts: 1,
            sharedInFlightHits: 1,
            cacheHits: 0,
            failures: 0,
            maxConcurrentRequests: 1,
            currentInFlightCount: 0
        )
    }

    func reset() {
        fetchCount = 0
    }
}
