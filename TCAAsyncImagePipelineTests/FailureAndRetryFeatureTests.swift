import Combine
import ComposableArchitecture
import Foundation
import XCTest
@testable import TCAAsyncImagePipeline

@MainActor
final class FailureAndRetryFeatureTests: XCTestCase {
    func testRetryCreatesFreshWorkAfterFailure() async {
        let tracker = RetryTracker()

        let store = Store(initialState: FailureAndRetryFeature.State()) {
            FailureAndRetryFeature()
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
                simulateFailure: { _, url in
                    await tracker.markFailure(url: url)
                }
            )
        }

        struct ViewState: Equatable {
            var isRunning: Bool
            var failures: Int?
            var newWorkStarts: Int?
            var galleryCount: Int

            init(state: FailureAndRetryFeature.State) {
                self.isRunning = state.isRunning
                self.failures = state.metrics?.failures
                self.newWorkStarts = state.metrics?.newWorkStarts
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
        await fulfillment(of: [completed], timeout: 2.0)

        XCTAssertEqual(viewStore.failures, 1)
        XCTAssertEqual(viewStore.newWorkStarts, 1)
        XCTAssertEqual(viewStore.galleryCount, 1)
    }
}

private actor RetryTracker {
    private var shouldFailFirst = false
    private var fetchCount = 0

    func markFailure(url _: URL) {
        shouldFailFirst = true
        fetchCount = 0
    }

    func fetch(url: URL) async -> PipelineFetch {
        fetchCount += 1
        if shouldFailFirst && fetchCount == 1 {
            return PipelineFetch(
                url: url,
                source: .failed("Transient failure for \(url.lastPathComponent)"),
                image: nil,
                duration: 0.01
            )
        }

        let image = DecodedImage(url: url, imageData: Data([9, 9, 9]), byteCount: 3, checksum: 27)
        return PipelineFetch(
            url: url,
            source: .newWork,
            image: image,
            duration: 0.01
        )
    }

    func metrics() -> PipelineMetrics {
        PipelineMetrics(
            totalFetches: 2,
            newWorkStarts: 1,
            sharedInFlightHits: 0,
            cacheHits: 0,
            failures: 1,
            maxConcurrentRequests: 1,
            currentInFlightCount: 0
        )
    }

    func reset() {
        shouldFailFirst = false
        fetchCount = 0
    }
}
