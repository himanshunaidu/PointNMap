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
    public let surfaceDisruptionProbability: Double
    public let surfaceDisruptionLogit: Double
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
    func analyzeMeshWindows(
        meshContents: MeshContents,
        plane: Plane,
        damageDetectionResults: [DamageDetectionResult],
        captureData: any CaptureMeshDataProtocol,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        predictionModel: any SurfaceIntegrityWindowPredicting =
            SurfaceIntegrityAnalysisModelZoo.placeholderLogisticRegression,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        predictionCellSize: Float = 0.09,
        includeEmptyWindows: Bool = true,
        minimumWindowPolygonCount: Int = 5
    ) throws -> SurfaceIntegrityWindowAnalysisResult {
        guard let depthImage = captureData.depthImage else {
            throw SurfaceIntegrityWindowAnalysisError.missingDepthImage
        }

        let depthMapProcessor = try DepthMapProcessor(depthImage: depthImage)
        let imageSize = captureData.originalSize
        var damagePolygonsOnPlane: [[SIMD2<Float>]] = []
        damagePolygonsOnPlane.reserveCapacity(damageDetectionResults.count)

        for result in damageDetectionResults {
            let rectangle = result.getPixelCGRect(for: imageSize)
            let imagePolygon = [
                SIMD2<Float>(Float(rectangle.minX), Float(rectangle.minY)),
                SIMD2<Float>(Float(rectangle.maxX), Float(rectangle.minY)),
                SIMD2<Float>(Float(rectangle.maxX), Float(rectangle.maxY)),
                SIMD2<Float>(Float(rectangle.minX), Float(rectangle.maxY))
            ]
            let worldPolygon = try Self.projectPolygon(
                imagePolygon,
                depthMapProcessor: depthMapProcessor,
                cameraIntrinsics: captureData.cameraIntrinsics,
                cameraTransform: captureData.cameraTransform,
                imageSize: imageSize
            )
            damagePolygonsOnPlane.append(Self.projectPolygonToPlane(worldPolygon, plane: plane))
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
            predictionModel: predictionModel,
            cellSize: cellSize,
            stride: stride,
            predictionCellSize: predictionCellSize,
            includeEmptyWindows: includeEmptyWindows,
            minimumWindowPolygonCount: minimumWindowPolygonCount
        )
    }

    func analyzeMeshWindows(
        meshPolygons: [MeshPolygon],
        plane: Plane,
        damagePolygonsOnPlane: [[SIMD2<Float>]],
        damageConfidenceScores: [Float],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        predictionModel: any SurfaceIntegrityWindowPredicting =
            SurfaceIntegrityAnalysisModelZoo.placeholderLogisticRegression,
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
            predictionModel: predictionModel,
            cellSize: cellSize,
            stride: stride,
            predictionCellSize: predictionCellSize,
            includeEmptyWindows: includeEmptyWindows,
            minimumWindowPolygonCount: minimumWindowPolygonCount
        )
    }

    func analyzeMeshWindows(
        meshPolygons: [MeshPolygon],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        planeNormal: SIMD3<Float>,
        damagePolygonsOnPlane: [[SIMD2<Float>]],
        damageConfidenceScores: [Float],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault,
        predictionModel: any SurfaceIntegrityWindowPredicting =
            SurfaceIntegrityAnalysisModelZoo.placeholderLogisticRegression,
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
        let surfaceDetails = try Self.getSurfaceDetailsFromMesh(
            centroids: meshPolygons.map(\.centroid),
            normals: meshPolygons.map(\.normal),
            areas: meshPolygons.map(\.area),
            planeNormal: planeNormal
        )
        let heightResiduals = Self.calculateHeightResiduals(
            surfaceDetails: surfaceDetails,
            planeOrigin: planeOrigin,
            planeNormal: planeNormal
        )
        let signedTiltData = try Self.calculateSignedTiltData(
            surfaceDetails: surfaceDetails,
            firstPlaneVector: firstPlaneVector,
            secondPlaneVector: secondPlaneVector,
            planeNormal: planeNormal
        )
        let grid = try computeSlidingWindowGridUsingMetalMembership(
            meshCentroids: surfaceDetails.map { $0.centroid },
            planeOrigin: planeOrigin,
            firstPlaneVector: firstPlaneVector,
            secondPlaneVector: secondPlaneVector,
            cellSize: cellSize,
            stride: stride,
            predictionCellSize: predictionCellSize,
            includeEmptyWindows: includeEmptyWindows,
            minMeshPoints: minimumWindowPolygonCount
        )
        let windowsOnPlane = Self.projectGridWindowsToPlane(
            grid.gridBounds3D,
            planeOrigin: planeOrigin,
            firstPlaneVector: firstPlaneVector,
            secondPlaneVector: secondPlaneVector
        )

        var stagedFeatures: [SurfaceIntegrityWindowFeatures]?
        if let gpuMembership = grid.gpuMembership {
            do {
                let result = try computeCompleteGPUWindowFeatures(
                    surfaceDetails: surfaceDetails,
                    heightResiduals: heightResiduals,
                    signedTiltData: signedTiltData,
                    membership: gpuMembership,
                    retainedWindowIndices: grid.retainedWindowIndices,
                    heightFromGround: heightFromGround,
                    configuration: configuration
                )
                guard result.values.count == grid.gridIndices.count * result.featureStride else {
                    throw SurfaceIntegrityProcessorError.unableToProcessBufferData
                }
                stagedFeatures = grid.gridIndices.indices.map { row in
                    let start = row * result.featureStride
                    let rowValues = Array(result.values[start..<(start + result.featureStride)])
                    return SurfaceIntegrityWindowFeatures(
                        values: Dictionary(uniqueKeysWithValues: zip(configuration.allColumns, rowValues)),
                        orderedColumns: configuration.allColumns
                    )
                }
            } catch {
                print("[WINDOW_FEATURE:GPU] success=false fallback=zero error=\(error.localizedDescription)")
            }
        } else {
            print("[WINDOW_FEATURE:GPU] success=false fallback=zero error=missing_gpu_membership")
        }

        var windows: [SurfaceIntegrityWindowAnalysis] = []
        windows.reserveCapacity(grid.gridIndices.count)
        for index in grid.gridIndices.indices {
            // Metal scatter ordering is intentionally unspecified; canonicalize the CPU bridge.
            let surfaceDetailIndices = grid.windowToMeshIndices[index].sorted()
            let damageOverlap = Self.checkOverlapBetweenPolygons(
                polygonBase: windowsOnPlane[index],
                polygonsCompare: damagePolygonsOnPlane,
                severityCompare: damageConfidenceScores
            )
            let features: SurfaceIntegrityWindowFeatures
            if let stagedFeatures {
                features = stagedFeatures[index]
            } else {
                features = Self.makeUnavailableWindowFeatures(
                    heightFromGround: heightFromGround,
                    configuration: configuration
                )
            }
            let prediction: SurfaceIntegrityPrediction
            if stagedFeatures != nil {
                var modelFeatures: [SurfaceIntegrityModelFeature: Double] = [
                    .damageOverlapRatio: Double(damageOverlap.overlapRatio),
                    .maximumDamageConfidence: Double(damageOverlap.maximumSeverity)
                ]
                for (feature, value) in features.values {
                    modelFeatures[.windowFeature(feature)] = Double(value)
                }
                prediction = try predictionModel.predict(features: modelFeatures)
            } else {
                prediction = Self.unavailableSurfaceIntegrityPrediction
            }

            windows.append(
                SurfaceIntegrityWindowAnalysis(
                    gridIndex: grid.gridIndices[index],
                    gridBounds: grid.gridBounds[index],
                    gridBounds3D: grid.gridBounds3D[index],
                    surfaceDetailIndices: surfaceDetailIndices,
                    damageOverlapRatio: damageOverlap.overlapRatio,
                    maximumDamageConfidence: damageOverlap.maximumSeverity,
                    surfaceDisruptionProbability: prediction.probability,
                    surfaceDisruptionLogit: prediction.logit,
                    hasSurfaceDisruption: prediction.isDisrupted,
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

    static func makeUnavailableWindowFeatures(
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration
    ) -> SurfaceIntegrityWindowFeatures {
        var values = Dictionary(
            uniqueKeysWithValues: configuration.allColumns.map { ($0, Float.zero) }
        )
        values[.heightFromGround] = heightFromGround ?? .nan
        return SurfaceIntegrityWindowFeatures(
            values: values,
            orderedColumns: configuration.allColumns
        )
    }

    static var unavailableSurfaceIntegrityPrediction: SurfaceIntegrityPrediction {
        SurfaceIntegrityPrediction(probability: 0, isDisrupted: false, logit: .nan)
    }
}
