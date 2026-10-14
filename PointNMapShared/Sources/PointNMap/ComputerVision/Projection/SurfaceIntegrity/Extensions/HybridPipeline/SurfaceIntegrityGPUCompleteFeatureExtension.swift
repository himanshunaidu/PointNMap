import Foundation
import Metal
import PointNMapShaderTypes

public extension SurfaceIntegrityProcessor {
    func computeCompleteGPUWindowFeatures(
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData],
        membership: SlidingWindowMembershipGPU,
        retainedWindowIndices: [Int],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault
    ) throws -> SurfaceIntegrityGPUWindowFeatureResult {
        let intermediate = try computeGPUWindowFeatureIntermediate(
            surfaceDetails: surfaceDetails,
            heightResiduals: heightResiduals,
            signedTiltData: signedTiltData,
            membership: membership,
            configuration: configuration
        )
        let plan = try Self.makeGPUOrderStatisticPlan(configuration: configuration)
        let orderStatistics = try computeGPUWeightedSelections(
            surfaceDetails: surfaceDetails,
            heightResiduals: heightResiduals,
            signedTiltData: signedTiltData,
            membership: membership,
            plan: plan
        )
        guard retainedWindowIndices.allSatisfy({ $0 >= 0 && $0 < membership.windowCount }) else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }

        let columns = configuration.allColumns
        var matrix: [Float] = []
        matrix.reserveCapacity(retainedWindowIndices.count * columns.count)
        for originalWindow in retainedWindowIndices {
            var values = Dictionary(uniqueKeysWithValues: columns.map { ($0, Float.zero) })
            values[.heightFromGround] = heightFromGround ?? .nan
            let global = intermediate.reductions[originalWindow * 6]
            if global.count > 0 {
                for group in configuration.featureGroups {
                    let source = Self.sourceIndex(group.source)
                    let reduction = intermediate.reductions[originalWindow * 6 + source]
                    let count = Float(reduction.count)
                    let variance = max(reduction.centeredMoment2Sum / count, 0)
                    let third = reduction.centeredMoment3Sum / count
                    let fourth = reduction.centeredMoment4Sum / count
                    for feature in group.centralTendencyFeatures {
                        let column = SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)")
                        switch feature {
                        case .mean: values[column] = reduction.mean
                        case .standardDeviation: values[column] = sqrt(variance)
                        case .median, .medianAbsoluteDeviation: break
                        }
                    }
                    for shape in group.distributionShapeFeatures {
                        let column = SurfaceIntegrityWindowFeature("\(group.label)_\(shape.rawValue)")
                        switch shape {
                        case .skewness: values[column] = variance > 0 ? third / pow(variance, 1.5) : 0
                        case .kurtosis: values[column] = variance > 0 ? fourth / (variance * variance) - 3 : 0
                        case .entropy: values[column] = intermediate.entropies[originalWindow * 6 + source]
                        }
                    }
                    let tailStart = group.centralTendencyFeatures.count + group.percentileFeatures.count
                    for tailIndex in group.tailFeatures.indices {
                        let column = group.columns[tailStart + tailIndex]
                        if let descriptor = intermediate.tailColumns.firstIndex(of: column) {
                            values[column] = intermediate.tailValues[
                                originalWindow * intermediate.tailColumns.count + descriptor
                            ]
                        }
                    }
                }
                values[.numberOfPolygons] = Float(global.count)
                values[.totalSidewalkArea] = global.totalArea
                values[.averagePolygonArea] = global.totalArea / Float(global.count)
                values[.polygonDensity] = global.totalArea > 0
                    ? Float(global.count) / global.totalArea : 0
            }
            for (slot, descriptor) in plan.primaryDescriptors.enumerated()
                where descriptor.destinationFeatureSlot != UInt32.max {
                values[columns[Int(descriptor.destinationFeatureSlot)]] =
                    orderStatistics.primaryValues[originalWindow * plan.primaryDescriptors.count + slot]
            }
            for (slot, descriptor) in plan.madDescriptors.enumerated() {
                values[columns[Int(descriptor.destinationFeatureSlot)]] =
                    orderStatistics.madValues[originalWindow * plan.madDescriptors.count + slot]
            }
            matrix.append(contentsOf: columns.map { values[$0] ?? 0 })
        }
        guard let buffer = device.makeBuffer(
            bytes: matrix,
            length: max(matrix.count * MemoryLayout<Float>.stride, 1),
            options: .storageModeShared
        ) else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        var timings = intermediate.timings
        timings.orderStatisticsMilliseconds = orderStatistics.selectionMilliseconds
        timings.totalMilliseconds += orderStatistics.selectionMilliseconds
        return SurfaceIntegrityGPUWindowFeatureResult(
            originalWindowCount: membership.windowCount,
            featureStride: columns.count,
            valuesBuffer: buffer,
            values: matrix,
            supportedColumns: Set(columns),
            timings: timings
        )
    }
}
