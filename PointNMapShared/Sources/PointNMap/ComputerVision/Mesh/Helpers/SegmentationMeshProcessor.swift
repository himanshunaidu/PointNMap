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

@MainActor
public final class SegmentationMeshProcessor {

    let context: MetalContext
    let pipelineState: MTLComputePipelineState

    let classificationParams:
        AccessibilityFeatureMeshClassificationParams

    init(
        context: MetalContext,
        classificationParams:
            AccessibilityFeatureMeshClassificationParams
    ) throws {

        self.context = context
        self.classificationParams = classificationParams

        let library = try context.device.makeDefaultLibrary(
            bundle: PointNMapSharedResources.bundle
        )

        guard let kernelFunction =
            library.makeFunction(name: "processMesh")
        else {
            throw SegmentationMeshRecordError.metalInitializationError
        }

        self.pipelineState =
            try context.device.makeComputePipelineState(
                function: kernelFunction
            )
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

        /*
         MOVE MOST OF THE EXISTING update() IMPLEMENTATION HERE.

         In particular:

         1. Calculate:
              totalFaceCount
              maxTriangles
              maxVerts
              maxIndices

         2. Allocate:
              outTriCount
              debugCounter
              aabbMinU
              aabbMaxU

         3. Create segmentationTexture.

         4. Loop over meshGPUSnapshot.anchors.

         5. Configure processMesh compute encoder.

         Existing:
              commandEncoder.setBuffer(outVertexBuf, index: 5)
              commandEncoder.setBuffer(outIndexBuf,  index: 6)

         Becomes:
              commandEncoder.setBuffer(
                  outputVertexBuffer,
                  offset: 0,
                  index: 5
              )

              commandEncoder.setBuffer(
                  outputIndexBuffer,
                  offset: 0,
                  index: 6
              )

         6. Commit/wait.

         7. Read:
              triangleCount
              vertexCount
              indexCount
              bounds

         8. Return SegmentationMeshProcessingResult.
         */

        fatalError("Move existing shared Metal processing here")
    }
}
