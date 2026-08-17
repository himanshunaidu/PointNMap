//
//  MetricTimer.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//

import Foundation

/// A one-shot stopwatch for timing an operation with `ContinuousClock`.
///
/// `MetricTimer` can be created in one method and stopped later from a callback.
/// Stopping the timer more than once is harmless: only the first call records data.
public final class MetricTimer: @unchecked Sendable {
    public let metric: TelemetryMetric
    public let mappingSessionID: UUID?

    private let telemetryEncoder: TelemetryEncoder?
    private let baseMetadata: [String: String]
    private let synchronizeImmediately: Bool

    private let clock = ContinuousClock()
    private let startInstant: ContinuousClock.Instant

    private let stateLock = NSLock()
    private var hasFinished = false

    public init(
        metric: TelemetryMetric,
        telemetryEncoder: TelemetryEncoder? = nil,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false
    ) {
        self.metric = metric
        self.telemetryEncoder = telemetryEncoder
        self.mappingSessionID = mappingSessionID
        self.baseMetadata = metadata
        self.synchronizeImmediately = synchronizeImmediately
        self.startInstant = clock.now
    }

    /// Returns the elapsed duration without stopping or recording the timer.
    public func elapsedDuration() -> Duration {
        startInstant.duration(to: clock.now)
    }

    /// Returns the elapsed duration in milliseconds without stopping the timer.
    public func elapsedMilliseconds() -> Double {
        Self.milliseconds(from: elapsedDuration())
    }

    /// Stops the timer and optionally writes the duration to `TelemetryEncoder`.
    ///
    /// - Returns: The elapsed time in milliseconds, or `nil` when the timer had
    ///   already been stopped or cancelled.
    @discardableResult
    public func stop(
        metadata: [String: String] = [:]
    ) async -> Double? {
        guard claimFinish() else {
            return nil
        }

        let elapsedMS = elapsedMilliseconds()

        guard let telemetryEncoder else {
            return elapsedMS
        }

        let mergedMetadata = baseMetadata.merging(metadata) {
            _, newValue in newValue
        }

        _ = await telemetryEncoder.add(
            metric: metric,
            value: elapsedMS,
            mappingSessionID: mappingSessionID,
            metadata: mergedMetadata,
            synchronizeImmediately: synchronizeImmediately
        )

        return elapsedMS
    }

    /// Marks the timer as finished without writing a telemetry record.
    /// This is useful when an operation is abandoned or its sample is invalid.
    @discardableResult
    public func cancel() -> Bool {
        claimFinish()
    }

    /// Times a synchronous operation and records the elapsed duration.
    @discardableResult
    public static func measure<Value>(
        metric: TelemetryMetric,
        telemetryEncoder: TelemetryEncoder? = nil,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false,
        operation: () throws -> Value
    ) async rethrows -> Value {
        let timer = MetricTimer(
            metric: metric,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )

        do {
            let value = try operation()
            _ = await timer.stop(metadata: ["result": "success"])
            return value
        } catch {
            _ = await timer.stop(
                metadata: [
                    "result": "failure",
                    "error": String(describing: error)
                ]
            )
            throw error
        }
    }

    /// Times an asynchronous operation and records the elapsed duration.
    @discardableResult
    public static func measure<Value: Sendable>(
        metric: TelemetryMetric,
        telemetryEncoder: TelemetryEncoder? = nil,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false,
        operation: @Sendable () async throws -> Value
    ) async rethrows -> Value {
        let timer = MetricTimer(
            metric: metric,
            telemetryEncoder: telemetryEncoder,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )

        do {
            let value = try await operation()
            _ = await timer.stop(metadata: ["result": "success"])
            return value
        } catch {
            _ = await timer.stop(
                metadata: [
                    "result": "failure",
                    "error": String(describing: error)
                ]
            )
            throw error
        }
    }

    private func claimFinish() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }

        guard !hasFinished else {
            return false
        }

        hasFinished = true
        return true
    }

    private static func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
        let fractionalSeconds = Double(components.attoseconds)
            / 1_000_000_000_000_000_000.0
        return (seconds + fractionalSeconds) * 1_000.0
    }
}
