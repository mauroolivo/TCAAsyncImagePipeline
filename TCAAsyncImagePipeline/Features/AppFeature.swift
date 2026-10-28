import ComposableArchitecture

struct AppFeature: Reducer {
    @ObservableState
    struct State {
        var pipeline = ImagePipelineFeature.State()
    }

    enum Action {
        case pipeline(ImagePipelineFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.pipeline, action: /Action.pipeline) {
            ImagePipelineFeature()
        }
    }
}
