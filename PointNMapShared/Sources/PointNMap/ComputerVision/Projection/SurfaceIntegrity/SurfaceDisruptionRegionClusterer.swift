//
//  SurfaceDisruptionRegionClusterer.swift
//  PointNMapShared
//

import Foundation
import simd

public enum SurfaceDisruptionClusteringError: Error, Equatable, LocalizedError {
    case invalidAdjacencyThreshold
    case invalidMinimumWindowCount
    case invalidPredictionCellSize
    case inconsistentAnalysisData

    public var errorDescription: String? {
        switch self {
        case .invalidAdjacencyThreshold:
            return "The surface disruption adjacency threshold must be finite and nonnegative."
        case .invalidMinimumWindowCount:
            return "The minimum surface disruption window count must be greater than zero."
        case .invalidPredictionCellSize:
            return "The surface disruption prediction-cell size must be finite and greater than zero."
        case .inconsistentAnalysisData:
            return "The surface integrity analysis contains inconsistent window geometry."
        }
    }
}

struct SurfaceDisruptionWindowSample: Equatable, Sendable {
    let windowIndex: Int
    let gridIndex: SIMD2<Int32>
    let planeCenter: SIMD2<Float>
    let worldCenter: SIMD3<Float>
    let hasSurfaceDisruption: Bool
}

public struct SurfaceDisruptionRegionClusterer {
    public init() {}

    public func cluster(
        analysis: SurfaceIntegrityWindowAnalysisResult,
        configuration: SurfaceDisruptionClusteringConfiguration = .init()
    ) throws -> SurfaceDisruptionClusteringResult {
        let samples = try analysis.windows.indices.compactMap { index -> SurfaceDisruptionWindowSample? in
            let window = analysis.windows[index]
            guard window.hasSurfaceDisruption else {
                return nil
            }
            guard analysis.grid.predictionCellBounds.indices.contains(index),
                  analysis.grid.predictionCellBounds3D.indices.contains(index) else {
                throw SurfaceDisruptionClusteringError.inconsistentAnalysisData
            }

            let bounds = analysis.grid.predictionCellBounds[index]
            let worldCorners = analysis.grid.predictionCellBounds3D[index]
            guard !worldCorners.isEmpty else {
                throw SurfaceDisruptionClusteringError.inconsistentAnalysisData
            }

            return SurfaceDisruptionWindowSample(
                windowIndex: index,
                gridIndex: window.gridIndex,
                planeCenter: SIMD2(
                    (bounds.minU + bounds.maxU) / 2,
                    (bounds.minV + bounds.maxV) / 2
                ),
                worldCenter: Self.average(worldCorners),
                hasSurfaceDisruption: true
            )
        }

        return try cluster(
            samples: samples,
            predictionCellSize: analysis.grid.predictionCellSize,
            stride: analysis.grid.stride,
            configuration: configuration
        )
    }

    func cluster(
        samples: [SurfaceDisruptionWindowSample],
        predictionCellSize: Float,
        stride: Float,
        configuration: SurfaceDisruptionClusteringConfiguration = .init()
    ) throws -> SurfaceDisruptionClusteringResult {
        guard configuration.minimumWindowCount > 0 else {
            throw SurfaceDisruptionClusteringError.invalidMinimumWindowCount
        }
        guard predictionCellSize.isFinite, predictionCellSize > 0 else {
            throw SurfaceDisruptionClusteringError.invalidPredictionCellSize
        }

        let adjacencyThreshold = configuration.adjacencyThresholdMeters
            ?? (stride * Float(2).squareRoot())
        guard adjacencyThreshold.isFinite, adjacencyThreshold >= 0 else {
            throw SurfaceDisruptionClusteringError.invalidAdjacencyThreshold
        }

        let disruptedSamples = samples
            .filter(\.hasSurfaceDisruption)
            .sorted(by: Self.samplePrecedes)

        let connectedComponents = ConnectedComponents<SurfaceDisruptionWindowSample>(
            minimumComponentSize: configuration.minimumWindowCount,
            adjacencyFunction: { lhs, rhs, threshold in
                let tolerance = max(1, abs(threshold)) * Float.ulpOfOne * 8
                return simd_distance(lhs.planeCenter, rhs.planeCenter) <= threshold + tolerance
            },
            adjacencyThreshold: adjacencyThreshold
        )
        let fitResult = try connectedComponents.fit(values: disruptedSamples)

        let regions = fitResult.clusters
            .map {
                Self.makeRegion(
                    samples: $0,
                    predictionCellSize: predictionCellSize
                )
            }
            .sorted(by: Self.regionPrecedes)
        let noiseWindowIndices = fitResult.outliers
            .map(\.windowIndex)
            .sorted()

        return SurfaceDisruptionClusteringResult(
            regions: regions,
            noiseWindowIndices: noiseWindowIndices
        )
    }

    private static func makeRegion(
        samples: [SurfaceDisruptionWindowSample],
        predictionCellSize: Float
    ) -> SurfaceDisruptionRegion {
        let sortedSamples = samples.sorted(by: samplePrecedes)
        let gridIndices = sortedSamples.map(\.gridIndex)
        let count = Float(sortedSamples.count)
        let planeCenter = sortedSamples.reduce(into: SIMD2<Float>.zero) {
            $0 += $1.planeCenter
        } / count
        let worldCenter = sortedSamples.reduce(into: SIMD3<Float>.zero) {
            $0 += $1.worldCenter
        } / count
        let id = gridIndices
            .map { "\($0.x):\($0.y)" }
            .joined(separator: "|")

        return SurfaceDisruptionRegion(
            id: id,
            windowIndices: sortedSamples.map(\.windowIndex).sorted(),
            gridIndices: gridIndices,
            planeCenter: planeCenter,
            worldCenter: worldCenter,
            areaSquareMeters: Double(sortedSamples.count)
                * Double(predictionCellSize)
                * Double(predictionCellSize)
        )
    }

    private static func average(_ values: [SIMD3<Float>]) -> SIMD3<Float> {
        values.reduce(into: SIMD3<Float>.zero, +=) / Float(values.count)
    }

    private static func samplePrecedes(
        _ lhs: SurfaceDisruptionWindowSample,
        _ rhs: SurfaceDisruptionWindowSample
    ) -> Bool {
        if lhs.gridIndex.x != rhs.gridIndex.x {
            return lhs.gridIndex.x < rhs.gridIndex.x
        }
        if lhs.gridIndex.y != rhs.gridIndex.y {
            return lhs.gridIndex.y < rhs.gridIndex.y
        }
        return lhs.windowIndex < rhs.windowIndex
    }

    private static func regionPrecedes(
        _ lhs: SurfaceDisruptionRegion,
        _ rhs: SurfaceDisruptionRegion
    ) -> Bool {
        guard let lhsFirst = lhs.gridIndices.first,
              let rhsFirst = rhs.gridIndices.first else {
            return lhs.gridIndices.count < rhs.gridIndices.count
        }
        if lhsFirst.x != rhsFirst.x {
            return lhsFirst.x < rhsFirst.x
        }
        if lhsFirst.y != rhsFirst.y {
            return lhsFirst.y < rhsFirst.y
        }
        return lhs.id < rhs.id
    }
}
