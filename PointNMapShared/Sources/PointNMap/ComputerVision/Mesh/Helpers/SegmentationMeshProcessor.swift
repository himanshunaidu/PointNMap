//
//  SegmentationMeshProcessor.swift
//  PointNMap
//
//  Created by Himanshu on 8/17/26.
//
import Foundation
import Metal
import CoreImage
import simd
import PointNMapShaderTypes
import RealityKit

struct SegmentationMeshProcessingResult {
    let triangleCount: Int
    let vertexCount: Int
    let indexCount: Int

    let aabbMin: SIMD3<Float>
    let aabbMax: SIMD3<Float>

    let debugCounts: [UInt32]
}

@MainActor
public final class SegmentationMeshProcessor {

    let context: MetalContext
    let pipelineState: MTLComputePipelineState

    let accessibilityFeatureMeshClassificationParams: AccessibilityFeatureMeshClassificationParams

    init(
        context: MetalContext,
        accessibilityFeatureMeshClassificationParams: AccessibilityFeatureMeshClassificationParams
    ) throws {
        self.context = context
        self.accessibilityFeatureMeshClassificationParams = accessibilityFeatureMeshClassificationParams

        let library = try context.device.makeDefaultLibrary(
            bundle: PointNMapSharedResources.bundle
        )

        guard let kernelFunction = library.makeFunction(name: "processMesh")
        else {
            throw SegmentationMeshRecordError.metalInitializationError
        }

        self.pipelineState = try context.device.makeComputePipelineState(function: kernelFunction)
    }

    /// Shared mesh-classification operation.
    ///
    /// The important change is that this no longer knows anything about
    /// LowLevelMesh. It simply receives ordinary Metal destination buffers.
    func process(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,

        commandBuffer: MTLCommandBuffer,

        outputVertexBuffer: MTLBuffer,
        outputIndexBuffer: MTLBuffer
    ) throws -> SegmentationMeshProcessingResult {
        let meshGPUAnchors = meshGPUSnapshot.anchors
        
        let totalFaceCount = meshGPUAnchors.reduce(0) { $0 + $1.value.faceCount }
        let maxTriangles   = max(totalFaceCount, 1)     // avoid 0-sized buffers
//        let maxVerts       = maxTriangles * 3
//        let maxIndices     = maxTriangles * 3
        
        let outTriCount: MTLBuffer = try MetalBufferUtils.makeBuffer(
            device: self.context.device, length: MemoryLayout<UInt32>.stride, options: .storageModeShared
        )
        // For debugging
        let debugSlots = Int(3) // MARK: Hard-coded
        let debugBytes = debugSlots * MemoryLayout<UInt32>.stride
        let debugCounter: MTLBuffer = try MetalBufferUtils.makeBuffer(
            device: self.context.device, length: debugBytes, options: .storageModeShared
        )
        
        let aabbMinU = try MetalBufferUtils.makeBuffer(
            device: self.context.device, length: 3 * MemoryLayout<UInt32>.stride, options: .storageModeShared
        )
        let aabbMaxU = try MetalBufferUtils.makeBuffer(
            device: self.context.device, length: 3 * MemoryLayout<UInt32>.stride, options: .storageModeShared
        )
        do {
            let minPtr = aabbMinU.contents().bindMemory(to: UInt32.self, capacity: 3)
            let maxPtr = aabbMaxU.contents().bindMemory(to: UInt32.self, capacity: 3)
            let fMax: Float = .greatestFiniteMagnitude
            let fMin: Float = -Float.greatestFiniteMagnitude
            let initMin = floatToOrderedUInt(fMax)
            let initMax = floatToOrderedUInt(fMin)
            minPtr[0] = initMin; minPtr[1] = initMin; minPtr[2] = initMin
            maxPtr[0] = initMax; maxPtr[1] = initMax; maxPtr[2] = initMax
        }
        
        // Set up additional parameters
        let viewMatrix = simd_inverse(cameraTransform)
        let imageSize = simd_uint2(UInt32(segmentationImage.extent.width), UInt32(segmentationImage.extent.height))
        // Set up the Metal command buffer
        guard let commandBuffer = self.context.commandQueue.makeCommandBuffer() else {
            throw SegmentationMeshRecordError.metalPipelineCreationError
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else {
            throw SegmentationMeshRecordError.meshPipelineBlitEncoderError
        }
        blit.fill(buffer: outTriCount, range: 0..<MemoryLayout<UInt32>.stride, value: 0)
        blit.fill(buffer: debugCounter, range: 0..<debugBytes, value: 0)
        blit.endEncoding()
        let threadGroupSizeWidth = min(self.pipelineState.maxTotalThreadsPerThreadgroup, 256)
        
//        let outVertexBuf = mesh.replace(bufferIndex: 0, using: commandBuffer)
//        let outIndexBuf = mesh.replaceIndices(using: commandBuffer)
        
        let segmentationTexture = try segmentationImage.toMTLTexture(
            device: self.context.device, commandBuffer: commandBuffer, pixelFormat: .r8Unorm,
            context: self.context.ciContextNoColorSpace,
            colorSpace: CGColorSpaceCreateDeviceRGB(), /// Dummy color space to avoid warnings
            cIImageToMTLTextureOrientation: .metalTopLeft
        )
        
        var accessibilityFeatureMeshClassificationParams = self.accessibilityFeatureMeshClassificationParams
        
        for (_, anchor) in meshGPUSnapshot.anchors {
            guard anchor.faceCount > 0 else { continue }
            
            let hasClass: UInt32 = anchor.classificationBuffer != nil ? 1 : 0
            var params = MeshParams(
                faceCount: UInt32(anchor.faceCount), totalCount: UInt32(totalFaceCount),
                indicesPerFace: 3, hasClass: hasClass,
                anchorTransform: anchor.anchorTransform, cameraTransform: cameraTransform,
                viewMatrix: viewMatrix, intrinsics: cameraIntrinsics, imageSize: imageSize
            )
            guard let commandEncoder = commandBuffer.makeComputeCommandEncoder() else {
                throw SegmentationMeshRecordError.metalPipelineCreationError
            }
            commandEncoder.setComputePipelineState(self.pipelineState)
            // Main inputs
            commandEncoder.setBuffer(anchor.vertexBuffer, offset: 0, index: 0)
            commandEncoder.setBuffer(anchor.indexBuffer, offset: 0, index: 1)
            commandEncoder.setBuffer(anchor.classificationBuffer ?? nil, offset: 0, index: 2)
            commandEncoder.setBytes(&params, length: MemoryLayout<MeshParams>.stride, index: 3)
            commandEncoder.setBytes(&accessibilityFeatureMeshClassificationParams,
                                    length: MemoryLayout<AccessibilityFeatureMeshClassificationParams>.stride, index: 4)
            commandEncoder.setTexture(segmentationTexture, index: 0)
            // Main outputs
//            commandEncoder.setBuffer(outVertexBuf, offset: 0, index: 5)
//            commandEncoder.setBuffer(outIndexBuf,  offset: 0, index: 6)
            commandEncoder.setBuffer(outputVertexBuffer, offset: 0, index: 5)
            commandEncoder.setBuffer(outputIndexBuffer,  offset: 0, index: 6)
            commandEncoder.setBuffer(outTriCount,  offset: 0, index: 7)
            
            commandEncoder.setBuffer(aabbMinU, offset: 0, index: 8)
            commandEncoder.setBuffer(aabbMaxU, offset: 0, index: 9)
            commandEncoder.setBuffer(debugCounter, offset: 0, index: 10)
            
            let threadGroupSize = MTLSize(width: threadGroupSizeWidth, height: 1, depth: 1)
            let threadGroups = MTLSize(
                width: (anchor.faceCount + threadGroupSize.width - 1) / threadGroupSize.width, height: 1, depth: 1
            )
            commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
            commandEncoder.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let triCount = outTriCount.contents().bindMemory(to: UInt32.self, capacity: 1).pointee
        // Clamp to capacity (defensive)
        let triangleCount = min(Int(triCount), maxTriangles)
        let vertexCount   = triangleCount * 3
        let indexCount    = triangleCount * 3

        let minU = aabbMinU.contents().bindMemory(to: UInt32.self, capacity: 3)
        let maxU = aabbMaxU.contents().bindMemory(to: UInt32.self, capacity: 3)
        let aabbMin = SIMD3<Float>(
            orderedUIntToFloat(minU[0]),
            orderedUIntToFloat(minU[1]),
            orderedUIntToFloat(minU[2])
        )
        let aabbMax = SIMD3<Float>(
            orderedUIntToFloat(maxU[0]),
            orderedUIntToFloat(maxU[1]),
            orderedUIntToFloat(maxU[2])
        )
        let bounds: BoundingBox = BoundingBox(min: aabbMin, max: aabbMax)
        
        let debugCountPointer = debugCounter.contents().bindMemory(to: UInt32.self, capacity: debugSlots)
        var debugCountValue: [UInt32] = []
        for i in 0..<debugSlots {
            debugCountValue.append(debugCountPointer.advanced(by: i).pointee)
        }
        
        return SegmentationMeshProcessingResult(
            triangleCount: triangleCount,
            vertexCount: vertexCount,
            indexCount: indexCount,
            aabbMin: aabbMin,
            aabbMax: aabbMax,
            debugCounts: debugCountValue
        )
    }
    
    @inline(__always)
    private func floatToOrderedUInt(_ f: Float) -> UInt32 {
        let u = f.bitPattern
        return (u & 0x8000_0000) != 0 ? ~u : (u | 0x8000_0000)
    }

    @inline(__always)
    private func orderedUIntToFloat(_ u: UInt32) -> Float {
        let raw = (u & 0x8000_0000) != 0 ? (u & ~0x8000_0000) : ~u
        return Float(bitPattern: raw)
    }
}
