//
//  AssetTracker.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//

import Foundation

public enum AssetSizeKind: String, Codable, Sendable {
    /// Sum of file content lengths.
    case logical

    /// Sum of filesystem-allocated bytes. Falls back to logical size when an
    /// allocated size is unavailable for a file.
    case allocatedOnDisk
}

public struct AssetSizeMeasurement: Codable, Sendable {
    public let url: URL
    public let sizeKind: AssetSizeKind
    public let bytes: Int64
    public let fileCount: Int

    public var megabytes: Double {
        Double(bytes) / 1_000_000.0
    }

    public var mebibytes: Double {
        Double(bytes) / 1_048_576.0
    }
}

public enum AssetTrackerError: LocalizedError {
    case resourceNotFound(name: String, extension: String)
    case unableToEnumerate(URL)

    public var errorDescription: String? {
        switch self {
        case let .resourceNotFound(name, fileExtension):
            return "Could not find resource \(name).\(fileExtension)."
        case let .unableToEnumerate(url):
            return "Could not enumerate asset at \(url.path)."
        }
    }
}

/// Measures the size of compiled model resources or other files/directories.
public enum AssetTracker {
    /// Locates a compiled Core ML resource in a bundle.
    public static func compiledModelURL(
        named resourceName: String,
        in bundle: Bundle = .main,
        subdirectory: String? = nil
    ) throws -> URL {
        guard let url = bundle.url(
            forResource: resourceName,
            withExtension: "mlmodelc",
            subdirectory: subdirectory
        ) else {
            throw AssetTrackerError.resourceNotFound(
                name: resourceName,
                extension: "mlmodelc"
            )
        }

        return url
    }

    /// Recursively measures a file or directory.
    public static func measure(
        url: URL,
        sizeKind: AssetSizeKind = .logical,
        fileManager: FileManager = .default
    ) throws -> AssetSizeMeasurement {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .fileAllocatedSizeKey
        ]

        let rootValues = try url.resourceValues(forKeys: keys)

        if rootValues.isRegularFile == true {
            let bytes = sizeInBytes(
                values: rootValues,
                sizeKind: sizeKind
            )
            return AssetSizeMeasurement(
                url: url,
                sizeKind: sizeKind,
                bytes: bytes,
                fileCount: 1
            )
        }

        guard rootValues.isDirectory == true,
              let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles],
                errorHandler: { childURL, error in
                    print("AssetTracker enumeration warning [\(childURL.path)]: \(error)")
                    return true
                }
              ) else {
            throw AssetTrackerError.unableToEnumerate(url)
        }

        var totalBytes: Int64 = 0
        var fileCount = 0

        for case let childURL as URL in enumerator {
            let values = try childURL.resourceValues(forKeys: keys)

            // Avoid following/counting symbolic links as separate asset data.
            if values.isSymbolicLink == true {
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            totalBytes += sizeInBytes(
                values: values,
                sizeKind: sizeKind
            )
            fileCount += 1
        }

        return AssetSizeMeasurement(
            url: url,
            sizeKind: sizeKind,
            bytes: totalBytes,
            fileCount: fileCount
        )
    }

    /// Measures a compiled Core ML resource and writes its size in decimal MB to
    /// `compiled_segmentation_model_size.jsonl`.
    @discardableResult
    public static func recordCompiledModelSize(
        named resourceName: String,
        in bundle: Bundle = .main,
        subdirectory: String? = nil,
        sizeKind: AssetSizeKind = .logical,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = true
    ) async throws -> AssetSizeMeasurement {
        let url = try compiledModelURL(
            named: resourceName,
            in: bundle,
            subdirectory: subdirectory
        )

        return try await recordSize(
            of: url,
            metric: .compiledSegmentationModelSize,
            sizeKind: sizeKind,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: metadata.merging(
                ["resource_name": resourceName],
                uniquingKeysWith: { _, newValue in newValue }
            ),
            synchronizeImmediately: synchronizeImmediately
        )
    }

    /// Measures any asset and records the value in decimal MB using the supplied
    /// telemetry metric.
    @discardableResult
    public static func recordSize(
        of url: URL,
        metric: TelemetryMetric,
        sizeKind: AssetSizeKind = .logical,
        telemetryEncoder: TelemetryEncoder,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = true
    ) async throws -> AssetSizeMeasurement {
        let measurement = try measure(
            url: url,
            sizeKind: sizeKind
        )

        var recordMetadata = metadata
        recordMetadata["asset_path"] = url.lastPathComponent
        recordMetadata["size_kind"] = sizeKind.rawValue
        recordMetadata["size_bytes"] = String(measurement.bytes)
        recordMetadata["file_count"] = String(measurement.fileCount)

        _ = await telemetryEncoder.add(
            metric: metric,
            value: measurement.megabytes,
            mappingSessionID: mappingSessionID,
            metadata: recordMetadata,
            synchronizeImmediately: synchronizeImmediately
        )

        return measurement
    }

    private static func sizeInBytes(
        values: URLResourceValues,
        sizeKind: AssetSizeKind
    ) -> Int64 {
        switch sizeKind {
        case .logical:
            return Int64(values.fileSize ?? 0)
        case .allocatedOnDisk:
            return Int64(
                values.fileAllocatedSize
                    ?? values.fileSize
                    ?? 0
            )
        }
    }
}
