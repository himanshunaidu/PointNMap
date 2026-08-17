//
//  RateTracker.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//

import Foundation

public struct RateSnapshot: Sendable {
    public let eventCount: UInt64
    public let totalEventCount: UInt64
    public let windowDurationSeconds: Double
    public let rateHz: Double
    public let windowIndex: UInt64

    public init(
        eventCount: UInt64,
        totalEventCount: UInt64,
        windowDurationSeconds: Double,
        rateHz: Double,
        windowIndex: UInt64
    ) {
        self.eventCount = eventCount
        self.totalEventCount = totalEventCount
        self.windowDurationSeconds = windowDurationSeconds
        self.rateHz = rateHz
        self.windowIndex = windowIndex
    }
}

/// Thread-safe event-rate tracker.
///
/// Call `mark()` whenever the tracked event completes. The tracker emits one
/// telemetry sample after each configured window. File I/O is delegated to the
/// `TelemetryEncoder` actor, so `mark()` itself remains synchronous and light.
public final class RateTracker: @unchecked Sendable {
    public let metric: TelemetryMetric
    public let windowDurationSeconds: Double

    private struct Emission: Sendable {
        let snapshot: RateSnapshot
        let mappingSessionID: UUID?
        let metadata: [String: String]
        let synchronizeImmediately: Bool
    }

    private let telemetryEncoder: TelemetryEncoder?
    private let baseMetadata: [String: String]
    private let synchronizeImmediately: Bool
    private let clock = ContinuousClock()
    private let lock = NSLock()

    private var mappingSessionID: UUID?
    private var windowStart: ContinuousClock.Instant?
    private var windowEventCount: UInt64 = 0
    private var totalEventCount: UInt64 = 0
    private var windowIndex: UInt64 = 0
    private var isRunning: Bool

    public init(
        metric: TelemetryMetric,
        telemetryEncoder: TelemetryEncoder? = nil,
        windowDurationSeconds: Double = 30.0,
        mappingSessionID: UUID? = nil,
        metadata: [String: String] = [:],
        synchronizeImmediately: Bool = false,
        startImmediately: Bool = true
    ) {
        self.metric = metric
        self.telemetryEncoder = telemetryEncoder
        self.windowDurationSeconds = max(0.001, windowDurationSeconds)
        self.mappingSessionID = mappingSessionID
        self.baseMetadata = metadata
        self.synchronizeImmediately = synchronizeImmediately
        self.isRunning = startImmediately
        self.windowStart = startImmediately ? clock.now : nil
    }

    /// Starts or restarts the current rate window.
    public func start(
        mappingSessionID: UUID? = nil,
        resetTotalCount: Bool = false
    ) {
        lock.lock()
        defer { lock.unlock() }

        if let mappingSessionID {
            self.mappingSessionID = mappingSessionID
        }

        if resetTotalCount {
            totalEventCount = 0
            windowIndex = 0
        }

        windowEventCount = 0
        windowStart = clock.now
        isRunning = true
    }

    /// Updates the session identifier attached to future rate records.
    public func setMappingSessionID(_ id: UUID?) {
        lock.lock()
        mappingSessionID = id
        lock.unlock()
    }

    /// Records one or more occurrences of the tracked event.
    ///
    /// - Returns: A completed rate window when this call crossed the configured
    ///   window duration; otherwise `nil`.
    @discardableResult
    public func mark(count: UInt64 = 1) -> RateSnapshot? {
        guard count > 0 else {
            return nil
        }

        let now = clock.now
        var emission: Emission?

        lock.lock()

        if !isRunning {
            isRunning = true
            windowStart = now
        }

        if windowStart == nil {
            windowStart = now
        }

        windowEventCount &+= count
        totalEventCount &+= count

        if let start = windowStart {
            let elapsed = Self.seconds(from: start.duration(to: now))
            if elapsed >= windowDurationSeconds {
                emission = makeEmissionLocked(
                    now: now,
                    resetWindow: true,
                    additionalMetadata: [:]
                )
            }
        }

        lock.unlock()

        if let emission {
            submit(emission)
            return emission.snapshot
        }

        return nil
    }

    /// Emits the current partial window and optionally starts a fresh one.
    @discardableResult
    public func flush(
        resetWindow: Bool = true,
        metadata: [String: String] = [:]
    ) -> RateSnapshot? {
        let now = clock.now
        var emission: Emission?

        lock.lock()
        emission = makeEmissionLocked(
            now: now,
            resetWindow: resetWindow,
            additionalMetadata: metadata
        )
        lock.unlock()

        if let emission {
            submit(emission)
            return emission.snapshot
        }

        return nil
    }

    /// Stops tracking. By default, any nonempty partial window is emitted first.
    public func stop(
        flushPartialWindow: Bool = true,
        metadata: [String: String] = [:]
    ) {
        if flushPartialWindow {
            _ = flush(resetWindow: false, metadata: metadata)
        }

        lock.lock()
        isRunning = false
        windowStart = nil
        windowEventCount = 0
        lock.unlock()
    }

    /// Returns the current in-progress window without recording or resetting it.
    public func currentSnapshot() -> RateSnapshot? {
        let now = clock.now

        lock.lock()
        defer { lock.unlock() }

        guard let start = windowStart else {
            return nil
        }

        let elapsed = Self.seconds(from: start.duration(to: now))
        guard elapsed > 0 else {
            return nil
        }

        return RateSnapshot(
            eventCount: windowEventCount,
            totalEventCount: totalEventCount,
            windowDurationSeconds: elapsed,
            rateHz: Double(windowEventCount) / elapsed,
            windowIndex: windowIndex
        )
    }

    private func makeEmissionLocked(
        now: ContinuousClock.Instant,
        resetWindow: Bool,
        additionalMetadata: [String: String]
    ) -> Emission? {
        guard let start = windowStart else {
            return nil
        }

        let elapsed = Self.seconds(from: start.duration(to: now))
        guard elapsed > 0, windowEventCount > 0 else {
            if resetWindow {
                windowStart = now
                windowEventCount = 0
            }
            return nil
        }

        let snapshot = RateSnapshot(
            eventCount: windowEventCount,
            totalEventCount: totalEventCount,
            windowDurationSeconds: elapsed,
            rateHz: Double(windowEventCount) / elapsed,
            windowIndex: windowIndex
        )

        var metadata = baseMetadata.merging(additionalMetadata) {
            _, newValue in newValue
        }
        metadata["event_count"] = String(snapshot.eventCount)
        metadata["total_event_count"] = String(snapshot.totalEventCount)
        metadata["window_duration_s"] = String(snapshot.windowDurationSeconds)
        metadata["window_index"] = String(snapshot.windowIndex)

        let emission = Emission(
            snapshot: snapshot,
            mappingSessionID: mappingSessionID,
            metadata: metadata,
            synchronizeImmediately: synchronizeImmediately
        )

        if resetWindow {
            windowIndex &+= 1
            windowEventCount = 0
            windowStart = now
        }

        return emission
    }

    private func submit(_ emission: Emission) {
        guard let telemetryEncoder else {
            return
        }

        let metric = metric

        Task(priority: .utility) {
            _ = await telemetryEncoder.add(
                metric: metric,
                value: emission.snapshot.rateHz,
                mappingSessionID: emission.mappingSessionID,
                metadata: emission.metadata,
                synchronizeImmediately: emission.synchronizeImmediately
            )
        }
    }

    private static func seconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds)
            + Double(components.attoseconds)
                / 1_000_000_000_000_000_000.0
    }
}
