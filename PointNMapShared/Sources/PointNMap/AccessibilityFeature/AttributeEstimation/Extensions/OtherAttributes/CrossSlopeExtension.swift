//
//  CrossSlopeExtension.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/2/26.
//

import SwiftUI
import CoreLocation
import PointNMapShaderTypes

public extension AttributeEstimationPipeline {
    func calculateCrossSlope(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        let isMeshEnabled: Bool = self.captureMeshData != nil
        if isMeshEnabled {
            return try self.calculateCrossSlopeFromMesh(accessibilityFeature: accessibilityFeature)
        }
        return try self.calculateCrossSlopeFromImage(accessibilityFeature: accessibilityFeature)
    }
    
    func calculateCrossSlopeFromImage(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        let worldPoints: [WorldPoint] = try self.getCachedWorldPoints(
            accessibilityFeature: accessibilityFeature
        )
        let alignedPlane: Plane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, worldPoints: worldPoints
        )
        let crossVector = simd_normalize(alignedPlane.secondVector)
        let gravityVector = SIMD3<Float>(0, 1, 0)
        let rise = simd_dot(crossVector, gravityVector)
        let crossHorizontalVector = crossVector - (rise * gravityVector)
        let run = simd_length(crossHorizontalVector)
        let slopeRadians = atan2(rise, run)
        let slopeDegrees: Double = Double(abs(slopeRadians * (180.0 / .pi)))
        
        guard let crossSlopeAttributeValue = AccessibilityFeatureAttribute.crossSlope.value(from: slopeDegrees) else {
            throw AttributeEstimationPipelineError.attributeAssignmentError
        }
        return crossSlopeAttributeValue
    }
    
    func calculateCrossSlopeFromMesh(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        /// TODO: For optimization, replace the usage of meshPolygons with meshTriangles (GPU-based)
        let meshPolygons: [MeshPolygon] = try self.getCachedMeshContents(
            accessibilityFeature: accessibilityFeature
        ).polygons
        let alignedPlane: Plane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, meshPolygons: meshPolygons
        )
        let crossVector = simd_normalize(alignedPlane.secondVector)
        let gravityVector = SIMD3<Float>(0, 1, 0)
        let rise = simd_dot(crossVector, gravityVector)
        let crossHorizontalVector = crossVector - (rise * gravityVector)
        let run = simd_length(crossHorizontalVector)
        let slopeRadians = atan2(rise, run)
        let slopeDegrees: Double = Double(abs(slopeRadians * (180.0 / .pi)))
        
        guard let crossSlopeAttributeValue = AccessibilityFeatureAttribute.crossSlope.value(from: slopeDegrees) else {
            throw AttributeEstimationPipelineError.attributeAssignmentError
        }
        return crossSlopeAttributeValue
    }
}
