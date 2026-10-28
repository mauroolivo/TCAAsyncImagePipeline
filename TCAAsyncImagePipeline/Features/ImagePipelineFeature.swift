import ComposableArchitecture
import Foundation

@Reducer
struct ImagePipelineFeature {
    @ObservableState
    struct State {
        var duplicate: DuplicateRequestsFeature.State
        var bounded: BoundedPrefetchFeature.State
        var retry: FailureAndRetryFeature.State
        var cancellation: CancellationFeature.State

        init() {
            duplicate = DuplicateRequestsFeature.State()
            bounded = BoundedPrefetchFeature.State()
            retry = FailureAndRetryFeature.State()
            cancellation = CancellationFeature.State()
        }
    }

    @CasePathable
    enum Action {
        case duplicate(DuplicateRequestsFeature.Action)
        case bounded(BoundedPrefetchFeature.Action)
        case retry(FailureAndRetryFeature.Action)
        case cancellation(CancellationFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.duplicate, action: \.duplicate) {
            DuplicateRequestsFeature()
        }
        Scope(state: \.bounded, action: \.bounded) {
            BoundedPrefetchFeature()
        }
        Scope(state: \.retry, action: \.retry) {
            FailureAndRetryFeature()
        }
        Scope(state: \.cancellation, action: \.cancellation) {
            CancellationFeature()
        }
    }
}

extension ImagePipelineFeature {
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

