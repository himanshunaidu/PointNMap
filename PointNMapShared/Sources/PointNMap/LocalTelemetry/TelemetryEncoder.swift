//
//  TelemetryEncoder.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//

import Foundation
import ARKit
import CryptoKit
import CoreLocation

enum TelemetryEncoderError: Error, LocalizedError {
    case documentsDirectoryUnavailable
    case directoryCreationFailed(URL, Error)
    case fileCreationFailed(URL)
    
    
    var errorDescription: String? {
        switch self {
        case .documentsDirectoryUnavailable:
            return "The app Documents directory is unavailable."
        case let .directoryCreationFailed(url, error):
            return "Could not create directory at \(url.path): \(error.localizedDescription)"
        case let .fileCreationFailed(url):
            return "Could not create telemetry file at \(url.path)."
        }
    }
}

public struct TelemetryRecord: Codable, Sendable {
    public let sequenceNumber: UInt64
    public let timestamp: Date
    public let systemUptimeSeconds: TimeInterval

    public let metric: TelemetryMetric
    public let launchID: UUID
    public let mappingSessionID: UUID?

    public let numericValue: Double?
    public let textValue: String?
    public let metadata: [String: String]

    public init(
        sequenceNumber: UInt64,
        timestamp: Date = Date(),
        systemUptimeSeconds: TimeInterval = ProcessInfo.processInfo.systemUptime,
        metric: TelemetryMetric,
        launchID: UUID,
        mappingSessionID: UUID?,
        numericValue: Double? = nil,
        textValue: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.systemUptimeSeconds = systemUptimeSeconds
        self.metric = metric
        self.launchID = launchID
        self.mappingSessionID = mappingSessionID
        self.numericValue = numericValue
        self.textValue = textValue
        self.metadata = metadata
    }
}

public actor TelemetryEncoder {
    public nonisolated let launchID: UUID

    private let fileManager: FileManager
    private let telemetryDirectory: URL?
    private let backupRootDirectory: URL?
    private let synchronizeEveryNRecords: Int

    private var metricEncoders: [TelemetryMetric: MetricJSONLEncoder] = [:]
    private var failedMetrics: Set<TelemetryMetric> = []

    private var nextSequenceNumber: UInt64 = 0
    private var currentMappingSessionID: UUID?
    private var isShutDown = false

    /// Creates Documents/telemetry and Documents/telemetry/backup.
    /// Setup failures disable only the unavailable telemetry functionality;
    /// they do not throw or terminate the app.
    public init(
        enabledMetrics: Set<TelemetryMetric> = Set(TelemetryMetric.allCases),
        directoryName: String = "telemetry",
        synchronizeEveryNRecords: Int = 20,
        fileManager: FileManager = .default
    ) {
        self.launchID = UUID()
        self.fileManager = fileManager
        self.synchronizeEveryNRecords = max(1, synchronizeEveryNRecords)

        guard let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            self.telemetryDirectory = nil
            self.backupRootDirectory = nil
            print("Telemetry disabled: \(TelemetryEncoderError.documentsDirectoryUnavailable.localizedDescription)")
            return
        }

        let telemetryDirectory = documentsDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        let backupRootDirectory = telemetryDirectory
            .appendingPathComponent("backup", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: telemetryDirectory,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: backupRootDirectory,
                withIntermediateDirectories: true
            )

            self.telemetryDirectory = telemetryDirectory
            self.backupRootDirectory = backupRootDirectory
        } catch {
            self.telemetryDirectory = nil
            self.backupRootDirectory = nil
            print(
                "Telemetry disabled: \(TelemetryEncoderError.directoryCreationFailed(telemetryDirectory, error).localizedDescription)"
            )
            return
        }

        for metric in enabledMetrics {
            do {
                metricEncoders[metric] = try MetricJSONLEncoder(
                    metric: metric,
                    telemetryDirectory: telemetryDirectory,
                    synchronizeEveryNRecords: self.synchronizeEveryNRecords
                )
            } catch {
                failedMetrics.insert(metric)
                print("Telemetry metric disabled [\(metric.rawValue)]: \(error)")
            }
        }

        if let lifecycleEncoder = metricEncoders[.appLifecycleEvent] {
            nextSequenceNumber = 1
            let initializationRecord = TelemetryRecord(
                sequenceNumber: nextSequenceNumber,
                metric: .appLifecycleEvent,
                launchID: launchID,
                mappingSessionID: nil,
                textValue: "telemetry_encoder_initialized",
                metadata: ["launch_id": launchID.uuidString]
            )

            do {
                try lifecycleEncoder.append(
                    initializationRecord,
                    synchronizeImmediately: true
                )
            } catch {
                failedMetrics.insert(.appLifecycleEvent)
                metricEncoders.removeValue(forKey: .appLifecycleEvent)
                print("Telemetry metric disabled [app_lifecycle_event]: \(error)")
            }
        }
    }

    // MARK: Public state

    public func activeMappingSessionID() -> UUID? {
        currentMappingSessionID
    }

    public func telemetryDirectoryURL() -> URL? {
        telemetryDirectory
    }

    public func unavailableMetrics() -> Set<TelemetryMetric> {
        failedMetrics
    }

    // MARK: Record values

    /// Adds a numeric sample to the JSONL file belonging to `metric`.
    /// Errors are contained internally so telemetry cannot crash the app.
    @discardableResult
    public func add(
        metric: TelemetryMetric,
        value: Double,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) -> Bool {
        appendRecord(
            metric: metric,
            numericValue: value,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )
    }

    /// Adds a categorical/string sample to the JSONL file belonging to `metric`.
    /// Use this for thermal state, battery state, lifecycle events, and result labels.
    @discardableResult
    public func add(
        metric: TelemetryMetric,
        text: String,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) -> Bool {
        appendRecord(
            metric: metric,
            textValue: text,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )
    }

    /// Adds an event with metadata but no numeric or string value.
    @discardableResult
    public func addEvent(
        metric: TelemetryMetric,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) -> Bool {
        appendRecord(
            metric: metric,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )
    }

    // MARK: Mapping-session boundaries

    /// Begins a mapping session, writes a boundary event, synchronizes all files,
    /// and creates a uniquely named backup snapshot.
    @discardableResult
    public func beginMappingSession(
        id: UUID = UUID(),
        metadata: [String: String] = [:]
    ) -> UUID {
        currentMappingSessionID = id

        _ = appendRecord(
            metric: .mappingSessionEvent,
            textValue: "started",
            mappingSessionID: id,
            metadata: metadata,
            synchronizeImmediately: true
        )

        synchronizeAll()
        _ = createBackup(reason: "mapping_session_start", mappingSessionID: id)
        return id
    }

    /// Writes an end boundary, synchronizes all files, and creates a uniquely
    /// named backup snapshot. The encoder remains active afterward.
    public func endMappingSession(
        id: UUID? = nil,
        metadata: [String: String] = [:]
    ) {
        let sessionID = id ?? currentMappingSessionID

        _ = appendRecord(
            metric: .mappingSessionEvent,
            textValue: "ended",
            mappingSessionID: sessionID,
            metadata: metadata,
            synchronizeImmediately: true
        )

        synchronizeAll()
        _ = createBackup(reason: "mapping_session_end", mappingSessionID: sessionID)

        if id == nil || currentMappingSessionID == id {
            currentMappingSessionID = nil
        }
    }

    /// Optional lifecycle markers that do not close the telemetry files.
    public func recordAppLifecycleEvent(
        _ event: String,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) {
        _ = appendRecord(
            metric: .appLifecycleEvent,
            textValue: event,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )
    }

    // MARK: Backup and persistence

    /// Copies all currently enabled metric files to a new unique backup folder.
    /// A failure to copy one file does not stop the remaining files from copying.
    @discardableResult
    public func createBackup(
        reason: String,
        mappingSessionID: UUID? = nil
    ) -> URL? {
        guard !isShutDown, let backupRootDirectory else {
            return nil
        }

        synchronizeAll()

        let safeReason = sanitizePathComponent(reason)
        let timestampMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000.0)
        let backupName = "\(timestampMilliseconds)_\(safeReason)_\(UUID().uuidString)"
        let backupDirectory = backupRootDirectory
            .appendingPathComponent(backupName, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: false
            )
        } catch {
            print("Telemetry backup directory creation failed: \(error)")
            return nil
        }

        var copiedMetrics: [String] = []
        var failedCopies: [String: String] = [:]

        for (metric, encoder) in metricEncoders {
            let destinationURL = backupDirectory
                .appendingPathComponent(encoder.fileURL.lastPathComponent)

            do {
                try fileManager.copyItem(
                    at: encoder.fileURL,
                    to: destinationURL
                )
                copiedMetrics.append(metric.rawValue)
            } catch {
                failedCopies[metric.rawValue] = error.localizedDescription
                print("Telemetry backup failed [\(metric.rawValue)]: \(error)")
            }
        }

        writeBackupManifest(
            to: backupDirectory,
            reason: reason,
            mappingSessionID: mappingSessionID ?? currentMappingSessionID,
            copiedMetrics: copiedMetrics,
            failedCopies: failedCopies
        )

        return backupDirectory
    }

    /// Requests that all open metric files be synchronized to persistent storage.
    /// Individual failures are contained and the affected metric is disabled.
    public func synchronizeAll() {
        guard !isShutDown else {
            return
        }

        for (metric, encoder) in Array(metricEncoders) {
            do {
                try encoder.synchronize()
            } catch {
                disableMetric(metric, error: error)
            }
        }
    }

    /// Optional clean shutdown. The app does not need to call this for each mapping
    /// session. After shutdown, this TelemetryEncoder instance accepts no writes.
    public func shutdown() {
        guard !isShutDown else {
            return
        }

        _ = appendRecord(
            metric: .appLifecycleEvent,
            textValue: "telemetry_encoder_shutdown",
            synchronizeImmediately: true
        )

        for (metric, encoder) in Array(metricEncoders) {
            do {
                try encoder.close()
            } catch {
                print("Telemetry close failed [\(metric.rawValue)]: \(error)")
            }
        }

        metricEncoders.removeAll()
        isShutDown = true
    }

    // MARK: Internal append logic

    @discardableResult
    private func appendRecord(
        metric: TelemetryMetric,
        numericValue: Double? = nil,
        textValue: String? = nil,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) -> Bool {
        guard !isShutDown,
              !failedMetrics.contains(metric),
              let encoder = metricEncoders[metric] else {
            return false
        }

        nextSequenceNumber &+= 1

        let record = TelemetryRecord(
            sequenceNumber: nextSequenceNumber,
            metric: metric,
            launchID: launchID,
            mappingSessionID: mappingSessionID ?? currentMappingSessionID,
            numericValue: numericValue,
            textValue: textValue,
            metadata: metadata
        )

        do {
            try encoder.append(
                record,
                synchronizeImmediately: synchronizeImmediately
            )
            return true
        } catch {
            disableMetric(metric, error: error)
            return false
        }
    }

    private func disableMetric(_ metric: TelemetryMetric, error: Error) {
        failedMetrics.insert(metric)
        metricEncoders.removeValue(forKey: metric)
        print("Telemetry metric disabled [\(metric.rawValue)]: \(error)")
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_" )
        )

        let sanitizedScalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "_"
        }

        let sanitized = String(sanitizedScalars)
        return sanitized.isEmpty ? "backup" : sanitized
    }

    private func writeBackupManifest(
        to backupDirectory: URL,
        reason: String,
        mappingSessionID: UUID?,
        copiedMetrics: [String],
        failedCopies: [String: String]
    ) {
        struct BackupManifest: Codable {
            let timestamp: Date
            let reason: String
            let launchID: UUID
            let mappingSessionID: UUID?
            let copiedMetrics: [String]
            let failedCopies: [String: String]
        }

        let manifest = BackupManifest(
            timestamp: Date(),
            reason: reason,
            launchID: launchID,
            mappingSessionID: mappingSessionID,
            copiedMetrics: copiedMetrics.sorted(),
            failedCopies: failedCopies
        )

        let manifestURL = backupDirectory
            .appendingPathComponent("manifest.json", isDirectory: false)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(manifest)
            try data.write(to: manifestURL, options: [.atomic])
        } catch {
            print("Telemetry backup manifest write failed: \(error)")
        }
    }
}
