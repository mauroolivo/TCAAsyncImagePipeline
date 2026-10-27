//

import SwiftUI

@main
struct TCAAsyncImagePipelineApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await Phase0BaselineRunner.runIfEnabled()
                }
        }
    }
}
