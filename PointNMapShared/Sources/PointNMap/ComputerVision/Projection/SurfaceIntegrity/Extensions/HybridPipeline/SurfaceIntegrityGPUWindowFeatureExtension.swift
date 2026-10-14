import Foundation
import Metal
import PointNMapShaderTypes

public struct SurfaceIntegrityGPUWindowIntermediate: @unchecked Sendable {
    public let reductions: [SurfaceIntegrityWindowReductionGPU]
    public let entropies: [Float]
    public let tailValues: [Float]
    public let tailColumns: [SurfaceIntegrityWindowFeature]
    public let timings: SurfaceIntegrityGPUWindowFeatureTimings
}

public extension SurfaceIntegrityProcessor {
    func computeGPUWindowFeatureIntermediate(
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData],
        membership: SlidingWindowMembershipGPU,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault
    ) throws -> SurfaceIntegrityGPUWindowIntermediate {
        guard surfaceDetails.count == heightResiduals.count,
              surfaceDetails.count == signedTiltData.count else {
            throw SurfaceIntegrityWindowFeatureError.mismatchedInputCounts
        }
        let packed = surfaceDetails.indices.map { index in
            let tilt = signedTiltData[index]
            return SurfaceIntegrityPackedPolygonFeaturesGPU(
                area: surfaceDetails[index].area,
                normalDeviation: surfaceDetails[index].angularDeviationDegrees,
                heightResidual: heightResiduals[index],
                absoluteHeightResidual: abs(heightResiduals[index]),
                signedTiltU: tilt.tiltUDegrees,
                signedTiltV: tilt.tiltVDegrees,
                signedTiltMagnitude: sqrt(
                    tilt.tiltUDegrees * tilt.tiltUDegrees
                        + tilt.tiltVDegrees * tilt.tiltVDegrees
                        + tilt.tiltMagnitudeDegrees * tilt.tiltMagnitudeDegrees
                ),
                reserved: 0
            )
        }
        let packedLength = max(packed.count * MemoryLayout<SurfaceIntegrityPackedPolygonFeaturesGPU>.stride, 1)
        let resultCount = membership.windowCount * SurfaceIntegrityGPUValueSource.allCases.count
        let tails: [(SurfaceIntegrityTailDescriptorGPU, SurfaceIntegrityWindowFeature)] =
            configuration.featureGroups.flatMap { group in
                let tailStart = group.centralTendencyFeatures.count + group.percentileFeatures.count
                return group.tailFeatures.enumerated().map { index, threshold in
                    (
                        SurfaceIntegrityTailDescriptorGPU(
                            source: UInt32(Self.sourceIndex(group.source)), threshold: threshold
                        ),
                        group.columns[tailStart + index]
                    )
                }
            }
        guard let polygonBuffer = packed.isEmpty
                ? device.makeBuffer(length: packedLength, options: .storageModeShared)
                : device.makeBuffer(bytes: packed, length: packedLength, options: .storageModeShared),
              let reductionBuffer = device.makeBuffer(
                length: max(resultCount * MemoryLayout<SurfaceIntegrityWindowReductionGPU>.stride, 1),
                options: .storageModeShared
              ),
              let entropyBuffer = device.makeBuffer(
                length: max(resultCount * MemoryLayout<Float>.stride, 1),
                options: .storageModeShared
              ),
              let histogramBuffer = device.makeBuffer(
                length: max(resultCount * 30 * MemoryLayout<UInt32>.stride, 1),
                options: .storageModeShared
              ) else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        var windowCount = UInt32(membership.windowCount)
        var polygonCount = UInt32(surfaceDetails.count)
        let groupSize = MTLSize(width: 256, height: 1, depth: 1)
        let groups = MTLSize(width: membership.windowCount, height: 6, depth: 1)

        let reductionStart = ProcessInfo.processInfo.systemUptime
        guard let reductionCommand = commandQueue.makeCommandBuffer(),
              let reductionEncoder = reductionCommand.makeComputeCommandEncoder() else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        reductionEncoder.setComputePipelineState(surfaceIntegrityWindowReductionPipeline)
        reductionEncoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
        reductionEncoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
        reductionEncoder.setBuffer(polygonBuffer, offset: 0, index: 2)
        reductionEncoder.setBytes(&windowCount, length: 4, index: 3)
        reductionEncoder.setBytes(&polygonCount, length: 4, index: 4)
        reductionEncoder.setBuffer(reductionBuffer, offset: 0, index: 5)
        reductionEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: groupSize)
        reductionEncoder.endEncoding()
        guard let centeredMomentsEncoder = reductionCommand.makeComputeCommandEncoder() else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        centeredMomentsEncoder.setComputePipelineState(surfaceIntegrityWindowCenteredMomentsPipeline)
        centeredMomentsEncoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
        centeredMomentsEncoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
        centeredMomentsEncoder.setBuffer(polygonBuffer, offset: 0, index: 2)
        centeredMomentsEncoder.setBytes(&windowCount, length: 4, index: 3)
        centeredMomentsEncoder.setBytes(&polygonCount, length: 4, index: 4)
        centeredMomentsEncoder.setBuffer(reductionBuffer, offset: 0, index: 5)
        centeredMomentsEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: groupSize)
        centeredMomentsEncoder.endEncoding()
        reductionCommand.commit()
        reductionCommand.waitUntilCompleted()
        guard reductionCommand.status == .completed else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        let reductionMilliseconds = (ProcessInfo.processInfo.systemUptime - reductionStart) * 1_000

        let entropyStart = ProcessInfo.processInfo.systemUptime
        histogramBuffer.contents().initializeMemory(
            as: UInt8.self,
            repeating: 0,
            count: histogramBuffer.length
        )
        guard let entropyCommand = commandQueue.makeCommandBuffer(),
              let entropyEncoder = entropyCommand.makeComputeCommandEncoder() else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        entropyEncoder.setComputePipelineState(surfaceIntegrityWindowEntropyPipeline)
        entropyEncoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
        entropyEncoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
        entropyEncoder.setBuffer(polygonBuffer, offset: 0, index: 2)
        entropyEncoder.setBuffer(reductionBuffer, offset: 0, index: 3)
        entropyEncoder.setBytes(&windowCount, length: 4, index: 4)
        entropyEncoder.setBytes(&polygonCount, length: 4, index: 5)
        entropyEncoder.setBuffer(entropyBuffer, offset: 0, index: 6)
        entropyEncoder.setBuffer(histogramBuffer, offset: 0, index: 7)
        entropyEncoder.dispatchThreadgroups(groups, threadsPerThreadgroup: groupSize)
        entropyEncoder.endEncoding()
        entropyCommand.commit()
        entropyCommand.waitUntilCompleted()
        guard entropyCommand.status == .completed else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        let entropyMilliseconds = (ProcessInfo.processInfo.systemUptime - entropyStart) * 1_000
        var tailValues: [Float] = []
        if !tails.isEmpty {
            let descriptors = tails.map(\.0)
            let tailValueCount = membership.windowCount * descriptors.count
            guard let descriptorBuffer = device.makeBuffer(
                bytes: descriptors,
                length: descriptors.count * MemoryLayout<SurfaceIntegrityTailDescriptorGPU>.stride,
                options: .storageModeShared
            ), let tailBuffer = device.makeBuffer(
                length: max(tailValueCount * MemoryLayout<Float>.stride, 1),
                options: .storageModeShared
            ), let tailCommand = commandQueue.makeCommandBuffer(),
               let tailEncoder = tailCommand.makeComputeCommandEncoder() else {
                throw SurfaceIntegrityProcessorError.unableToProcessBufferData
            }
            var descriptorCount = UInt32(descriptors.count)
            tailEncoder.setComputePipelineState(surfaceIntegrityWindowTailPipeline)
            tailEncoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
            tailEncoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
            tailEncoder.setBuffer(polygonBuffer, offset: 0, index: 2)
            tailEncoder.setBuffer(descriptorBuffer, offset: 0, index: 3)
            tailEncoder.setBytes(&windowCount, length: 4, index: 4)
            tailEncoder.setBytes(&polygonCount, length: 4, index: 5)
            tailEncoder.setBytes(&descriptorCount, length: 4, index: 6)
            tailEncoder.setBuffer(tailBuffer, offset: 0, index: 7)
            tailEncoder.dispatchThreadgroups(
                MTLSize(width: membership.windowCount, height: descriptors.count, depth: 1),
                threadsPerThreadgroup: groupSize
            )
            tailEncoder.endEncoding()
            tailCommand.commit()
            tailCommand.waitUntilCompleted()
            guard tailCommand.status == .completed else {
                throw SurfaceIntegrityProcessorError.unableToProcessBufferData
            }
            let pointer = tailBuffer.contents().bindMemory(to: Float.self, capacity: tailValueCount)
            tailValues = Array(UnsafeBufferPointer(start: pointer, count: tailValueCount))
        }
        let reductionPointer = reductionBuffer.contents().bindMemory(
            to: SurfaceIntegrityWindowReductionGPU.self, capacity: resultCount
        )
        let entropyPointer = entropyBuffer.contents().bindMemory(to: Float.self, capacity: resultCount)
        return SurfaceIntegrityGPUWindowIntermediate(
            reductions: Array(UnsafeBufferPointer(start: reductionPointer, count: resultCount)),
            entropies: Array(UnsafeBufferPointer(start: entropyPointer, count: resultCount)),
            tailValues: tailValues,
            tailColumns: tails.map(\.1),
            timings: .init(
                reductionMilliseconds: reductionMilliseconds,
                entropyMilliseconds: entropyMilliseconds
            )
        )
    }

    func processStagedWindowFeatures(
        intermediate: SurfaceIntegrityGPUWindowIntermediate,
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData],
        membershipCSR: SlidingWindowMembershipCSR,
        retainedWindowIndices: [Int],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault
    ) throws -> SurfaceIntegrityStagedWindowFeatureResult {
        let totalStart = ProcessInfo.processInfo.systemUptime
        guard intermediate.reductions.count == membershipCSR.windowCount * 6,
              intermediate.entropies.count == membershipCSR.windowCount * 6,
              retainedWindowIndices.allSatisfy({ $0 >= 0 && $0 < membershipCSR.windowCount }) else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        var supported = Set(SurfaceIntegrityFeatureConfiguration.globalColumns.filter { $0 != .heightFromGround })
        for group in configuration.featureGroups {
            for feature in group.centralTendencyFeatures where feature != .median && feature != .medianAbsoluteDeviation {
                supported.insert(SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)"))
            }
            for feature in group.distributionShapeFeatures {
                supported.insert(SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)"))
            }
        }
        supported.formUnion(intermediate.tailColumns)
        let orderStart = ProcessInfo.processInfo.systemUptime
        var output: [SurfaceIntegrityWindowFeatures] = []
        output.reserveCapacity(retainedWindowIndices.count)
        for originalWindow in retainedWindowIndices {
            let start = Int(membershipCSR.windowOffsets[originalWindow])
            let end = Int(membershipCSR.windowOffsets[originalWindow + 1])
            let indices = membershipCSR.meshIndices[start..<end].map(Int.init).sorted()
            var values = Dictionary(uniqueKeysWithValues: configuration.allColumns.map { ($0, Float.zero) })
            values[.heightFromGround] = heightFromGround ?? .nan
            if !indices.isEmpty {
                let areas = indices.map { surfaceDetails[$0].area }
                for group in configuration.featureGroups {
                    let sourceValues = Self.gpuSourceValues(
                        group.source, indices: indices, surfaceDetails: surfaceDetails,
                        heightResiduals: heightResiduals, signedTiltData: signedTiltData
                    )
                    let reduction = intermediate.reductions[originalWindow * 6 + Self.sourceIndex(group.source)]
                    let mean = reduction.mean
                    let variance = max(
                        reduction.centeredMoment2Sum / Float(reduction.count), 0
                    )
                    let third = reduction.centeredMoment3Sum / Float(reduction.count)
                    let fourth = reduction.centeredMoment4Sum / Float(reduction.count)
                    for feature in group.centralTendencyFeatures {
                        let key = SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)")
                        switch feature {
                        case .mean: values[key] = mean
                        case .standardDeviation: values[key] = sqrt(variance)
                        case .median:
                            values[key] = Self.weightedMedian(values: sourceValues, weights: areas)
                        case .medianAbsoluteDeviation:
                            let result = Self.weightedMedianAbsoluteDeviation(values: sourceValues, weights: areas)
                            values[key] = result.isNaN ? 0 : result
                        }
                    }
                    for percentile in group.percentileFeatures {
                        values[SurfaceIntegrityWindowFeature("\(group.label)_p\(percentile)")] =
                            Self.weightedPercentile(values: sourceValues, weights: areas, percentile: Float(percentile))
                    }
                    let groupColumns = group.columns
                    let tailStart = group.centralTendencyFeatures.count + group.percentileFeatures.count
                    for (tailIndex, tail) in group.tailFeatures.enumerated() {
                        let column = groupColumns[tailStart + tailIndex]
                        if let descriptorIndex = intermediate.tailColumns.firstIndex(of: column) {
                            values[column] = intermediate.tailValues[
                                originalWindow * intermediate.tailColumns.count + descriptorIndex
                            ]
                        } else {
                            values[column] = Self.weightedProportion(
                                mask: sourceValues.map { $0 > tail }, weights: areas
                            )
                        }
                    }
                    for shape in group.distributionShapeFeatures {
                        let key = SurfaceIntegrityWindowFeature("\(group.label)_\(shape.rawValue)")
                        switch shape {
                        case .skewness:
                            values[key] = variance > 0 ? third / pow(variance, 1.5) : 0
                        case .kurtosis:
                            values[key] = variance > 0 ? fourth / (variance * variance) - 3 : 0
                        case .entropy:
                            values[key] = intermediate.entropies[originalWindow * 6 + Self.sourceIndex(group.source)]
                        }
                    }
                }
                let global = intermediate.reductions[originalWindow * 6]
                values[.numberOfPolygons] = Float(global.count)
                values[.totalSidewalkArea] = global.totalArea
                values[.averagePolygonArea] = global.totalArea / Float(global.count)
                values[.polygonDensity] = global.totalArea > 0 ? Float(global.count) / global.totalArea : 0
            }
            output.append(.init(values: values, orderedColumns: configuration.allColumns))
        }
        let totalMilliseconds = (ProcessInfo.processInfo.systemUptime - totalStart) * 1_000
        var timings = intermediate.timings
        timings.orderStatisticsMilliseconds = (ProcessInfo.processInfo.systemUptime - orderStart) * 1_000
        timings.totalMilliseconds = totalMilliseconds + timings.reductionMilliseconds + timings.entropyMilliseconds
        return .init(features: output, supportedColumns: supported, timings: timings)
    }
}

extension SurfaceIntegrityProcessor {
    static func sourceIndex(_ source: SurfaceIntegrityFeatureValueSource) -> Int {
        switch source {
        case .normalDeviation: 0
        case .heightResidual: 1
        case .absoluteHeightResidual: 2
        case .signedTiltU: 3
        case .signedTiltV: 4
        case .signedTiltMagnitude: 5
        }
    }

    static func gpuSourceValues(
        _ source: SurfaceIntegrityFeatureValueSource,
        indices: [Int],
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData]
    ) -> [Float] {
        indices.map { index in
            switch source {
            case .normalDeviation: return surfaceDetails[index].angularDeviationDegrees
            case .heightResidual: return heightResiduals[index]
            case .absoluteHeightResidual: return abs(heightResiduals[index])
            case .signedTiltU: return signedTiltData[index].tiltUDegrees
            case .signedTiltV: return signedTiltData[index].tiltVDegrees
            case .signedTiltMagnitude:
                let tilt = signedTiltData[index]
                return sqrt(tilt.tiltUDegrees * tilt.tiltUDegrees
                    + tilt.tiltVDegrees * tilt.tiltVDegrees
                    + tilt.tiltMagnitudeDegrees * tilt.tiltMagnitudeDegrees)
            }
        }
    }
}
