import SwiftUI
import ComposableArchitecture

struct ImagePipelineView: View {
    let store: StoreOf<AppFeature>
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        TabView {
            ForEach(ImagePipelineFeature.ExperimentKind.allCases, id: \.self) { kind in
                experimentTab(kind: kind)
                    .tabItem {
                        Label(kind.tabTitle, systemImage: kind.tabImage)
                    }
            }
        }
    }

    private func experimentTab(kind: ImagePipelineFeature.ExperimentKind) -> some View {
        let model = experimentState(kind)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard(title: kind.title, description: kind.description)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Controls")
                        .font(.headline)

                    Button(action: {
                        store.send(experimentAction(kind, .runTapped))
                    }) {
                        Label(kind.actionTitle, systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .ifAvailableGlassProminent()
                    .disabled(model.isRunning)

                    HStack(spacing: 12) {
                        Button(action: {
                            store.send(experimentAction(kind, .resetTapped))
                        }) {
                            Label("Reset", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)

                        if model.isRunning {
                            Button(action: {
                                store.send(experimentAction(kind, .cancelTapped))
                            }) {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let metrics = model.metrics {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Observed pipeline metrics")
                            .font(.headline)
                        metricsPanel(metrics)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Result")
                        .font(.headline)
                    galleryAndLog(model: model)
                }
            }
            .padding()
        }
        .navigationTitle("Pipeline")
        .task {
            _ = store.send(experimentAction(kind, .onAppear))
        }
    }

    private func heroCard(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Tap the experiment button to generate network activity, deduplicated work, and a live image result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(.secondarySystemBackground), Color(.systemGray6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricsPanel(_ metrics: PipelineMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metrics")
                .font(.headline)

            metricRow("Total Fetches", value: "\(metrics.totalFetches)")
            metricRow("New Work Starts", value: "\(metrics.newWorkStarts)")
            metricRow("Shared In-Flight Hits", value: "\(metrics.sharedInFlightHits)")
            metricRow("Cache Hits", value: "\(metrics.cacheHits)")
            metricRow("Max Concurrent", value: "\(metrics.maxConcurrentRequests)")
            metricRow("In-Flight Now", value: "\(metrics.currentInFlightCount)")
        }
        .font(.caption)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }

    private func galleryAndLog(model: ExperimentViewState) -> some View {
        VStack(spacing: 0) {
            if !model.gallery.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Gallery")
                            .font(.headline)
                        Spacer()
                        Text("\(model.gallery.count) image\(model.gallery.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    LazyVGrid(columns: galleryColumns, spacing: isCompact ? 8 : 12) {
                        ForEach(model.gallery) { item in
                            galleryCell(item.image)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .background(Color(.systemGray6))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Gallery")
                            .font(.headline)
                        Spacer()
                        Text("empty")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)

                    Text("Run an experiment to load images. Check the event log below for details.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()

                    Spacer()
                }
                .background(Color(.systemGray6))
                .frame(height: 120)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Event Log")
                        .font(.headline)
                    Spacer()
                    if model.isRunning {
                        ProgressView()
                            .scaleEffect(0.8, anchor: .center)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.events) { event in
                            logEventRow(event)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.gallery.count)
    }

    private var galleryColumns: [GridItem] {
        let count = isCompact ? 2 : 3
        let spacing = gallerySpacing
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }

    private var gallerySpacing: CGFloat {
        isCompact ? 8 : 10
    }

    private var galleryTileMaxSide: CGFloat {
        isCompact ? 150 : 190
    }

    @ViewBuilder
    private func galleryCell(_ image: DecodedImage) -> some View {
        let displayImage = image.displayImage
        let hasImage = displayImage != nil

        ZStack {
            if hasImage {
                displayImage!
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemGray5))
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 24, weight: .medium))
                        Text("Failed to decode")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .onAppear {
                    AppDiagnostics.log("[GalleryCell] Image \(image.filename) failed: displayImage returned nil for \(image.byteCount) bytes")
                }
            }
        }
        .frame(maxWidth: galleryTileMaxSide)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .center)
        .clipped()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        .onAppear {
            AppDiagnostics.log("[GalleryCell] Cell appeared: \(image.filename) - hasImage: \(hasImage)")
        }
    }

    private func logEventRow(_ event: LogEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            eventBadge(event.level)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.message)
                    .font(.caption)
                    .lineLimit(nil)

                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.systemGray6))
        .cornerRadius(4)
    }

    private func eventBadge(_ level: LogEvent.Level) -> some View {
        Image(systemName: iconForLevel(level))
            .font(.caption)
            .foregroundStyle(colorForLevel(level))
            .frame(width: 20)
    }

    private func iconForLevel(_ level: LogEvent.Level) -> String {
        switch level {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.circle"
        case .error:
            return "xmark.circle"
        }
    }

    private func colorForLevel(_ level: LogEvent.Level) -> Color {
        switch level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private extension ImagePipelineView {
    enum ExperimentIntent {
        case onAppear
        case runTapped
        case resetTapped
        case cancelTapped
    }

    func experimentAction(
        _ kind: ImagePipelineFeature.ExperimentKind,
        _ intent: ExperimentIntent
    ) -> AppFeature.Action {
        switch kind {
        case .duplicate:
            return .pipeline(.duplicate(mapDuplicateIntent(intent)))
        case .bounded:
            return .pipeline(.bounded(mapBoundedIntent(intent)))
        case .retry:
            return .pipeline(.retry(mapRetryIntent(intent)))
        case .cancellation:
            return .pipeline(.cancellation(mapCancellationIntent(intent)))
        }
    }

    func experimentState(_ kind: ImagePipelineFeature.ExperimentKind) -> ExperimentViewState {
        switch kind {
        case .duplicate:
            let state = store.pipeline.duplicate
            return ExperimentViewState(events: state.events, gallery: state.gallery, isRunning: state.isRunning, metrics: state.metrics)
        case .bounded:
            let state = store.pipeline.bounded
            return ExperimentViewState(events: state.events, gallery: state.gallery, isRunning: state.isRunning, metrics: state.metrics)
        case .retry:
            let state = store.pipeline.retry
            return ExperimentViewState(events: state.events, gallery: state.gallery, isRunning: state.isRunning, metrics: state.metrics)
        case .cancellation:
            let state = store.pipeline.cancellation
            return ExperimentViewState(events: state.events, gallery: state.gallery, isRunning: state.isRunning, metrics: state.metrics)
        }
    }

    func mapDuplicateIntent(_ intent: ExperimentIntent) -> DuplicateRequestsFeature.Action {
        switch intent {
        case .onAppear: return .onAppear
        case .runTapped: return .runTapped
        case .resetTapped: return .resetTapped
        case .cancelTapped: return .cancelTapped
        }
    }

    func mapBoundedIntent(_ intent: ExperimentIntent) -> BoundedPrefetchFeature.Action {
        switch intent {
        case .onAppear: return .onAppear
        case .runTapped: return .runTapped
        case .resetTapped: return .resetTapped
        case .cancelTapped: return .cancelTapped
        }
    }

    func mapRetryIntent(_ intent: ExperimentIntent) -> FailureAndRetryFeature.Action {
        switch intent {
        case .onAppear: return .onAppear
        case .runTapped: return .runTapped
        case .resetTapped: return .resetTapped
        case .cancelTapped: return .cancelTapped
        }
    }

    func mapCancellationIntent(_ intent: ExperimentIntent) -> CancellationFeature.Action {
        switch intent {
        case .onAppear: return .onAppear
        case .runTapped: return .runTapped
        case .resetTapped: return .resetTapped
        case .cancelTapped: return .cancelTapped
        }
    }
}

private struct ExperimentViewState {
    let events: [LogEvent]
    let gallery: [GalleryItem]
    let isRunning: Bool
    let metrics: PipelineMetrics?
}

private extension View {
    @ViewBuilder
    func ifAvailableGlassProminent() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ImagePipelineView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        }
    )
}
