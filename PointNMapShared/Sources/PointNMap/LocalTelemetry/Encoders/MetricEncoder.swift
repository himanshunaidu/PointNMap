//
//  MetricEncoder.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//
import Foundation

final class MetricJSONLEncoder {
    let metric: TelemetryMetric
    let fileURL: URL

    private let fileHandle: FileHandle
    private let jsonEncoder: JSONEncoder
    /// The number of records to append before synchronizing the file handle to disk.
    private let synchronizeEveryNRecords: Int
    private var recordsSinceSynchronization: Int = 0

    init(
        metric: TelemetryMetric,
        telemetryDirectory: URL,
        synchronizeEveryNRecords: Int
    ) throws {
        self.metric = metric
        self.fileURL = telemetryDirectory
            .appendingPathComponent(metric.rawValue)
            .appendingPathExtension("jsonl")
        self.synchronizeEveryNRecords = max(1, synchronizeEveryNRecords)

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: fileURL.path) {
            guard fileManager.createFile(atPath: fileURL.path, contents: nil) else {
                throw TelemetryEncoderError.fileCreationFailed(fileURL)
            }
        }

        self.fileHandle = try FileHandle(forWritingTo: fileURL)
        _ = try self.fileHandle.seekToEnd()

        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    func append(_ record: TelemetryRecord, synchronizeImmediately: Bool) throws {
        var data = try jsonEncoder.encode(record)
        data.append(0x0A) // Newline: one complete JSON object per line.

        try fileHandle.write(contentsOf: data)
        recordsSinceSynchronization += 1

        if synchronizeImmediately || recordsSinceSynchronization >= synchronizeEveryNRecords {
            try synchronize()
        }
    }

    func synchronize() throws {
        try fileHandle.synchronize()
        recordsSinceSynchronization = 0
    }

    func close() throws {
        try synchronize()
        try fileHandle.close()
    }
}
