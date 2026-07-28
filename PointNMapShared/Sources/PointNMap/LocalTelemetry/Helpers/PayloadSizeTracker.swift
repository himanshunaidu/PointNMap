//
//  PayloadSizeTracker.swift
//  PointNMap
//
//  Created by Himanshu on 7/28/26.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PayloadSizeSource: String, Codable, Sendable {
    case data
    case file
    case requestHTTPBody
    case contentLengthHeader
    case urlSessionExpectedBytes
}

public struct PayloadSizeMeasurement: Codable, Sendable {
    public let bytes: Int64
    public let source: PayloadSizeSource

    public var kilobytes: Double {
        Double(bytes) / 1_000.0
    }

    public var megabytes: Double {
        Double(bytes) / 1_000_000.0
    }
}

/// Gets the encoded payload size before an upload begins.
///
/// Prefer measuring the actual `Data` supplied to the upload. A request backed
/// by `httpBodyStream` cannot be measured safely without consuming/replacing the
/// stream; this helper therefore uses `Content-Length` when available and
/// otherwise returns `nil`.
public enum PayloadSizeTracker {
    public static func measure(data: Data) -> PayloadSizeMeasurement {
        PayloadSizeMeasurement(
            bytes: Int64(data.count),
            source: .data
        )
    }

    public static func measure(
        fileAt url: URL
    ) throws -> PayloadSizeMeasurement {
        let values = try url.resourceValues(
            forKeys: [.fileSizeKey]
        )

        return PayloadSizeMeasurement(
            bytes: Int64(values.fileSize ?? 0),
            source: .file
        )
    }

    public static func measure(
        request: URLRequest
    ) -> PayloadSizeMeasurement? {
        if let body = request.httpBody {
            return PayloadSizeMeasurement(
                bytes: Int64(body.count),
                source: .requestHTTPBody
            )
        }

        if let contentLength = request.value(
            forHTTPHeaderField: "Content-Length"
        ), let bytes = Int64(contentLength), bytes >= 0 {
            return PayloadSizeMeasurement(
                bytes: bytes,
                source: .contentLengthHeader
            )
        }

        // Do not read request.httpBodyStream here. Reading it would consume or
        // disturb the stream used by URLSession.
        return nil
    }

    public static func measure(
        task: URLSessionTask
    ) -> PayloadSizeMeasurement? {
        let expectedBytes = task.countOfBytesExpectedToSend
        guard expectedBytes >= 0 else {
            return nil
        }

        return PayloadSizeMeasurement(
            bytes: expectedBytes,
            source: .urlSessionExpectedBytes
        )
    }

    @discardableResult
    public static func record(
        data: Data,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) async -> PayloadSizeMeasurement {
        let measurement = measure(data: data)
        await record(
            measurement: measurement,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )
        return measurement
    }

    @discardableResult
    public static func record(
        fileAt url: URL,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) async throws -> PayloadSizeMeasurement {
        let measurement = try measure(fileAt: url)
        var mergedMetadata = metadata
        mergedMetadata["file_name"] = url.lastPathComponent

        await record(
            measurement: measurement,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: mergedMetadata,
            synchronizeImmediately: synchronizeImmediately
        )
        return measurement
    }

    @discardableResult
    public static func record(
        request: URLRequest,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) async -> PayloadSizeMeasurement? {
        guard let measurement = measure(request: request) else {
            return nil
        }

        var mergedMetadata = metadata
        mergedMetadata["http_method"] = request.httpMethod ?? "unknown"
        mergedMetadata["host"] = request.url?.host ?? "unknown"

        await record(
            measurement: measurement,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: mergedMetadata,
            synchronizeImmediately: synchronizeImmediately
        )
        return measurement
    }

    @discardableResult
    public static func record(
        task: URLSessionTask,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) async -> PayloadSizeMeasurement? {
        guard let measurement = measure(task: task) else {
            return nil
        }

        var mergedMetadata = metadata
        mergedMetadata["task_id"] = String(task.taskIdentifier)

        await record(
            measurement: measurement,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: mergedMetadata,
            synchronizeImmediately: synchronizeImmediately
        )
        return measurement
    }

    private static func record(
        measurement: PayloadSizeMeasurement,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID?,
        metadata: [String: String],
        synchronizeImmediately: Bool
    ) async {
        var recordMetadata = metadata
        recordMetadata["size_source"] = measurement.source.rawValue
        recordMetadata["size_bytes"] = String(measurement.bytes)

        _ = await telemetryEncoder.add(
            metric: .uploadPayloadSize,
            value: Double(measurement.bytes),
            mappingSessionID: mappingSessionID,
            metadata: recordMetadata,
            synchronizeImmediately: synchronizeImmediately
        )
    }
}
