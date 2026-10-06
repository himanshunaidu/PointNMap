//
//  SlidingWindowGridExtension.swift
//  PointNMapShared
//

import Foundation
import simd

public enum SlidingWindowGridError: Error, LocalizedError {
    case emptyMesh
    case invalidCellSize
    case invalidStride
    case invalidMinimumMeshPointCount
    case gridDimensionOverflow

    public var errorDescription: String? {
        switch self {
        case .emptyMesh:
            return "A sliding-window grid cannot be created from an empty mesh."
        case .invalidCellSize:
            return "The sliding-window cell size must be finite and greater than zero."
        case .invalidStride:
            return "The sliding-window stride must be finite and greater than zero."
        case .invalidMinimumMeshPointCount:
            return "The minimum mesh point count cannot be negative."
        case .gridDimensionOverflow:
            return "The sliding-window grid dimensions exceed the supported range."
        }
    }
}

public struct SlidingWindowBounds: Sendable, Equatable {
    public let minU: Float
    public let maxU: Float
    public let minV: Float
    public let maxV: Float

    public init(minU: Float, maxU: Float, minV: Float, maxV: Float) {
        self.minU = minU
        self.maxU = maxU
        self.minV = minV
        self.maxV = maxV
    }
}

public struct SlidingWindowGridIndexResult: Sendable {
    public let gridIndices: [SIMD2<Int32>]
    public let gridOriginU: Float
    public let gridOriginV: Float
    public let gridShape: SIMD2<Int32>
    public let uvCoordinates: [SIMD2<Float>]
}

public struct SlidingWindowBoundsResult: Sendable {
    public let bounds: [SlidingWindowBounds]
    public let bounds3D: [[SIMD3<Float>]]
}

public struct SlidingWindowGrid: Sendable {
    public let gridIndices: [SIMD2<Int32>]
    public let gridBounds: [SlidingWindowBounds]
    public let gridBounds3D: [[SIMD3<Float>]]
    public let windowToMeshIndices: [[Int]]
    public let uvCoordinates: [SIMD2<Float>]
    public let gridOriginU: Float
    public let gridOriginV: Float
    public let gridShape: SIMD2<Int32>
    public let cellSize: Float
    public let stride: Float
}

public extension SurfaceIntegrityProcessor {
    static func computeGridIndices(
        meshPolygons: [MeshPolygon],
        plane: Plane,
        stride: Float = 0.09
    ) throws -> SlidingWindowGridIndexResult {
        try computeGridIndices(
            meshCentroids: meshPolygons.map(\.centroid),
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector,
            stride: stride
        )
    }

    static func computeGridIndices(
        meshCentroids: [SIMD3<Float>],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        stride: Float = 0.09
    ) throws -> SlidingWindowGridIndexResult {
        guard stride.isFinite, stride > 0 else {
            throw SlidingWindowGridError.invalidStride
        }
        guard !meshCentroids.isEmpty else {
            throw SlidingWindowGridError.emptyMesh
        }

        let uvCoordinates = meshCentroids.map { centroid in
            let displacement = centroid - planeOrigin
            return SIMD2<Float>(
                simd_dot(displacement, firstPlaneVector),
                simd_dot(displacement, secondPlaneVector)
            )
        }
        guard let firstCoordinate = uvCoordinates.first else {
            throw SlidingWindowGridError.emptyMesh
        }
        var minU = firstCoordinate.x
        var minV = firstCoordinate.y
        var maxU = firstCoordinate.x
        var maxV = firstCoordinate.y
        for coordinate in uvCoordinates.dropFirst() {
            minU = min(minU, coordinate.x)
            minV = min(minV, coordinate.y)
            maxU = max(maxU, coordinate.x)
            maxV = max(maxV, coordinate.y)
        }
        let gridOriginU = floor(minU / stride) * stride
        let gridOriginV = floor(minV / stride) * stride
        let uCount = floor((maxU - gridOriginU) / stride) + 1
        let vCount = floor((maxV - gridOriginV) / stride) + 1

        guard uCount <= Float(Int32.max), vCount <= Float(Int32.max) else {
            throw SlidingWindowGridError.gridDimensionOverflow
        }
        let numberOfUIndices = Int32(uCount)
        let numberOfVIndices = Int32(vCount)
        var gridIndices: [SIMD2<Int32>] = []
        gridIndices.reserveCapacity(Int(numberOfUIndices) * Int(numberOfVIndices))
        for uIndex in 0..<numberOfUIndices {
            for vIndex in 0..<numberOfVIndices {
                gridIndices.append(SIMD2<Int32>(uIndex, vIndex))
            }
        }

        return SlidingWindowGridIndexResult(
            gridIndices: gridIndices,
            gridOriginU: gridOriginU,
            gridOriginV: gridOriginV,
            gridShape: SIMD2<Int32>(numberOfUIndices, numberOfVIndices),
            uvCoordinates: uvCoordinates
        )
    }

    static func computeGridBounds(
        gridIndices: [SIMD2<Int32>],
        gridOriginU: Float,
        gridOriginV: Float,
        plane: Plane,
        cellSize: Float = 0.27,
        stride: Float = 0.09
    ) throws -> SlidingWindowBoundsResult {
        try computeGridBounds(
            gridIndices: gridIndices,
            gridOriginU: gridOriginU,
            gridOriginV: gridOriginV,
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector,
            cellSize: cellSize,
            stride: stride
        )
    }

    static func computeGridBounds(
        gridIndices: [SIMD2<Int32>],
        gridOriginU: Float,
        gridOriginV: Float,
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        cellSize: Float = 0.27,
        stride: Float = 0.09
    ) throws -> SlidingWindowBoundsResult {
        guard cellSize.isFinite, cellSize > 0 else {
            throw SlidingWindowGridError.invalidCellSize
        }
        guard stride.isFinite, stride > 0 else {
            throw SlidingWindowGridError.invalidStride
        }

        var bounds: [SlidingWindowBounds] = []
        var bounds3D: [[SIMD3<Float>]] = []
        bounds.reserveCapacity(gridIndices.count)
        bounds3D.reserveCapacity(gridIndices.count)
        for gridIndex in gridIndices {
            let minU = gridOriginU + Float(gridIndex.x) * stride
            let maxU = minU + cellSize
            let minV = gridOriginV + Float(gridIndex.y) * stride
            let maxV = minV + cellSize
            bounds.append(SlidingWindowBounds(minU: minU, maxU: maxU, minV: minV, maxV: maxV))
            bounds3D.append([
                planeOrigin + minU * firstPlaneVector + minV * secondPlaneVector,
                planeOrigin + maxU * firstPlaneVector + minV * secondPlaneVector,
                planeOrigin + maxU * firstPlaneVector + maxV * secondPlaneVector,
                planeOrigin + minU * firstPlaneVector + maxV * secondPlaneVector
            ])
        }

        return SlidingWindowBoundsResult(bounds: bounds, bounds3D: bounds3D)
    }

    static func computeSlidingWindowGrid(
        meshPolygons: [MeshPolygon],
        plane: Plane,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        includeEmptyWindows: Bool = true,
        minMeshPoints: Int = 5
    ) throws -> SlidingWindowGrid {
        try computeSlidingWindowGrid(
            meshCentroids: meshPolygons.map(\.centroid),
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector,
            cellSize: cellSize,
            stride: stride,
            includeEmptyWindows: includeEmptyWindows,
            minMeshPoints: minMeshPoints
        )
    }

    static func computeSlidingWindowGrid(
        meshCentroids: [SIMD3<Float>],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        cellSize: Float = 0.27,
        stride: Float = 0.09,
        includeEmptyWindows: Bool = false,
        minMeshPoints: Int = 5
    ) throws -> SlidingWindowGrid {
        guard minMeshPoints >= 0 else {
            throw SlidingWindowGridError.invalidMinimumMeshPointCount
        }
        let indexResult = try computeGridIndices(
            meshCentroids: meshCentroids,
            planeOrigin: planeOrigin,
            firstPlaneVector: firstPlaneVector,
            secondPlaneVector: secondPlaneVector,
            stride: stride
        )
        let boundsResult = try computeGridBounds(
            gridIndices: indexResult.gridIndices,
            gridOriginU: indexResult.gridOriginU,
            gridOriginV: indexResult.gridOriginV,
            planeOrigin: planeOrigin,
            firstPlaneVector: firstPlaneVector,
            secondPlaneVector: secondPlaneVector,
            cellSize: cellSize,
            stride: stride
        )

        var retainedIndices: [SIMD2<Int32>] = []
        var retainedBounds: [SlidingWindowBounds] = []
        var retainedBounds3D: [[SIMD3<Float>]] = []
        var windowToMeshIndices: [[Int]] = []
        for windowIndex in boundsResult.bounds.indices {
            let windowBounds = boundsResult.bounds[windowIndex]
            let meshIndices = indexResult.uvCoordinates.indices.filter { meshIndex in
                let coordinate = indexResult.uvCoordinates[meshIndex]
                return coordinate.x >= windowBounds.minU && coordinate.x < windowBounds.maxU
                    && coordinate.y >= windowBounds.minV && coordinate.y < windowBounds.maxV
            }
            guard includeEmptyWindows || meshIndices.count >= minMeshPoints else {
                continue
            }
            retainedIndices.append(indexResult.gridIndices[windowIndex])
            retainedBounds.append(windowBounds)
            retainedBounds3D.append(boundsResult.bounds3D[windowIndex])
            windowToMeshIndices.append(meshIndices)
        }

        return SlidingWindowGrid(
            gridIndices: retainedIndices,
            gridBounds: retainedBounds,
            gridBounds3D: retainedBounds3D,
            windowToMeshIndices: windowToMeshIndices,
            uvCoordinates: indexResult.uvCoordinates,
            gridOriginU: indexResult.gridOriginU,
            gridOriginV: indexResult.gridOriginV,
            gridShape: indexResult.gridShape,
            cellSize: cellSize,
            stride: stride
        )
    }
}
