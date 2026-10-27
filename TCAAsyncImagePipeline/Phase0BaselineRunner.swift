import Foundation

/// Runs Phase 0 baseline experiments when `PHASE0_AUTORUN=1` is set in the process environment.
/// Results are written to app container files for reproducible parity evidence capture.
enum Phase0BaselineRunner {
    private static let autorunEnvironmentKey = "PHASE0_AUTORUN"
    private static let autorunLaunchArgument = "--phase0-autorun"
    private static let outputFileName = "phase0-baseline-report.json"
    private static let startupMarkerFileName = "phase0-baseline-started.txt"
    private static var hasRun = false

    static func runIfEnabled() async {
        let environmentEnabled = ProcessInfo.processInfo.environment[autorunEnvironmentKey] == "1"
        let argumentEnabled = ProcessInfo.processInfo.arguments.contains(autorunLaunchArgument)
        guard environmentEnabled || argumentEnabled else { return }
        guard !hasRun else { return }
        hasRun = true

        writeStartupMarker()
        let report = await runAllExperiments()
        await writeReport(report)
    }

    private static func runAllExperiments() async -> BaselineReport {
        let pipeline = AsyncImagePipeline()

        let duplicate = await runDuplicateExperiment(pipeline: pipeline)
        let boundedPrefetch = await runBoundedPrefetchExperiment(pipeline: pipeline)
        let failureRetry = await runFailureRetryExperiment(pipeline: pipeline)
        let cancellation = await runCancellationExperiment(pipeline: pipeline)

        return BaselineReport(
            generatedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            environment: EnvironmentSnapshot(
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                isVerboseLoggingEnabled: AppDiagnostics.isVerboseConsoleLoggingEnabled
            ),
            duplicateRequests: duplicate,
            boundedPrefetch: boundedPrefetch,
            failureAndRetry: failureRetry,
            cancellation: cancellation
        )
    }

    private static func runDuplicateExperiment(pipeline: AsyncImagePipeline) async -> ExperimentResult {
        await pipeline.reset()

        let urls: [URL] = [
            NetworkLoader.imageURLs[0],
            NetworkLoader.imageURLs[1],
            NetworkLoader.imageURLs[0],
        ]

        var fetches: [IndexedFetch] = []
        await withTaskGroup(of: IndexedFetch.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let fetch = await pipeline.fetch(url: url)
                    return IndexedFetch(index: index, fetch: fetch)
                }
            }
            for await indexed in group {
                fetches.append(indexed)
            }
        }

        fetches.sort { $0.index < $1.index }
        let metrics = await pipeline.getMetrics()

        let successCount = fetches.filter { $0.fetch.image != nil }.count
        let newWorkCount = fetches.filter {
            if case .newWork = $0.fetch.source { return true }
            return false
        }.count
        let sharedCount = fetches.filter {
            if case .sharedInFlight = $0.fetch.source { return true }
            return false
        }.count

        let passed = successCount == 3 && newWorkCount == 2 && sharedCount == 1 && metrics.newWorkStarts == 2 && metrics.sharedInFlightHits >= 1

        return ExperimentResult(
            name: "duplicate_requests",
            passed: passed,
            summary: "3 concurrent fetches with one duplicate URL",
            checks: [
                CheckResult(name: "all_three_fetches_succeeded", passed: successCount == 3, detail: "successCount=\(successCount)"),
                CheckResult(name: "two_new_work_results", passed: newWorkCount == 2, detail: "newWorkCount=\(newWorkCount)"),
                CheckResult(name: "one_shared_in_flight_result", passed: sharedCount == 1, detail: "sharedCount=\(sharedCount)"),
                CheckResult(name: "metrics_new_work_starts_is_two", passed: metrics.newWorkStarts == 2, detail: "metrics.newWorkStarts=\(metrics.newWorkStarts)"),
                CheckResult(name: "metrics_shared_hits_present", passed: metrics.sharedInFlightHits >= 1, detail: "metrics.sharedInFlightHits=\(metrics.sharedInFlightHits)")
            ],
            metrics: metrics,
            sources: fetches.map { sourceDescription($0.fetch.source) }
        )
    }

    private static func runBoundedPrefetchExperiment(pipeline: AsyncImagePipeline) async -> ExperimentResult {
        await pipeline.reset()

        let urls = Array(NetworkLoader.imageURLs.prefix(4))
        let fetches = await pipeline.fetchBatch(urls: urls, maxConcurrent: 2)
        let metrics = await pipeline.getMetrics()

        let successCount = fetches.filter { $0.image != nil }.count
        let passed = successCount == urls.count && metrics.maxConcurrentRequests <= 2

        return ExperimentResult(
            name: "bounded_prefetch",
            passed: passed,
            summary: "4 fetches with maxConcurrent=2",
            checks: [
                CheckResult(name: "all_prefetch_fetches_succeeded", passed: successCount == urls.count, detail: "successCount=\(successCount)"),
                CheckResult(name: "max_concurrency_not_exceeded", passed: metrics.maxConcurrentRequests <= 2, detail: "metrics.maxConcurrentRequests=\(metrics.maxConcurrentRequests)")
            ],
            metrics: metrics,
            sources: fetches.map { sourceDescription($0.source) }
        )
    }

    private static func runFailureRetryExperiment(pipeline: AsyncImagePipeline) async -> ExperimentResult {
        await pipeline.reset()

        let url = NetworkLoader.imageURLs[2]
        await pipeline.simulateFailure(for: url)

        let first = await pipeline.fetch(url: url)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let second = await pipeline.fetch(url: url)
        let metrics = await pipeline.getMetrics()

        let firstFailed: Bool = {
            if case .failed = first.source { return true }
            return false
        }()

        let secondSucceeded = second.image != nil
        let secondIsFreshWork: Bool = {
            if case .newWork = second.source { return true }
            return false
        }()

        let passed = firstFailed && secondSucceeded && secondIsFreshWork

        return ExperimentResult(
            name: "failure_and_retry",
            passed: passed,
            summary: "forced transient failure followed by retry",
            checks: [
                CheckResult(name: "first_attempt_failed", passed: firstFailed, detail: "firstSource=\(sourceDescription(first.source))"),
                CheckResult(name: "second_attempt_succeeded", passed: secondSucceeded, detail: "secondSource=\(sourceDescription(second.source))"),
                CheckResult(name: "second_attempt_is_fresh_work", passed: secondIsFreshWork, detail: "secondSource=\(sourceDescription(second.source))")
            ],
            metrics: metrics,
            sources: [sourceDescription(first.source), sourceDescription(second.source)]
        )
    }

    private static func runCancellationExperiment(pipeline: AsyncImagePipeline) async -> ExperimentResult {
        await pipeline.reset()

        let url = NetworkLoader.imageURLs[3]

        let taskA = Task { await pipeline.fetch(url: url) }
        try? await Task.sleep(nanoseconds: 100_000_000)

        let taskB = Task { await pipeline.fetch(url: url) }
        try? await Task.sleep(nanoseconds: 150_000_000)

        taskA.cancel()
        let resultB = await taskB.value
        let metrics = await pipeline.getMetrics()

        let bSucceeded = resultB.image != nil
        let bShared: Bool = {
            if case .sharedInFlight = resultB.source { return true }
            return false
        }()

        let passed = bSucceeded && bShared && metrics.sharedInFlightHits >= 1

        return ExperimentResult(
            name: "cancellation",
            passed: passed,
            summary: "cancel one waiter while another waits on shared in-flight task",
            checks: [
                CheckResult(name: "caller_b_succeeds", passed: bSucceeded, detail: "resultB=\(sourceDescription(resultB.source))"),
                CheckResult(name: "caller_b_received_shared_source", passed: bShared, detail: "resultB=\(sourceDescription(resultB.source))"),
                CheckResult(name: "shared_hit_recorded", passed: metrics.sharedInFlightHits >= 1, detail: "metrics.sharedInFlightHits=\(metrics.sharedInFlightHits)")
            ],
            metrics: metrics,
            sources: [sourceDescription(resultB.source)]
        )
    }

    private static func writeReport(_ report: BaselineReport) async {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(report)

            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(outputFileName)
            try data.write(to: tmpURL, options: .atomic)

            if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let docsReportURL = docsURL.appendingPathComponent(outputFileName)
                try data.write(to: docsReportURL, options: .atomic)
                print("PHASE0_REPORT_PATH=\(docsReportURL.path)")
            }

            print("PHASE0_REPORT_TMP_PATH=\(tmpURL.path)")
            print("PHASE0_REPORT_STATUS=completed")
        } catch {
            print("PHASE0_REPORT_STATUS=failed")
            print("PHASE0_REPORT_ERROR=\(error.localizedDescription)")
        }
    }

    private static func writeStartupMarker() {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let markerURL = docsURL.appendingPathComponent(startupMarkerFileName)
        let content = "started=\(ISO8601DateFormatter().string(from: Date()))\nargs=\(ProcessInfo.processInfo.arguments.joined(separator: " "))\n"
        try? content.data(using: .utf8)?.write(to: markerURL, options: .atomic)
    }

    private static func sourceDescription(_ source: FetchSource) -> String {
        switch source {
        case .cacheHit:
            return "cacheHit"
        case .newWork:
            return "newWork"
        case .sharedInFlight:
            return "sharedInFlight"
        case .failed(let reason):
            return "failed(\(reason))"
        }
    }
}

private struct IndexedFetch {
    let index: Int
    let fetch: PipelineFetch
}

private struct BaselineReport: Codable {
    let generatedAtISO8601: String
    let environment: EnvironmentSnapshot
    let duplicateRequests: ExperimentResult
    let boundedPrefetch: ExperimentResult
    let failureAndRetry: ExperimentResult
    let cancellation: ExperimentResult
}

private struct EnvironmentSnapshot: Codable {
    let osVersion: String
    let isVerboseLoggingEnabled: Bool
}

private struct ExperimentResult: Codable {
    let name: String
    let passed: Bool
    let summary: String
    let checks: [CheckResult]
    let metrics: PipelineMetricsSnapshot
    let sources: [String]

    init(name: String, passed: Bool, summary: String, checks: [CheckResult], metrics: PipelineMetrics, sources: [String]) {
        self.name = name
        self.passed = passed
        self.summary = summary
        self.checks = checks
        self.metrics = PipelineMetricsSnapshot(metrics)
        self.sources = sources
    }
}

private struct CheckResult: Codable {
    let name: String
    let passed: Bool
    let detail: String
}

private struct PipelineMetricsSnapshot: Codable {
    let totalFetches: Int
    let newWorkStarts: Int
    let sharedInFlightHits: Int
    let cacheHits: Int
    let failures: Int
    let maxConcurrentRequests: Int
    let currentInFlightCount: Int

    init(_ metrics: PipelineMetrics) {
        totalFetches = metrics.totalFetches
        newWorkStarts = metrics.newWorkStarts
        sharedInFlightHits = metrics.sharedInFlightHits
        cacheHits = metrics.cacheHits
        failures = metrics.failures
        maxConcurrentRequests = metrics.maxConcurrentRequests
        currentInFlightCount = metrics.currentInFlightCount
    }
}
