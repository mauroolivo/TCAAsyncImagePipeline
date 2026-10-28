# TCAAsyncImagePipeline

A SwiftUI companion app that migrates [`AsyncImagePipeline`](https://github.com/mauroolivo/AsyncImagePipeline) into The Composable Architecture **without rewriting the actor internals**.

This repository is the runnable companion to the article: [From Actors to Reducers: Migrating AsyncImagePipeline to TCA](https://uimatters.io/articles/tca-async-image-pipeline-migration).

Read the precursor first: [Designing a Production-Ready Async Image Pipeline](https://uimatters.io/articles/async-image-pipeline).

## What this demo shows

- TCA shell around an existing Swift concurrency pipeline
- Four scoped experiment features (duplicate, bounded prefetch, retry, cancellation)
- Pipeline I/O behind `@Dependency(\.imagePipelineClient)`
- Deterministic reducer tests with a mock client
- Hybrid production shape: actors still own cache, in-flight sharing, and network

The four experiments keep the same invariants as the precursor:

- Duplicate request deduplication (shared in-flight work)
- Bounded prefetch concurrency
- Failure eviction and retry
- Cancellation behavior with shared work

## Requirements

- Xcode 27+
- iOS 27 simulator/device

## Run

1. Open `TCAAsyncImagePipeline.xcodeproj` in Xcode.
2. Select the `TCAAsyncImagePipeline` scheme.
3. Run on an iPhone simulator.
4. Use the 4 tabs to run each experiment.

## Tests

```bash
xcodebuild test \
  -project TCAAsyncImagePipeline.xcodeproj \
  -scheme TCAAsyncImagePipeline \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0'
```

## Optional Phase 0 live parity autorun

Launch the app with:

```text
--phase0-autorun
```

The app writes `phase0-baseline-report.json` into its Documents container. This path hits the network (real image URLs).
