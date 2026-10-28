import Combine
import ComposableArchitecture
import Foundation
import XCTest
@testable import TCAAsyncImagePipeline

@MainActor
final class BoundedPrefetchFeatureTests: XCTestCase {
    func testBoundedPrefetchReportsBoundedConcurrencyMetrics() async {
        let tracker = BoundedTracker()

        let store = Store(initialState: BoundedPrefetchFeature.State()) {
            BoundedPrefetchFeature()
        } withDependencies: {
            $0.imagePipelineClient = ImagePipelineClient(
                fetch: { _, _ in
                    fatalError("fetch is not used in bounded prefetch test")
                },
                fetchBatch: { _, urls, _ in
                    await tracker.fetchBatch(urls: urls)
                },
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
            var maxConcurrentRequests: Int?
            var galleryCount: Int

            init(state: BoundedPrefetchFeature.State) {
                self.isRunning = state.isRunning
                self.maxConcurrentRequests = state.metrics?.maxConcurrentRequests
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

        XCTAssertEqual(viewStore.maxConcurrentRequests, 2)
        XCTAssertEqual(viewStore.galleryCount, 4)
    }
}

private actor BoundedTracker {
    func fetchBatch(urls: [URL]) -> [PipelineFetch] {
        urls.map { url in
            let image = DecodedImage(url: url, imageData: Data([4, 5, 6]), byteCount: 3, checksum: 15)
            return PipelineFetch(
                url: url,
                source: .newWork,
                image: image,
                duration: 0.01
            )
        }
    }

    func metrics() -> PipelineMetrics {
        PipelineMetrics(
            totalFetches: 4,
            newWorkStarts: 4,
            sharedInFlightHits: 0,
            cacheHits: 0,
            failures: 0,
            maxConcurrentRequests: 2,
            currentInFlightCount: 0
        )
    }

    func reset() {}
}
