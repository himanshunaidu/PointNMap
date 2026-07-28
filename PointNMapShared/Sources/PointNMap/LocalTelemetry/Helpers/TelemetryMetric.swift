//
//  TelemetryMetric.swift
//  PointNMap
//
//  Created by Himanshu on 7/27/26.
//

public enum TelemetryMetric: String, CaseIterable, Codable, Hashable, Sendable {
    // MARK: Deployment

    /// Unit: megabytes (MB).
    case compiledSegmentationModelSize = "compiled_segmentation_model_size"

    // MARK: Perception latency

    /// Unit: milliseconds (ms).
    /// Covered in ARCameraManager (ARCameraView -> ARCameraManager)
    case preprocessingLatency = "preprocessing_latency"

    /// Unit: milliseconds (ms).
    /// Covered in SegmentationARPipeline  (SetupView -> SegmentationARPipeline)
    case segmentationInferenceLatency = "segmentation_inference_latency"

    /// Unit: milliseconds (ms).
    /// Covered in ARCameraManager  (ARCameraView -> ARCameraManager)
    case postprocessingLatency = "postprocessing_latency"

    /// Unit: milliseconds (ms), from AR frame receipt to overlay publication.
    case frameToOverlayLatency = "frame_to_overlay_latency"

    // MARK: Perception and rendering throughput

    /// Unit: hertz (Hz).
    case cameraReceivedFrameRate = "camera_received_frame_rate"

    /// Unit: hertz (Hz).
    case inferenceSubmissionRate = "inference_submission_rate"

    /// Unit: hertz (Hz).
    /// Covered in ARCameraManager (ARCameraView -> ARCameraManager)
    case processedFrameRate = "processed_frame_rate"

    /// Unit: hertz (Hz).
    case overlayUpdateRate = "overlay_update_rate"

    /// Unit: percent (%).
    case processedFrameRatio = "processed_frame_ratio"

    /// Unit: percent (%).
    case inferenceCompletionRatio = "inference_completion_ratio"

    /// Unit: frames per second (FPS).
    case displayFrameRate = "display_frame_rate"

    // MARK: Capture

    /// Unit: milliseconds (ms).
    /// Covered in ARCameraManager (ARCameraView -> ARCameraManager)
    case captureToLocalResultLatency = "capture_to_local_result_latency"

    /// Unit: milliseconds (ms).
    case serializationLatency = "serialization_latency"

    // MARK: Network

    /// Unit: bytes.
    /// Covered in ChangesetService (ARCameraView -> APIChangesetUploadController -> ChangesetService)
    case uploadPayloadSize = "upload_payload_size"

    /// Unit: milliseconds (ms).
    case uploadLatency = "upload_latency"

    /// Unit: milliseconds (ms).
    case captureToServerAcknowledgmentLatency = "capture_to_server_acknowledgment_latency"

    /// Unit: milliseconds (ms).
    case networkRequestDuration = "network_request_duration"

    /// Unit: milliseconds (ms).
    case networkResponseDuration = "network_response_duration"

    /// Unit: categorical string, for example "success" or "failure".
    case uploadResult = "upload_result"

    // MARK: Device state and energy

    /// Unit: battery percentage (%), from 0 to 100.
    case batteryLevel = "battery_level"

    /// Unit: categorical string: unknown, unplugged, charging, or full.
    case batteryState = "battery_state"

    /// Unit: percentage points per hour.
    case batteryDrainRate = "battery_drain_rate"

    /// Unit: categorical string: nominal, fair, serious, or critical.
    case thermalState = "thermal_state"

    /// Unit: joules (J), or another explicitly documented Instruments export unit.
    case energyConsumption = "energy_consumption"

    // MARK: CPU and memory

    /// Unit: percent of one logical CPU core (%); document the convention used.
    case processCPUUtilization = "process_cpu_utilization"

    /// Unit: bytes.
    case steadyStateMemoryFootprint = "steady_state_memory_footprint"

    /// Unit: bytes.
    case peakMemoryFootprint = "peak_memory_footprint"

    // MARK: Telemetry and mapping lifecycle

    /// Unit: categorical string, for example "started", "paused", "resumed", or "ended".
    case mappingSessionEvent = "mapping_session_event"

    /// Unit: categorical string, for example "foreground", "background", or "terminated".
    case appLifecycleEvent = "app_lifecycle_event"
}
