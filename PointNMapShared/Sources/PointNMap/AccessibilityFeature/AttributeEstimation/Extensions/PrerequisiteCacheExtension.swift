//
//  PrerequisiteCacheExtension.swift
//  PointNMap
//
//  Created by Himanshu on 6/26/26.
//

import SwiftUI
import Combine
import CoreLocation
import MapKit
import PointNMapShaderTypes

public extension AttributeEstimationPipeline {
    struct PrerequisiteCache: Sendable {
        public var worldPoints: [WorldPoint]? = nil
        public var worldPointsGrid: WorldPointsGrid? = nil
        public var pointAlignedPlane: Plane? = nil
        public var pointProjectedPlane: ProjectedPlane? = nil
        public var meshContents: MeshContents? = nil
        public var meshAlignedPlane: Plane? = nil
        public var meshProjectedPlane: ProjectedPlane? = nil
        
        /// Additional lazy properties for caching can be added here as needed.
        public var surfaceNormalsGrid: SurfaceNormalsForPointsGrid? = nil
        
        mutating func getOrCompute<T>(
            _ keyPath: WritableKeyPath<PrerequisiteCache, T?>,
            compute: () throws -> T
        ) rethrows -> T {
            if let cachedValue = self[keyPath: keyPath] {
                return cachedValue
            } else {
                let computedValue = try compute()
                self[keyPath: keyPath] = computedValue
                return computedValue
            }
        }
    }
    
    func clearPrerequisites() {
        self.prerequisiteCache.worldPoints = nil
        self.prerequisiteCache.worldPointsGrid = nil
        self.prerequisiteCache.pointAlignedPlane = nil
        self.prerequisiteCache.pointProjectedPlane = nil
        self.prerequisiteCache.meshContents = nil
        self.prerequisiteCache.meshAlignedPlane = nil
        self.prerequisiteCache.meshProjectedPlane = nil
    }
}

/**
 Extension for caching counterparts of world point extraction and plane calculation.
 */
extension AttributeEstimationPipeline {
    /// Caching counterpart of getWorldPoints
    func getCachedWorldPoints(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> [WorldPoint] {
        return try self.prerequisiteCache.getOrCompute(\.worldPoints) {
            try self.getWorldPoints(accessibilityFeature: accessibilityFeature)
        }
    }
    
    /// Caching counterpart of getWorldPointsGrid
    func getCachedWorldPointsGrid(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol,
        worldPoints: [WorldPoint]
    ) throws -> WorldPointsGrid {
        return try self.prerequisiteCache.getOrCompute(\.worldPointsGrid) {
            try self.getWorldPointsGrid(
                accessibilityFeature: accessibilityFeature,
                worldPoints: worldPoints
            )
        }
    }
    
    /// Caching counterpart of calculateAlignedPlane
    func getCachedAlignedPlane(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol,
        worldPoints: [WorldPoint]
    ) throws -> Plane {
        return try self.prerequisiteCache.getOrCompute(\.pointAlignedPlane) {
            try self.calculateAlignedPlane(
                accessibilityFeature: accessibilityFeature,
                worldPoints: worldPoints
            )
        }
    }
    
    /// Caching counterpart of calculateProjectedPlane
    func getCachedProjectedPlane(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol,
        plane: Plane
    ) throws -> ProjectedPlane {
        return try self.prerequisiteCache.getOrCompute(\.pointProjectedPlane) {
            try self.calculateProjectedPlane(
                accessibilityFeature: accessibilityFeature,
                plane: plane
            )
        }
    }
}

/**
 Extension for caching counterparts of mesh polygon extraction and plane calculation
 */
public extension AttributeEstimationPipeline {
    /// Caching counterpart of getMeshContents
    func getCachedMeshContents(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> MeshContents {
        return try self.prerequisiteCache.getOrCompute(\.meshContents) {
            try self.getMeshContents(accessibilityFeature: accessibilityFeature)
        }
    }
    
    /// Caching counterpart of calculateAlignedPlane for mesh polygons
    func getCachedAlignedPlane(
        accessibilityFeature: any EditableAccessibilityFeatureProtocol,
        meshPolygons: [MeshPolygon]
    ) throws -> Plane {
        return try self.prerequisiteCache.getOrCompute(\.meshAlignedPlane) {
            try self.calculateAlignedPlane(
                accessibilityFeature: accessibilityFeature,
                meshPolygons: meshPolygons
            )
        }
    }
}

/**
 Other caching-related functions
 */
public extension AttributeEstimationPipeline {
    func getCachedSurfaceNormalsGrid(
        worldPointsGrid: WorldPointsGrid,
        plane: Plane,
        projectedPlane: ProjectedPlane
    ) throws -> SurfaceNormalsForPointsGrid {
        return try self.prerequisiteCache.getOrCompute(\.surfaceNormalsGrid) {
            guard let surfaceNormalsProcessor = self.surfaceNormalsProcessor else {
                throw AttributeEstimationPipelineError.missingPreprocessors
            }
            return try surfaceNormalsProcessor.getSurfaceNormalsFromWorldPoints(
                worldPointsGrid: worldPointsGrid, plane: plane, projectedPlane: projectedPlane
            )
        }
    }
}
