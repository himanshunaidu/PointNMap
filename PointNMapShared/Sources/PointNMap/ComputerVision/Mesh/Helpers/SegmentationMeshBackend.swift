//
//  SegmentationMeshBackend.swift
//  PointNMap
//
//  Created by Himanshu on 8/17/26.
//
import Foundation
import RealityKit
import CoreImage

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
