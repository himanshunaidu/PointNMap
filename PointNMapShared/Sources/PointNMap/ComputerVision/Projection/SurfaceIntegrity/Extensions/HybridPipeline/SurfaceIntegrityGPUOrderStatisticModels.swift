import Foundation
import Metal
import PointNMapShaderTypes

public enum SurfaceIntegrityOrderStatisticOperation: UInt32, Sendable {
    case percentile = 0
    case medianAbsoluteDeviation = 1
}

public struct SurfaceIntegrityGPUOrderStatisticPlan: Sendable {
    public let primaryDescriptors: [SurfaceIntegrityOrderStatisticDescriptorGPU]
    public let madDescriptors: [SurfaceIntegrityOrderStatisticDescriptorGPU]
    public let featureStride: Int

    public init(
        primaryDescriptors: [SurfaceIntegrityOrderStatisticDescriptorGPU],
        madDescriptors: [SurfaceIntegrityOrderStatisticDescriptorGPU],
        featureStride: Int
    ) {
        self.primaryDescriptors = primaryDescriptors
        self.madDescriptors = madDescriptors
        self.featureStride = featureStride
    }
}

public struct SurfaceIntegrityGPUOrderStatisticIntermediate: @unchecked Sendable {
    public let primaryValuesBuffer: MTLBuffer
    public let primaryValues: [Float]
    public let madValuesBuffer: MTLBuffer?
    public let madValues: [Float]
    public let originalWindowCount: Int
    public let primaryDescriptorCount: Int
    public let madDescriptorCount: Int
    public let selectionMilliseconds: Double
}

public enum SurfaceIntegrityGPUOrderStatisticError: Error, LocalizedError {
    case invalidPercentile(Int)
    case invalidFeatureSlot

    public var errorDescription: String? {
        switch self {
        case .invalidPercentile(let percentile):
            return "Order-statistic percentile \(percentile) is outside 0...100."
        case .invalidFeatureSlot:
            return "Order-statistic feature configuration exceeds GPU slot bounds."
        }
    }
}
