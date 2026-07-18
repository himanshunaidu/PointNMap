//
//  RunninSlopeExtension.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/2/26.
//

import SwiftUI
import CoreLocation
import PointNMapShaderTypes

public extension AttributeEstimationPipeline {
    func calculateRunningSlope(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        let isMeshEnabled: Bool = self.captureMeshData != nil
        if isMeshEnabled {
            return try self.calculateRunningSlopeFromMesh(accessibilityFeature: accessibilityFeature)
        }
        return try self.calculateRunningSlopeFromImage(accessibilityFeature: accessibilityFeature)
    }
    
    /**
     Function to calculate the running slope of the feature.
     
     Assumes that the plane being calculated has its first vector aligned with the direction of travel.
     */
    func calculateRunningSlopeFromImage(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        let worldPoints: [WorldPoint] = try self.getCachedWorldPoints(
            accessibilityFeature: accessibilityFeature
        )
        let alignedPlane: Plane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, worldPoints: worldPoints
        )
        let runningVector = simd_normalize(alignedPlane.firstVector)
        let gravityVector = SIMD3<Float>(0, 1, 0)
        let rise = simd_dot(runningVector, gravityVector)
        let runningHorizontalVector = runningVector - (rise * gravityVector)
        let run = simd_length(runningHorizontalVector)
        let slopeRadians = atan2(rise, run)
        let slopeDegrees: Double = Double(abs(slopeRadians * (180.0 / .pi)))
        
        guard let runningSlopeAttributeValue = AccessibilityFeatureAttribute.runningSlope.value(from: slopeDegrees) else {
            throw AttributeEstimationPipelineError.attributeAssignmentError
        }
        return runningSlopeAttributeValue
    }
    
    func calculateRunningSlopeFromMesh(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> AccessibilityFeatureAttribute.Value {
        /// TODO: For optimization, replace the usage of meshPolygons with meshTriangles (GPU-based)
        let meshPolygons: [MeshPolygon] = try self.getCachedMeshContents(
            accessibilityFeature: accessibilityFeature
        ).polygons
        let alignedPlane: Plane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, meshPolygons: meshPolygons
        )
        let runningVector = simd_normalize(alignedPlane.firstVector)
        let gravityVector = SIMD3<Float>(0, 1, 0)
        let rise = simd_dot(runningVector, gravityVector)
        let runningHorizontalVector = runningVector - (rise * gravityVector)
        let run = simd_length(runningHorizontalVector)
        let slopeRadians = atan2(rise, run)
        let slopeDegrees: Double = Double(abs(slopeRadians * (180.0 / .pi)))
        
        guard let runningSlopeAttributeValue = AccessibilityFeatureAttribute.runningSlope.value(from: slopeDegrees) else {
            throw AttributeEstimationPipelineError.attributeAssignmentError
        }
        return runningSlopeAttributeValue
    }
}
