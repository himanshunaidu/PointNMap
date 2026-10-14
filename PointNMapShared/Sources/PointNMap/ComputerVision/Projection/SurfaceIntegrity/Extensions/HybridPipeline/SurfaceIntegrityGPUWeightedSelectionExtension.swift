import Foundation
import Metal
import PointNMapShaderTypes

public extension SurfaceIntegrityProcessor {
    func computeGPUWeightedSelections(
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData],
        membership: SlidingWindowMembershipGPU,
        plan: SurfaceIntegrityGPUOrderStatisticPlan
    ) throws -> SurfaceIntegrityGPUOrderStatisticIntermediate {
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
        let descriptors = plan.primaryDescriptors
        let madDescriptors = plan.madDescriptors
        guard madDescriptors.allSatisfy({ Int($0.dependencySlot) < descriptors.count }) else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        let outputCount = membership.windowCount * descriptors.count
        let madOutputCount = membership.windowCount * madDescriptors.count
        let polygonLength = max(
            packed.count * MemoryLayout<SurfaceIntegrityPackedPolygonFeaturesGPU>.stride, 1
        )
        let polygonBuffer = packed.isEmpty
            ? device.makeBuffer(length: polygonLength, options: .storageModeShared)
            : device.makeBuffer(bytes: packed, length: polygonLength, options: .storageModeShared)
        guard !descriptors.isEmpty,
              let polygonBuffer,
              let descriptorBuffer = device.makeBuffer(
                bytes: descriptors,
                length: descriptors.count * MemoryLayout<SurfaceIntegrityOrderStatisticDescriptorGPU>.stride,
                options: .storageModeShared
              ),
              let outputBuffer = device.makeBuffer(
                length: outputCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ),
              let statusBuffer = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        statusBuffer.contents().storeBytes(of: UInt32.zero, as: UInt32.self)
        var windowCount = UInt32(membership.windowCount)
        var polygonCount = UInt32(surfaceDetails.count)
        var descriptorCount = UInt32(descriptors.count)
        var dependencyStride = descriptorCount
        encoder.setComputePipelineState(surfaceIntegrityWeightedSelectionPipeline)
        encoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
        encoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
        encoder.setBuffer(polygonBuffer, offset: 0, index: 2)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 3)
        encoder.setBytes(&windowCount, length: 4, index: 4)
        encoder.setBytes(&polygonCount, length: 4, index: 5)
        encoder.setBytes(&descriptorCount, length: 4, index: 6)
        encoder.setBuffer(outputBuffer, offset: 0, index: 7)
        encoder.setBuffer(statusBuffer, offset: 0, index: 8)
        encoder.setBuffer(outputBuffer, offset: 0, index: 9)
        encoder.setBytes(&dependencyStride, length: 4, index: 10)
        encoder.dispatchThreadgroups(
            MTLSize(width: membership.windowCount, height: descriptors.count, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
        )
        encoder.endEncoding()
        var madOutputBuffer: MTLBuffer?
        if !madDescriptors.isEmpty {
            guard let madDescriptorBuffer = device.makeBuffer(
                bytes: madDescriptors,
                length: madDescriptors.count * MemoryLayout<SurfaceIntegrityOrderStatisticDescriptorGPU>.stride,
                options: .storageModeShared
            ), let createdMADOutputBuffer = device.makeBuffer(
                length: madOutputCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ), let madEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw SurfaceIntegrityProcessorError.unableToProcessBufferData
            }
            madOutputBuffer = createdMADOutputBuffer
            var madDescriptorCount = UInt32(madDescriptors.count)
            madEncoder.setComputePipelineState(surfaceIntegrityWeightedSelectionPipeline)
            madEncoder.setBuffer(membership.windowOffsetsBuffer, offset: 0, index: 0)
            madEncoder.setBuffer(membership.meshIndicesBuffer, offset: 0, index: 1)
            madEncoder.setBuffer(polygonBuffer, offset: 0, index: 2)
            madEncoder.setBuffer(madDescriptorBuffer, offset: 0, index: 3)
            madEncoder.setBytes(&windowCount, length: 4, index: 4)
            madEncoder.setBytes(&polygonCount, length: 4, index: 5)
            madEncoder.setBytes(&madDescriptorCount, length: 4, index: 6)
            madEncoder.setBuffer(createdMADOutputBuffer, offset: 0, index: 7)
            madEncoder.setBuffer(statusBuffer, offset: 0, index: 8)
            madEncoder.setBuffer(outputBuffer, offset: 0, index: 9)
            madEncoder.setBytes(&dependencyStride, length: 4, index: 10)
            madEncoder.dispatchThreadgroups(
                MTLSize(width: membership.windowCount, height: madDescriptors.count, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1)
            )
            madEncoder.endEncoding()
        }
        let selectionStart = ProcessInfo.processInfo.systemUptime
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed,
              statusBuffer.contents().load(as: UInt32.self) == 0 else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }
        let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: outputCount)
        let madValues: [Float]
        if let madOutputBuffer {
            let pointer = madOutputBuffer.contents().bindMemory(to: Float.self, capacity: madOutputCount)
            madValues = Array(UnsafeBufferPointer(start: pointer, count: madOutputCount))
        } else {
            madValues = []
        }
        return SurfaceIntegrityGPUOrderStatisticIntermediate(
            primaryValuesBuffer: outputBuffer,
            primaryValues: Array(UnsafeBufferPointer(start: pointer, count: outputCount)),
            madValuesBuffer: madOutputBuffer,
            madValues: madValues,
            originalWindowCount: membership.windowCount,
            primaryDescriptorCount: descriptors.count,
            madDescriptorCount: madDescriptors.count,
            selectionMilliseconds: (ProcessInfo.processInfo.systemUptime - selectionStart) * 1_000
        )
    }
}
