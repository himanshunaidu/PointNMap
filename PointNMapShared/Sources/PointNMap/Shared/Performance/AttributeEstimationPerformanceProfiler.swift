import Foundation
import os

public enum AttributeEstimationPerformanceStage: String, Codable, Sendable {
    case annotationClassChange = "annotation.class_change"
    case annotationFeatureUpdate = "annotation.feature_update"
    case featureEstimation = "feature.estimation"
    case locationEstimation = "feature.location"
    case existingFeatureLookup = "feature.existing_lookup"
    case attributeRequest = "attribute.request"
    case attributeEstimation = "attribute.estimation"
    case cacheLookup = "cache.lookup"
    case damageDetection = "surface.damage_detection"
    case surfaceWindowAnalysis = "surface.window_analysis"
    case surfaceDamageProjection = "surface.detail.damage_projection"
    case surfaceMeshFeatureExtraction = "surface.detail.mesh_feature_extraction"
    case surfaceGridConstructionOptimized = "surface.detail.grid_construction.optimized"
    case surfaceGridConstructionReference = "surface.detail.grid_construction.reference"
    case surfaceGridComparison = "surface.detail.grid_comparison"
    case surfaceGridSummary = "surface.detail.grid_summary"
    case surfaceGridProjection = "surface.detail.grid_projection"
    case surfaceDamageOverlap = "surface.detail.damage_overlap"
    case surfaceWindowFeatures = "surface.detail.window_features"

    public var isFineGrained: Bool {
        rawValue.hasPrefix("surface.detail.")
    }

    fileprivate var isGridComparison: Bool {
        self == .surfaceGridComparison || self == .surfaceGridSummary
    }

    var signpostName: StaticString {
        switch self {
        case .annotationClassChange: "AnnotationClassChange"
        case .annotationFeatureUpdate: "AnnotationFeatureUpdate"
        case .featureEstimation: "FeatureEstimation"
        case .locationEstimation: "LocationEstimation"
        case .existingFeatureLookup: "ExistingFeatureLookup"
        case .attributeRequest: "AttributeRequest"
        case .attributeEstimation: "AttributeEstimation"
        case .cacheLookup: "CacheLookup"
        case .damageDetection: "DamageDetection"
        case .surfaceWindowAnalysis: "SurfaceWindowAnalysis"
        case .surfaceDamageProjection: "SurfaceDamageProjection"
        case .surfaceMeshFeatureExtraction: "SurfaceMeshFeatureExtraction"
        case .surfaceGridConstructionOptimized: "SurfaceGridConstructionOptimized"
        case .surfaceGridConstructionReference: "SurfaceGridConstructionReference"
        case .surfaceGridComparison: "SurfaceGridComparison"
        case .surfaceGridSummary: "SurfaceGridSummary"
        case .surfaceGridProjection: "SurfaceGridProjection"
        case .surfaceDamageOverlap: "SurfaceDamageOverlap"
        case .surfaceWindowFeatures: "SurfaceWindowFeatures"
        }
    }
}

public struct SurfaceGridComparisonMetrics: Equatable, Sendable {
    public let optimizedDurationMilliseconds: Double
    public let referenceDurationMilliseconds: Double
    public let gridIndexMismatchCount: Int
    public let boundsMismatchCount: Int
    public let predictionBoundsMismatchCount: Int
    public let membershipMismatchCount: Int
    public let csrMismatchCount: Int

    public init(
        optimizedDurationMilliseconds: Double,
        referenceDurationMilliseconds: Double,
        gridIndexMismatchCount: Int,
        boundsMismatchCount: Int,
        predictionBoundsMismatchCount: Int,
        membershipMismatchCount: Int,
        csrMismatchCount: Int
    ) {
        self.optimizedDurationMilliseconds = optimizedDurationMilliseconds
        self.referenceDurationMilliseconds = referenceDurationMilliseconds
        self.gridIndexMismatchCount = gridIndexMismatchCount
        self.boundsMismatchCount = boundsMismatchCount
        self.predictionBoundsMismatchCount = predictionBoundsMismatchCount
        self.membershipMismatchCount = membershipMismatchCount
        self.csrMismatchCount = csrMismatchCount
    }

    public var absoluteTimeSavedMilliseconds: Double {
        referenceDurationMilliseconds - optimizedDurationMilliseconds
    }

    public var speedup: Double {
        guard optimizedDurationMilliseconds > 0 else { return 0 }
        return referenceDurationMilliseconds / optimizedDurationMilliseconds
    }

    public var durationReductionPercent: Double {
        guard referenceDurationMilliseconds > 0 else { return 0 }
        return absoluteTimeSavedMilliseconds / referenceDurationMilliseconds * 100
    }

    public var totalMismatchCount: Int {
        gridIndexMismatchCount + boundsMismatchCount + predictionBoundsMismatchCount
            + membershipMismatchCount + csrMismatchCount
    }

    public var hasExactParity: Bool {
        totalMismatchCount == 0
    }
}

public struct SurfaceGridDistributionSummary: Equatable, Sendable {
    public let mean: Double
    public let minimum: Double
    public let maximum: Double
    public let standardDeviation: Double
    public let median: Double
    public let p95: Double
}

public struct SurfaceGridComparisonSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let parityPassCount: Int
    public let parityFailureCount: Int
    public let optimized: SurfaceGridDistributionSummary
    public let reference: SurfaceGridDistributionSummary
    public let speedup: SurfaceGridDistributionSummary
}

public struct SurfaceGridComparisonAccumulator: Sendable {
    private var samples: [SurfaceGridComparisonMetrics] = []

    public init() {}

    public mutating func append(_ metrics: SurfaceGridComparisonMetrics) {
        samples.append(metrics)
    }

    public var summary: SurfaceGridComparisonSummary {
        SurfaceGridComparisonSummary(
            sampleCount: samples.count,
            parityPassCount: samples.filter(\.hasExactParity).count,
            parityFailureCount: samples.filter { !$0.hasExactParity }.count,
            optimized: Self.distribution(samples.map(\.optimizedDurationMilliseconds)),
            reference: Self.distribution(samples.map(\.referenceDurationMilliseconds)),
            speedup: Self.distribution(samples.map(\.speedup))
        )
    }

    private static func distribution(_ values: [Double]) -> SurfaceGridDistributionSummary {
        guard !values.isEmpty else {
            return SurfaceGridDistributionSummary(
                mean: 0,
                minimum: 0,
                maximum: 0,
                standardDeviation: 0,
                median: 0,
                p95: 0
            )
        }
        let sorted = values.sorted()
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { partial, value in
            partial + pow(value - mean, 2)
        } / Double(values.count)
        return SurfaceGridDistributionSummary(
            mean: mean,
            minimum: sorted[0],
            maximum: sorted[sorted.count - 1],
            standardDeviation: sqrt(variance),
            median: percentile(sorted, fraction: 0.5),
            p95: percentile(sorted, fraction: 0.95)
        )
    }

    private static func percentile(_ sorted: [Double], fraction: Double) -> Double {
        guard sorted.count > 1 else { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        let interpolation = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * interpolation
    }
}

public struct AttributeEstimationPerformanceEvent: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let sessionID: UUID
    public let stage: AttributeEstimationPerformanceStage
    public let durationMilliseconds: Double
    public let success: Bool
    public let isMainThread: Bool
    public let metadata: [String: String]
    public let errorDescription: String?

    public init(
        timestamp: Date,
        sessionID: UUID,
        stage: AttributeEstimationPerformanceStage,
        durationMilliseconds: Double,
        success: Bool,
        isMainThread: Bool,
        metadata: [String: String],
        errorDescription: String?
    ) {
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.stage = stage
        self.durationMilliseconds = durationMilliseconds
        self.success = success
        self.isMainThread = isMainThread
        self.metadata = metadata
        self.errorDescription = errorDescription
    }

    public func jsonLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return string + "\n"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        guard let timestamp = ISO8601DateFormatter().date(from: timestampString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp."
            )
        }
        self.timestamp = timestamp
        self.sessionID = try container.decode(UUID.self, forKey: .sessionID)
        self.stage = try container.decode(AttributeEstimationPerformanceStage.self, forKey: .stage)
        self.durationMilliseconds = try container.decode(Double.self, forKey: .durationMilliseconds)
        self.success = try container.decode(Bool.self, forKey: .success)
        self.isMainThread = try container.decode(Bool.self, forKey: .isMainThread)
        self.metadata = try container.decode([String: String].self, forKey: .metadata)
        self.errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
    }
}

public final class AttributeEstimationPerformanceProfiler: @unchecked Sendable {
    public static let shared = AttributeEstimationPerformanceProfiler()

    @TaskLocal public static var currentSessionID: UUID?

    private let logger: Logger
    private let signposter: OSSignposter
    private let isEnabled: Bool
    private let persistEvents: Bool
    private let eventObserver: ((AttributeEstimationPerformanceEvent) -> Void)?
    private let gridComparisonLock = NSLock()
    private var gridComparisonAccumulator = SurfaceGridComparisonAccumulator()

    public var enabled: Bool {
        isEnabled
    }

    public init(
        isEnabled: Bool? = nil,
        persistEvents: Bool = true,
        eventObserver: ((AttributeEstimationPerformanceEvent) -> Void)? = nil
    ) {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "PointNMapShared",
            category: "AttributeEstimationPerformance"
        )
        self.logger = logger
        self.signposter = OSSignposter(logger: logger)
        self.isEnabled = isEnabled ?? _isDebugAssertConfiguration()
        self.persistEvents = persistEvents
        self.eventObserver = eventObserver
    }

    public func withSession<T>(_ sessionID: UUID, operation: () throws -> T) rethrows -> T {
        try Self.$currentSessionID.withValue(sessionID, operation: operation)
    }

    public func measure<T>(
        _ stage: AttributeEstimationPerformanceStage,
        metadata: [String: String] = [:],
        operation: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try operation() }
        let eventMetadata = decoratedMetadata(for: stage, metadata: metadata)
        let sessionID = Self.currentSessionID ?? UUID()
        let signpostID = signposter.makeSignpostID()
        let signpostState = signposter.beginInterval(
            stage.signpostName,
            id: signpostID,
            "session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public)"
        )
        let start = ContinuousClock.now
        do {
            let value = try operation()
            let duration = start.duration(to: .now)
            signposter.endInterval(stage.signpostName, signpostState)
            record(sessionID: sessionID, stage: stage, duration: duration, success: true, metadata: eventMetadata, errorDescription: nil)
            return value
        } catch {
            let duration = start.duration(to: .now)
            signposter.endInterval(stage.signpostName, signpostState)
            record(sessionID: sessionID, stage: stage, duration: duration, success: false, metadata: eventMetadata, errorDescription: error.localizedDescription)
            throw error
        }
    }

    public func recordEvent(
        _ stage: AttributeEstimationPerformanceStage,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        record(
            sessionID: Self.currentSessionID ?? UUID(),
            stage: stage,
            duration: .zero,
            success: true,
            metadata: decoratedMetadata(for: stage, metadata: metadata),
            errorDescription: nil
        )
    }

    public func recordGridComparison(
        _ metrics: SurfaceGridComparisonMetrics,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        var comparisonMetadata = metadata
        comparisonMetadata.merge([
            "optimized_duration_ms": Self.string(metrics.optimizedDurationMilliseconds),
            "reference_duration_ms": Self.string(metrics.referenceDurationMilliseconds),
            "time_saved_ms": Self.string(metrics.absoluteTimeSavedMilliseconds),
            "speedup": Self.string(metrics.speedup),
            "duration_reduction_percent": Self.string(metrics.durationReductionPercent),
            "exact_parity": String(metrics.hasExactParity),
            "total_mismatch_count": String(metrics.totalMismatchCount),
            "grid_index_mismatch_count": String(metrics.gridIndexMismatchCount),
            "bounds_mismatch_count": String(metrics.boundsMismatchCount),
            "prediction_bounds_mismatch_count": String(metrics.predictionBoundsMismatchCount),
            "membership_mismatch_count": String(metrics.membershipMismatchCount),
            "csr_mismatch_count": String(metrics.csrMismatchCount)
        ]) { _, new in new }
        recordEvent(.surfaceGridComparison, metadata: comparisonMetadata)

        gridComparisonLock.lock()
        gridComparisonAccumulator.append(metrics)
        let summary = gridComparisonAccumulator.summary
        gridComparisonLock.unlock()
        recordEvent(.surfaceGridSummary, metadata: Self.metadata(for: summary))
    }

    private func decoratedMetadata(
        for stage: AttributeEstimationPerformanceStage,
        metadata: [String: String]
    ) -> [String: String] {
        guard stage.isFineGrained else { return metadata }
        return metadata.merging(["granularity": "fine"]) { current, _ in current }
    }

    private func record(
        sessionID: UUID,
        stage: AttributeEstimationPerformanceStage,
        duration: Duration,
        success: Bool,
        metadata: [String: String],
        errorDescription: String?
    ) {
        let milliseconds = Self.milliseconds(duration)
        let event = AttributeEstimationPerformanceEvent(
            timestamp: Date(),
            sessionID: sessionID,
            stage: stage,
            durationMilliseconds: milliseconds,
            success: success,
            isMainThread: Thread.isMainThread,
            metadata: metadata,
            errorDescription: errorDescription
        )
        let metadataDescription = metadata.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        if stage.isGridComparison {
            logger.info("[PERF:GRID] session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 3)) success=\(success) main=\(event.isMainThread) \(metadataDescription, privacy: .public)")
        } else if stage.isFineGrained {
            logger.info("[PERF:FINE] session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 3)) success=\(success) main=\(event.isMainThread) \(metadataDescription, privacy: .public)")
        } else {
            logger.info("[PERF] session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 3)) success=\(success) main=\(event.isMainThread) \(metadataDescription, privacy: .public)")
        }
        eventObserver?(event)
        guard persistEvents else { return }
        Task { await AttributeEstimationPerformanceLogWriter.shared.append(event) }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    private static func string(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func metadata(for summary: SurfaceGridComparisonSummary) -> [String: String] {
        [
            "sample_count": String(summary.sampleCount),
            "parity_pass_count": String(summary.parityPassCount),
            "parity_failure_count": String(summary.parityFailureCount),
            "optimized_mean_ms": string(summary.optimized.mean),
            "optimized_min_ms": string(summary.optimized.minimum),
            "optimized_max_ms": string(summary.optimized.maximum),
            "optimized_stddev_ms": string(summary.optimized.standardDeviation),
            "optimized_median_ms": string(summary.optimized.median),
            "optimized_p95_ms": string(summary.optimized.p95),
            "reference_mean_ms": string(summary.reference.mean),
            "reference_min_ms": string(summary.reference.minimum),
            "reference_max_ms": string(summary.reference.maximum),
            "reference_stddev_ms": string(summary.reference.standardDeviation),
            "reference_median_ms": string(summary.reference.median),
            "reference_p95_ms": string(summary.reference.p95),
            "speedup_mean": string(summary.speedup.mean),
            "speedup_median": string(summary.speedup.median),
            "speedup_p95": string(summary.speedup.p95)
        ]
    }
}

private actor AttributeEstimationPerformanceLogWriter {
    static let shared = AttributeEstimationPerformanceLogWriter()
    private var fileURLs: [UUID: URL] = [:]
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PointNMapShared",
        category: "AttributeEstimationPerformance"
    )

    func append(_ event: AttributeEstimationPerformanceEvent) {
        do {
            let fileURL = try fileURL(for: event.sessionID)
            let data = Data(try event.jsonLine().utf8)
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            logger.error("Failed to persist performance event: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(for sessionID: UUID) throws -> URL {
        if let fileURL = fileURLs[sessionID] { return fileURL }
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directoryURL = documentsURL.appendingPathComponent("PerformanceLogs", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("attribute-estimation-\(sessionID.uuidString).jsonl")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            logger.notice("Performance log: \(fileURL.path, privacy: .public)")
        }
        fileURLs[sessionID] = fileURL
        return fileURL
    }
}
