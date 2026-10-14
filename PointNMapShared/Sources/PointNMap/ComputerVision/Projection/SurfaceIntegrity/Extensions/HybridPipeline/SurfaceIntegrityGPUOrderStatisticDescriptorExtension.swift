import Foundation
import PointNMapShaderTypes

public extension SurfaceIntegrityProcessor {
    static func makeGPUOrderStatisticPlan(
        configuration: SurfaceIntegrityFeatureConfiguration
    ) throws -> SurfaceIntegrityGPUOrderStatisticPlan {
        guard configuration.allColumns.count <= Int(UInt32.max) else {
            throw SurfaceIntegrityGPUOrderStatisticError.invalidFeatureSlot
        }

        var primary: [SurfaceIntegrityOrderStatisticDescriptorGPU] = []
        var mad: [SurfaceIntegrityOrderStatisticDescriptorGPU] = []
        var groupColumnOffset = 0

        for group in configuration.featureGroups {
            let source = gpuSourceIndex(group.source)
            var medianDependency: UInt32?

            if let medianColumn = group.centralTendencyFeatures.firstIndex(of: .median) {
                medianDependency = UInt32(primary.count)
                primary.append(makeOrderStatisticDescriptor(
                    source: source,
                    operation: .percentile,
                    percentile: 50,
                    dependencySlot: UInt32.max,
                    destinationFeatureSlot: UInt32(groupColumnOffset + medianColumn)
                ))
            }

            for (centralIndex, feature) in group.centralTendencyFeatures.enumerated()
                where feature == .medianAbsoluteDeviation {
                if medianDependency == nil {
                    medianDependency = UInt32(primary.count)
                    primary.append(makeOrderStatisticDescriptor(
                        source: source,
                        operation: .percentile,
                        percentile: 50,
                        dependencySlot: UInt32.max,
                        destinationFeatureSlot: UInt32.max
                    ))
                }
                mad.append(makeOrderStatisticDescriptor(
                    source: source,
                    operation: .medianAbsoluteDeviation,
                    percentile: 50,
                    dependencySlot: medianDependency ?? UInt32.max,
                    destinationFeatureSlot: UInt32(groupColumnOffset + centralIndex)
                ))
            }

            let percentileOffset = groupColumnOffset + group.centralTendencyFeatures.count
            for (index, percentile) in group.percentileFeatures.enumerated() {
                guard (0...100).contains(percentile) else {
                    throw SurfaceIntegrityGPUOrderStatisticError.invalidPercentile(percentile)
                }
                primary.append(makeOrderStatisticDescriptor(
                    source: source,
                    operation: .percentile,
                    percentile: Float(percentile),
                    dependencySlot: UInt32.max,
                    destinationFeatureSlot: UInt32(percentileOffset + index)
                ))
            }
            groupColumnOffset += group.columns.count
        }

        return SurfaceIntegrityGPUOrderStatisticPlan(
            primaryDescriptors: primary,
            madDescriptors: mad,
            featureStride: configuration.allColumns.count
        )
    }
}

private extension SurfaceIntegrityProcessor {
    static func gpuSourceIndex(_ source: SurfaceIntegrityFeatureValueSource) -> UInt32 {
        switch source {
        case .normalDeviation: 0
        case .heightResidual: 1
        case .absoluteHeightResidual: 2
        case .signedTiltU: 3
        case .signedTiltV: 4
        case .signedTiltMagnitude: 5
        }
    }

    static func makeOrderStatisticDescriptor(
        source: UInt32,
        operation: SurfaceIntegrityOrderStatisticOperation,
        percentile: Float,
        dependencySlot: UInt32,
        destinationFeatureSlot: UInt32
    ) -> SurfaceIntegrityOrderStatisticDescriptorGPU {
        SurfaceIntegrityOrderStatisticDescriptorGPU(
            source: source,
            operation: operation.rawValue,
            percentile: percentile,
            dependencySlot: dependencySlot,
            destinationFeatureSlot: destinationFeatureSlot
        )
    }
}
