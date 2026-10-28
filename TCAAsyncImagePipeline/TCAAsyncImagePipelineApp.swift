//

import SwiftUI
import ComposableArchitecture

@main
struct TCAAsyncImagePipelineApp: App {
    private let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
                .task {
                    await Phase0BaselineRunner.runIfEnabled()
                }
        }
    }
}
