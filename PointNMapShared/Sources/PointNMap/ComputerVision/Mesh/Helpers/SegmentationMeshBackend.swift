//
//  SegmentationMeshBackend.swift
//  PointNMap
//
//  Created by Himanshu on 8/17/26.
//
import Foundation
import RealityKit
import CoreImage
import UIKit
import PointNMapShaderTypes

@MainActor
public protocol SegmentationMeshBackend: AnyObject {

    var entity: ModelEntity { get }

    var vertexCount: Int { get }
    var indexCount: Int { get }

    var supportsLiveUpdates: Bool { get }

    func replace(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws

    func update(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws
}

public struct LegacyMeshResourceResult {
    let meshResource: MeshResource?
    let vertexCount: Int
    let indexCount: Int
}

@MainActor
public final class LegacySegmentationMeshBackend: SegmentationMeshBackend {
    public let entity: ModelEntity
    
    public private(set) var vertexCount: Int = 0
    public private(set) var indexCount: Int = 0
    
    public let supportsLiveUpdates: Bool = false
    
    public let processor: SegmentationMeshProcessor
    
    private let material: UnlitMaterial
    private let name: String
    
    init(
        processor: SegmentationMeshProcessor,
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        color: UIColor,
        opacity: Float,
        name: String
    ) throws {
        self.processor = processor
        self.name = name
        
        self.material = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
        
        let entity = ModelEntity()
        entity.name = name
        self.entity = entity
        
        try replace(
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics
        )
    }
    
    public func replace(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws {
        let result = try Self.generateMeshResource(
            processor: processor,
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            name: name
        )
        vertexCount = result.vertexCount
        indexCount = result.indexCount
        
        guard let meshResource = result.meshResource else {
            entity.model = nil
            return
        }
        entity.model = ModelComponent(
            mesh: meshResource,
            materials: [material]
        )
    }
    
    /// - Warning: This method is intentionally unsupported for the legacy backend.
    public func update(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws {
        // Intentionally unsupported.
        //
        // SegmentationMeshRecord.update() should prevent this
        // from being called on the legacy backend.
    }
    
    private static func generateMeshResource(
        processor: SegmentationMeshProcessor,
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        name: String
    ) throws -> LegacyMeshResourceResult {
        let capacity = requiredCapacity(meshGPUSnapshot: meshGPUSnapshot)
        
        let outputVertexBuffer = try MetalBufferUtils.makeBuffer(
            device: processor.context.device,
            length: capacity.vertexCount * MeshGPUCanonicalLayout.vertexStride,
            options: .storageModeShared
        )
        let outputIndexBuffer = try MetalBufferUtils.makeBuffer(
            device: processor.context.device,
            length: capacity.indexCount * MeshGPUCanonicalLayout.indexStride,
            options: .storageModeShared
        )
        
        guard let commandBuffer = processor.context.commandQueue.makeCommandBuffer() else {
            throw SegmentationMeshRecordError.metalPipelineCreationError
        }
        
        let result = try processor.process(
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            commandBuffer: commandBuffer,
            outputVertexBuffer: outputVertexBuffer,
            outputIndexBuffer: outputIndexBuffer
        )
        guard result.triangleCount > 0 else {
            return LegacyMeshResourceResult(
                meshResource: nil,
                vertexCount: 0,
                indexCount: 0
            )
        }
        
        let positions = extractPositions(
            from: outputVertexBuffer,
            count: result.vertexCount,
        )
        let indices = extractIndices(
            from: outputIndexBuffer,
            count: result.indexCount
        )
        
        var descriptor = MeshDescriptor(name: name)
        
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        
        let meshResource = try MeshResource.generate(from: [descriptor])
        
        return LegacyMeshResourceResult(
            meshResource: meshResource,
            vertexCount: result.vertexCount,
            indexCount: result.indexCount
        )
    }
    
    private static func extractPositions(
        from buffer: MTLBuffer,
        count: Int
    ) -> [SIMD3<Float>] {
        guard count > 0 else {
            return []
        }
        let pointer = buffer.contents().bindMemory(to: packed_float3.self, capacity: count)
        let packedPositions = UnsafeBufferPointer(start: pointer, count: count)
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(count)

        for position in packedPositions {
            positions.append(SIMD3<Float>(position.x, position.y, position.z))
        }
        return positions
    }
    
    private static func extractIndices(
        from buffer: MTLBuffer,
        count: Int
    ) -> [UInt32] {
        guard count > 0 else {
            return []
        }
        let pointer = buffer.contents().bindMemory(to: UInt32.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
    
    private struct RequiredCapacity {
        let vertexCount: Int
        let indexCount: Int
    }


    private static func requiredCapacity(meshGPUSnapshot: MeshGPUSnapshot) -> RequiredCapacity {
        let totalFaceCount = meshGPUSnapshot.anchors.values.reduce(0) { $0 + $1.faceCount }
        /// processMesh creates three independent vertices for every accepted triangle.
        /// Use a minimum of one triangle so that zero-sized Metal buffers are never requested.
        let maximumTriangleCount = max(totalFaceCount, 1)
        return RequiredCapacity(
            vertexCount: maximumTriangleCount * 3,
            indexCount: maximumTriangleCount * 3
        )
    }
}

@available(iOS 18.0, *)
@MainActor
public final class ModernSegmentationMeshBackend: SegmentationMeshBackend {

    public let entity: ModelEntity

    public var vertexCount: Int = 0
    public var indexCount: Int = 0

    public let supportsLiveUpdates = true

    public let processor: SegmentationMeshProcessor

    public var mesh: LowLevelMesh
    
    private let name: String
    private static let capacityMultiplier: Int = 10

    init(
        processor: SegmentationMeshProcessor,
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        color: UIColor,
        opacity: Float,
        name: String
    ) throws {
        self.processor = processor
        self.name = name

        let descriptor = Self.createDescriptor(meshGPUSnapshot: meshGPUSnapshot)
        self.mesh = try LowLevelMesh(descriptor: descriptor)

        let resource = try MeshResource(from: mesh)

        var material = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
        material.triangleFillMode = .fill

        let entity = ModelEntity(
            mesh: resource,
            materials: [material]
        )
        entity.name = name
        self.entity = entity

        try replace(
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics
        )
    }

    public func replace(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws {
        try update(
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics
        )
    }

    public func update(
        meshGPUSnapshot: MeshGPUSnapshot,
        segmentationImage: CIImage,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3
    ) throws {
        let requiredCapacity = Self.requiredCapacity(meshGPUSnapshot: meshGPUSnapshot)

        // Preserve your existing LowLevelMesh capacity logic.
        if mesh.descriptor.vertexCapacity < requiredCapacity.vertexCount ||
            mesh.descriptor.indexCapacity < requiredCapacity.indexCount {
            let meshName = self.name.replacingOccurrences(of: " ", with: "_")
            print("SegmentationMeshRecord '\(meshName)' capacity exceeded. Reallocating mesh.")
            let descriptor = Self.createDescriptor(meshGPUSnapshot: meshGPUSnapshot)
            let newMesh = try LowLevelMesh(descriptor: descriptor)
            self.mesh = newMesh
            entity.model?.mesh = try MeshResource(from: mesh)
        }

        guard let commandBuffer = processor.context.commandQueue.makeCommandBuffer() else {
            throw SegmentationMeshRecordError.metalPipelineCreationError
        }

        // This is the only backend that obtains output buffers
        // directly from RealityKit.
        let outputVertexBuffer = mesh.replace(bufferIndex: 0, using: commandBuffer)
        let outputIndexBuffer = mesh.replaceIndices(using: commandBuffer)

        let result = try processor.process(
            meshGPUSnapshot: meshGPUSnapshot,
            segmentationImage: segmentationImage,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            commandBuffer: commandBuffer,
            outputVertexBuffer: outputVertexBuffer,
            outputIndexBuffer: outputIndexBuffer
        )
        try updateMeshParts(result: result)

        vertexCount = result.vertexCount
        indexCount = result.indexCount
    }
    
    private func updateMeshParts(
        result: SegmentationMeshProcessingResult
    ) throws {
        guard result.indexCount > 0 else {
            mesh.parts.replaceAll([])
            return
        }
        let bounds = BoundingBox(
            min: result.aabbMin,
            max: result.aabbMax
        )
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexOffset: 0,
                indexCount: result.indexCount,
                topology: .triangle,
                materialIndex: 0,
                bounds: bounds
            )
        ])
    }
    
    private struct RequiredCapacity {
        let vertexCount: Int
        let indexCount: Int
    }
    
    private static func requiredCapacity(
        meshGPUSnapshot: MeshGPUSnapshot
    ) -> RequiredCapacity {
        let totalFaceCount = meshGPUSnapshot.anchors.values.reduce(0) { $0 + $1.faceCount }
        /// A nonzero minimum avoids creating zero-capacity LowLevelMesh buffers.
        /// The actual result may still contain zero triangles.
        let maximumTriangleCount = max(totalFaceCount, 1)
        return RequiredCapacity(
            vertexCount: maximumTriangleCount * 3,
            indexCount: maximumTriangleCount * 3
        )
    }

    private static func createDescriptor(
        meshGPUSnapshot: MeshGPUSnapshot
    ) -> LowLevelMesh.Descriptor {
        let requiredCapacity = self.requiredCapacity(
            meshGPUSnapshot: meshGPUSnapshot
        )
        var descriptor = LowLevelMesh.Descriptor()

        /*
         MARK: This describes the OUTPUT of processMesh:
         device packed_float3* outVertices
         It does NOT describe the original ARKit vertex layout.
         processMesh writes tightly packed packed_float3 values beginning at byte offset 0.
         */
        descriptor.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MeshGPUCanonicalLayout.vertexOffset)
        ]
        descriptor.vertexLayouts = [
            .init(bufferIndex: 0, bufferStride: MeshGPUCanonicalLayout.vertexStride)
        ]
        descriptor.indexType = .uint32

        // Preserve the original overallocation strategy to reduce
        // reallocation frequency during live updates.
        descriptor.vertexCapacity = requiredCapacity.vertexCount * capacityMultiplier
        descriptor.indexCapacity = requiredCapacity.indexCount * capacityMultiplier
        
        return descriptor
    }
}
