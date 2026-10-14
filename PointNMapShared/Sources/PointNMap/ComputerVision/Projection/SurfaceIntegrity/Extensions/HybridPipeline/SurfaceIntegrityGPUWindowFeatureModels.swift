import Foundation
import Metal

public enum SurfaceIntegrityGPUValueSource: UInt32, CaseIterable, Sendable {
    case normalDeviation
    case heightResidual
    case absoluteHeightResidual
    case signedTiltU
    case signedTiltV
    case signedTiltMagnitude
}

public struct SurfaceIntegrityGPUWindowFeatureTimings: Sendable {
    public var cpuReferenceMilliseconds: Double = 0
    public var reductionMilliseconds: Double = 0
    public var entropyMilliseconds: Double = 0
    public var orderStatisticsMilliseconds: Double = 0
    public var assemblyMilliseconds: Double = 0
    public var totalMilliseconds: Double = 0
}

public struct SurfaceIntegrityGPUWindowFeatureResult: @unchecked Sendable {
    public let originalWindowCount: Int
    public let featureStride: Int
    public let valuesBuffer: MTLBuffer
    public let values: [Float]
    public let supportedColumns: Set<SurfaceIntegrityWindowFeature>
    public let timings: SurfaceIntegrityGPUWindowFeatureTimings
}

public struct SurfaceIntegrityStagedWindowFeatureResult: Sendable {
    public let features: [SurfaceIntegrityWindowFeatures]
    public let supportedColumns: Set<SurfaceIntegrityWindowFeature>
    public let timings: SurfaceIntegrityGPUWindowFeatureTimings
}

public struct SurfaceIntegrityWindowFeatureParityDetail: Sendable {
    public let retainedWindowIndex: Int
    public let originalWindowIndex: Int
    public let feature: SurfaceIntegrityWindowFeature
    public let cpuValue: Float
    public let stagedValue: Float
    public let absoluteError: Float
    public let relativeError: Float
    public let isGPUSupported: Bool
}

public struct SurfaceIntegrityWindowFeatureParitySummary: Sendable {
    public let hasParity: Bool
    public let comparedValueCount: Int
    public let totalMismatchCount: Int
    public let gpuSupportedMismatchCount: Int
    public let cpuOnlyMismatchCount: Int
    public let maximumAbsoluteError: Float
    public let maximumRelativeError: Float
    public let details: [SurfaceIntegrityWindowFeatureParityDetail]
}
