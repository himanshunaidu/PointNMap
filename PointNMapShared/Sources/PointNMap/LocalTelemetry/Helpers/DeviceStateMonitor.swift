//
//  DeviceStateMonitor.swift
//  PointNMap
//
//  Created by Himanshu on 7/28/26.
//

import Foundation

#if canImport(UIKit)
import UIKit

/// Standalone iOS monitor for battery level, charging state, thermal state, and
/// Low Power Mode. It records periodic snapshots and immediate state changes.
@MainActor
public final class DeviceStateMonitor: NSObject {
    private let telemetryEncoder: TelemetryEncoder
    private let sampleIntervalSeconds: TimeInterval
    private let monitorApplicationLifecycle: Bool
    private let restoreBatteryMonitoringOnStop: Bool

    private var timer: Timer?
    private var isRunning = false
    private var batteryMonitoringWasEnabled = false

    public init(
        telemetryEncoder: TelemetryEncoder,
        sampleIntervalSeconds: TimeInterval = 60.0,
        monitorApplicationLifecycle: Bool = true,
        restoreBatteryMonitoringOnStop: Bool = false
    ) {
        self.telemetryEncoder = telemetryEncoder
        self.sampleIntervalSeconds = max(5.0, sampleIntervalSeconds)
        self.monitorApplicationLifecycle = monitorApplicationLifecycle
        self.restoreBatteryMonitoringOnStop = restoreBatteryMonitoringOnStop
        super.init()
    }

    public func start() {
        guard !isRunning else {
            return
        }

        isRunning = true

        let device = UIDevice.current
        batteryMonitoringWasEnabled = device.isBatteryMonitoringEnabled
        device.isBatteryMonitoringEnabled = true

        // Apple requires reading thermalState before registering for its change
        // notification.
        _ = ProcessInfo.processInfo.thermalState

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(batteryStateChanged),
            name: UIDevice.batteryStateDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: ProcessInfo.processInfo
        )
        center.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: ProcessInfo.processInfo
        )

        if monitorApplicationLifecycle {
            center.addObserver(
                self,
                selector: #selector(applicationDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            center.addObserver(
                self,
                selector: #selector(applicationWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        timer = Timer.scheduledTimer(
            timeInterval: sampleIntervalSeconds,
            target: self,
            selector: #selector(periodicTimerFired),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = min(5.0, sampleIntervalSeconds * 0.1)

        recordSnapshot(
            reason: "monitor_started",
            synchronizeImmediately: true
        )
    }

    public func stop() {
        guard isRunning else {
            return
        }

        recordSnapshot(
            reason: "monitor_stopped",
            synchronizeImmediately: true
        )

        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)

        if restoreBatteryMonitoringOnStop {
            UIDevice.current.isBatteryMonitoringEnabled = batteryMonitoringWasEnabled
        }

        isRunning = false
    }

    /// Records a device-state snapshot immediately.
    public func recordSnapshot(
        reason: String = "manual",
        synchronizeImmediately: Bool = false
    ) {
        let device = UIDevice.current
        let processInfo = ProcessInfo.processInfo

        let batteryLevel = device.batteryLevel
        let batteryState = Self.batteryStateName(device.batteryState)
        let thermalState = Self.thermalStateName(processInfo.thermalState)
        let lowPowerModeEnabled = processInfo.isLowPowerModeEnabled

        let snapshotMetadata: [String: String] = [
            "reason": reason,
            "low_power_mode_enabled": String(lowPowerModeEnabled),
            "battery_monitoring_enabled": String(device.isBatteryMonitoringEnabled)
        ]

        let telemetryEncoder = telemetryEncoder

        Task(priority: .utility) {
            // Capture one session ID and attach it to the whole snapshot so the
            // three records cannot be split across a session boundary.
            let mappingSessionID = await telemetryEncoder.activeMappingSessionID()

            if batteryLevel >= 0 {
                _ = await telemetryEncoder.add(
                    metric: .batteryLevel,
                    value: Double(batteryLevel) * 100.0,
                    mappingSessionID: mappingSessionID,
                    metadata: snapshotMetadata,
                    synchronizeImmediately: synchronizeImmediately
                )
            }

            _ = await telemetryEncoder.add(
                metric: .batteryState,
                text: batteryState,
                mappingSessionID: mappingSessionID,
                metadata: snapshotMetadata,
                synchronizeImmediately: synchronizeImmediately
            )

            _ = await telemetryEncoder.add(
                metric: .thermalState,
                text: thermalState,
                mappingSessionID: mappingSessionID,
                metadata: snapshotMetadata,
                synchronizeImmediately: synchronizeImmediately
            )
        }
    }

    @objc private func periodicTimerFired() {
        recordSnapshot(reason: "periodic")
    }

    @objc private func batteryLevelChanged() {
        recordSnapshot(reason: "battery_level_changed")
    }

    @objc private func batteryStateChanged() {
        recordSnapshot(
            reason: "battery_state_changed",
            synchronizeImmediately: true
        )
    }

    @objc private func thermalStateChanged() {
        let currentState = ProcessInfo.processInfo.thermalState
        recordSnapshot(
            reason: "thermal_state_changed",
            synchronizeImmediately: currentState == .serious || currentState == .critical
        )
    }

    @objc private func powerStateChanged() {
        recordSnapshot(
            reason: "low_power_mode_changed",
            synchronizeImmediately: true
        )
    }

    @objc private func applicationDidEnterBackground() {
        recordSnapshot(
            reason: "application_did_enter_background",
            synchronizeImmediately: true
        )

        let telemetryEncoder = telemetryEncoder
        Task(priority: .utility) {
            await telemetryEncoder.recordAppLifecycleEvent(
                "background",
                synchronizeImmediately: true
            )
        }
    }

    @objc private func applicationWillEnterForeground() {
        recordSnapshot(
            reason: "application_will_enter_foreground",
            synchronizeImmediately: true
        )

        let telemetryEncoder = telemetryEncoder
        Task(priority: .utility) {
            await telemetryEncoder.recordAppLifecycleEvent(
                "foreground",
                synchronizeImmediately: true
            )
        }
    }

    private static func batteryStateName(
        _ state: UIDevice.BatteryState
    ) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        @unknown default:
            return "future_unknown"
        }
    }

    private static func thermalStateName(
        _ state: ProcessInfo.ThermalState
    ) -> String {
        switch state {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "future_unknown"
        }
    }

    deinit {
        timer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

#else

@available(*, unavailable, message: "DeviceStateMonitor requires UIKit and must be built for iOS.")
public final class DeviceStateMonitor {}

#endif
