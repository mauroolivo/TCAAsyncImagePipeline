import Foundation

enum AppDiagnostics {
    // Enable by setting PIPELINE_VERBOSE_LOGS=1 in the run scheme environment.
    nonisolated static let isVerboseConsoleLoggingEnabled = ProcessInfo.processInfo.environment["PIPELINE_VERBOSE_LOGS"] == "1"

    nonisolated static func log(_ message: @autoclosure () -> String) {
        guard isVerboseConsoleLoggingEnabled else { return }
        print(message())
    }
}
