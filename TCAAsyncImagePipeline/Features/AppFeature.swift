import ComposableArchitecture

struct AppFeature: Reducer {
    @ObservableState
    struct State {
        var pipeline = ImagePipelineFeature.State()
    }

    @CasePathable
    enum Action {
        case pipeline(ImagePipelineFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.pipeline, action: \.pipeline) {
            ImagePipelineFeature()
        }
    }
}
