import ComposableArchitecture

struct ImagePipelineClient: Sendable {
    var makePipeline: @Sendable () -> AsyncImagePipeline
}

extension DependencyValues {
    var imagePipelineClient: ImagePipelineClient {
        get { self[ImagePipelineClientKey.self] }
        set { self[ImagePipelineClientKey.self] = newValue }
    }
}

private enum ImagePipelineClientKey: DependencyKey {
    static let liveValue = ImagePipelineClient(
        makePipeline: {
            AsyncImagePipeline()
        }
    )
}
