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
    case surfaceGridConstruction = "surface.detail.grid_construction"
    case surfaceGridProjection = "surface.detail.grid_projection"
    case surfaceDamageOverlap = "surface.detail.damage_overlap"
    case surfaceWindowFeatures = "surface.detail.window_features"

    public var isFineGrained: Bool {
        rawValue.hasPrefix("surface.detail.")
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
        case .surfaceGridConstruction: "SurfaceGridConstruction"
        case .surfaceGridProjection: "SurfaceGridProjection"
        case .surfaceDamageOverlap: "SurfaceDamageOverlap"
        case .surfaceWindowFeatures: "SurfaceWindowFeatures"
        }
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
        guard isEnabled else {
            return try operation()
        }
        let eventMetadata = stage.isFineGrained
            ? metadata.merging(["granularity": "fine"]) { current, _ in current }
            : metadata
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
            record(
                sessionID: sessionID,
                stage: stage,
                duration: duration,
                success: true,
                metadata: eventMetadata,
                errorDescription: nil
            )
            return value
        } catch {
            let duration = start.duration(to: .now)
            signposter.endInterval(stage.signpostName, signpostState)
            record(
                sessionID: sessionID,
                stage: stage,
                duration: duration,
                success: false,
                metadata: eventMetadata,
                errorDescription: error.localizedDescription
            )
            throw error
        }
    }

    public func recordEvent(
        _ stage: AttributeEstimationPerformanceStage,
        metadata: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        let eventMetadata = stage.isFineGrained
            ? metadata.merging(["granularity": "fine"]) { current, _ in current }
            : metadata
        record(
            sessionID: Self.currentSessionID ?? UUID(),
            stage: stage,
            duration: .zero,
            success: true,
            metadata: eventMetadata,
            errorDescription: nil
        )
    }

    private func record(
        sessionID: UUID,
        stage: AttributeEstimationPerformanceStage,
        duration: Duration,
        success: Bool,
        metadata: [String: String],
        errorDescription: String?
    ) {
        let components = duration.components
        let milliseconds = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
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
        let metadataDescription = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if stage.isFineGrained {
            logger.info(
                "[PERF:FINE] session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 3)) success=\(success) main=\(event.isMainThread) \(metadataDescription, privacy: .public)"
            )
        } else {
            logger.info(
                "[PERF] session=\(sessionID.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public) duration_ms=\(milliseconds, format: .fixed(precision: 3)) success=\(success) main=\(event.isMainThread) \(metadataDescription, privacy: .public)"
            )
        }
        eventObserver?(event)
        guard persistEvents else { return }
        Task {
            await AttributeEstimationPerformanceLogWriter.shared.append(event)
        }
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
        if let fileURL = fileURLs[sessionID] {
            return fileURL
        }
        guard let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directoryURL = documentsURL.appendingPathComponent(
            "PerformanceLogs",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let fileURL = directoryURL.appendingPathComponent(
            "attribute-estimation-\(sessionID.uuidString).jsonl"
        )
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            logger.notice("Performance log: \(fileURL.path, privacy: .public)")
        }
        fileURLs[sessionID] = fileURL
        return fileURL
    }
}
