//
//  SurfaceIntegrityWindowAnalysisExtension.swift
//  PointNMapShared
//

import Foundation
import CoreGraphics
import simd

public enum SurfaceIntegrityWindowAnalysisError: Error, LocalizedError {
    case missingDepthImage
    case mismatchedDamagePredictionData

    public var errorDescription: String? {
        switch self {
        case .missingDepthImage:
            return "Surface-integrity window analysis requires a depth image."
        case .mismatchedDamagePredictionData:
            return "Damage polygons and confidence scores must have matching counts."
        }
    }
}

public struct SurfaceIntegrityWindowAnalysis: Sendable {
    public let gridIndex: SIMD2<Int32>
    public let gridBounds: SlidingWindowBounds
    public let gridBounds3D: [SIMD3<Float>]
    /// Indices into the filtered surface-detail collection used to construct the grid.
    public let surfaceDetailIndices: [Int]
    public let damageOverlapRatio: Float
    public let maximumDamageConfidence: Float
    public let hasSurfaceDisruption: Bool
    public let features: SurfaceIntegrityWindowFeatures
}

public struct SurfaceIntegrityWindowAnalysisResult: Sendable {
    public let grid: SlidingWindowGrid
    public let surfaceDetails: [MeshSurfaceDetail]
    public let heightResiduals: [Float]
    public let signedTiltData: [SignedTiltData]
    public let windows: [SurfaceIntegrityWindowAnalysis]
}

public extension SurfaceIntegrityProcessor {
    static func analyzeMeshWindows(
        meshContents: MeshContents,
        plane: Plane,
        damageDetectionResults: [DamageDetectionResult],
        captureData: any CaptureMeshDataProtocol,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        predictionCellSize: Float = 0.09,
        includeEmptyWindows: Bool = true,
        minimumWindowPolygonCount: Int = 5
    ) throws -> SurfaceIntegrityWindowAnalysisResult {
        guard let depthImage = captureData.depthImage else {
            throw SurfaceIntegrityWindowAnalysisError.missingDepthImage
        }

        let imageSize = captureData.originalSize
        let damagePolygonsOnPlane = try AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceDamageProjection,
            metadata: ["detection_count": String(damageDetectionResults.count)]
        ) { () -> [[SIMD2<Float>]] in
            let depthMapProcessor = try DepthMapProcessor(depthImage: depthImage)
            var polygons: [[SIMD2<Float>]] = []
            polygons.reserveCapacity(damageDetectionResults.count)
            for result in damageDetectionResults {
                let rectangle = result.getPixelCGRect(for: imageSize)
                let imagePolygon = [
                    SIMD2<Float>(Float(rectangle.minX), Float(rectangle.minY)),
                    SIMD2<Float>(Float(rectangle.maxX), Float(rectangle.minY)),
                    SIMD2<Float>(Float(rectangle.maxX), Float(rectangle.maxY)),
                    SIMD2<Float>(Float(rectangle.minX), Float(rectangle.maxY))
                ]
                let worldPolygon = try projectPolygon(
                    imagePolygon,
                    depthMapProcessor: depthMapProcessor,
                    cameraIntrinsics: captureData.cameraIntrinsics,
                    cameraTransform: captureData.cameraTransform,
                    imageSize: imageSize
                )
                polygons.append(projectPolygonToPlane(worldPolygon, plane: plane))
            }
            return polygons
        }

        let cameraPosition4 = captureData.cameraTransform.columns.3
        let cameraPosition = SIMD3<Float>(
            cameraPosition4.x,
            cameraPosition4.y,
            cameraPosition4.z
        )
        let heightFromGround = abs(
            simd_dot(cameraPosition - plane.origin, plane.normalVector)
        )

        return try analyzeMeshWindows(
            meshPolygons: meshContents.polygons,
            plane: plane,
            damagePolygonsOnPlane: damagePolygonsOnPlane,
            damageConfidenceScores: damageDetectionResults.map { Float($0.confidence) },
            heightFromGround: heightFromGround,
            configuration: configuration,
            cellSize: cellSize,
            stride: stride,
            predictionCellSize: predictionCellSize,
            includeEmptyWindows: includeEmptyWindows,
            minimumWindowPolygonCount: minimumWindowPolygonCount
        )
    }

    static func analyzeMeshWindows(
        meshPolygons: [MeshPolygon],
        plane: Plane,
        damagePolygonsOnPlane: [[SIMD2<Float>]],
        damageConfidenceScores: [Float],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        predictionCellSize: Float = 0.09,
        includeEmptyWindows: Bool = true,
        minimumWindowPolygonCount: Int = 5
    ) throws -> SurfaceIntegrityWindowAnalysisResult {
        try analyzeMeshWindows(
            meshPolygons: meshPolygons,
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector,
            planeNormal: plane.normalVector,
            damagePolygonsOnPlane: damagePolygonsOnPlane,
            damageConfidenceScores: damageConfidenceScores,
            heightFromGround: heightFromGround,
            configuration: configuration,
            cellSize: cellSize,
            stride: stride,
            predictionCellSize: predictionCellSize,
            includeEmptyWindows: includeEmptyWindows,
            minimumWindowPolygonCount: minimumWindowPolygonCount
        )
    }

    static func analyzeMeshWindows(
        meshPolygons: [MeshPolygon],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        planeNormal: SIMD3<Float>,
        damagePolygonsOnPlane: [[SIMD2<Float>]],
        damageConfidenceScores: [Float],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        predictionCellSize: Float = 0.09,
        includeEmptyWindows: Bool = true,
        minimumWindowPolygonCount: Int = 5
    ) throws -> SurfaceIntegrityWindowAnalysisResult {
        guard damagePolygonsOnPlane.count == damageConfidenceScores.count else {
            throw SurfaceIntegrityWindowAnalysisError.mismatchedDamagePredictionData
        }

        // Invalid polygon normals are removed before grid creation so membership indices
        // remain aligned with every per-polygon feature array.
        let featureData = try AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceMeshFeatureExtraction,
            metadata: ["mesh_polygon_count": String(meshPolygons.count)]
        ) {
            let surfaceDetails = try getSurfaceDetailsFromMesh(
                centroids: meshPolygons.map(\.centroid),
                normals: meshPolygons.map(\.normal),
                areas: meshPolygons.map(\.area),
                planeNormal: planeNormal
            )
            let heightResiduals = calculateHeightResiduals(
                surfaceDetails: surfaceDetails,
                planeOrigin: planeOrigin,
                planeNormal: planeNormal
            )
            let signedTiltData = try calculateSignedTiltData(
                surfaceDetails: surfaceDetails,
                firstPlaneVector: firstPlaneVector,
                secondPlaneVector: secondPlaneVector,
                planeNormal: planeNormal
            )
            return (surfaceDetails, heightResiduals, signedTiltData)
        }
        let surfaceDetails = featureData.0
        let heightResiduals = featureData.1
        let signedTiltData = featureData.2
        let grid = try AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceGridConstruction,
            metadata: ["surface_detail_count": String(surfaceDetails.count)]
        ) {
            try computeSlidingWindowGrid(
                meshCentroids: surfaceDetails.map(\.centroid),
                planeOrigin: planeOrigin,
                firstPlaneVector: firstPlaneVector,
                secondPlaneVector: secondPlaneVector,
                cellSize: cellSize,
                stride: stride,
                predictionCellSize: predictionCellSize,
                includeEmptyWindows: includeEmptyWindows,
                minMeshPoints: minimumWindowPolygonCount
            )
        }
        let windowMetadata = [
            "window_count": String(grid.gridIndices.count),
            "surface_detail_count": String(surfaceDetails.count)
        ]
        let windowsOnPlane = AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceGridProjection,
            metadata: windowMetadata
        ) {
            projectGridWindowsToPlane(
                grid.gridBounds3D,
                planeOrigin: planeOrigin,
                firstPlaneVector: firstPlaneVector,
                secondPlaneVector: secondPlaneVector
            )
        }

        let damageOverlaps = AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceDamageOverlap,
            metadata: windowMetadata.merging([
                "detection_count": String(damagePolygonsOnPlane.count)
            ]) { _, new in new }
        ) {
            windowsOnPlane.map { window in
                checkOverlapBetweenPolygons(
                    polygonBase: window,
                    polygonsCompare: damagePolygonsOnPlane,
                    severityCompare: damageConfidenceScores
                )
            }
        }
        let featureResults = try AttributeEstimationPerformanceProfiler.shared.measure(
            .surfaceWindowFeatures,
            metadata: windowMetadata
        ) {
            try grid.windowToMeshIndices.map { surfaceDetailIndices in
                try processWindowFeatures(
                    surfaceDetails: surfaceDetailIndices.map { surfaceDetails[$0] },
                    heightResiduals: surfaceDetailIndices.map { heightResiduals[$0] },
                    signedTiltData: surfaceDetailIndices.map { signedTiltData[$0] },
                    heightFromGround: heightFromGround,
                    configuration: configuration
                )
            }
        }

        var windows: [SurfaceIntegrityWindowAnalysis] = []
        windows.reserveCapacity(grid.gridIndices.count)
        for index in grid.gridIndices.indices {
            let surfaceDetailIndices = grid.windowToMeshIndices[index]
            let damageOverlap = damageOverlaps[index]
            let features = featureResults[index]

            windows.append(
                SurfaceIntegrityWindowAnalysis(
                    gridIndex: grid.gridIndices[index],
                    gridBounds: grid.gridBounds[index],
                    gridBounds3D: grid.gridBounds3D[index],
                    surfaceDetailIndices: surfaceDetailIndices,
                    damageOverlapRatio: damageOverlap.overlapRatio,
                    maximumDamageConfidence: damageOverlap.maximumSeverity,
                    hasSurfaceDisruption: damageOverlap.overlapRatio > 0.25,
                    features: features
                )
            )
        }

        return SurfaceIntegrityWindowAnalysisResult(
            grid: grid,
            surfaceDetails: surfaceDetails,
            heightResiduals: heightResiduals,
            signedTiltData: signedTiltData,
            windows: windows
        )
    }
}
