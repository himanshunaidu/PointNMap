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
    /// Retained context windows and the source mesh polygons whose centroids support each window.
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
    static func projectPolygon(
        _ polygon: [SIMD2<Float>],
        depthMapProcessor: DepthMapProcessor,
        cameraIntrinsics: simd_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize,
        depthSearchRadius: Int = 3
    ) throws -> [SIMD3<Float>] {
        var projectedPolygon: [SIMD3<Float>] = []
        projectedPolygon.reserveCapacity(polygon.count)
        for point in polygon {
            guard point.x >= 0, point.x < Float(imageSize.width),
                  point.y >= 0, point.y < Float(imageSize.height) else {
                continue
            }
            let pixelPoint = CGPoint(x: CGFloat(point.x), y: CGFloat(point.y))
            guard let depth = try depthMapProcessor.getDepthAtPointInRadius(
                point: pixelPoint,
                radius: depthSearchRadius
            ) else {
                continue
            }
            projectedPolygon.append(
                ProjectionUtils.projectPixelToWorld(
                    pixelPoint: pixelPoint,
                    depth: depth,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics
                )
            )
        }
        return projectedPolygon
    }

    static func projectPolygonToPlane(
        _ projectedPolygon: [SIMD3<Float>],
        plane: Plane
    ) -> [SIMD2<Float>] {
        projectPolygonToPlane(
            projectedPolygon,
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector
        )
    }

    static func projectPolygonToPlane(
        _ projectedPolygon: [SIMD3<Float>],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>
    ) -> [SIMD2<Float>] {
        projectedPolygon.map { point in
            let displacement = point - planeOrigin
            return SIMD2<Float>(
                simd_dot(displacement, firstPlaneVector),
                simd_dot(displacement, secondPlaneVector)
            )
        }
    }

    static func projectGridWindowsToPlane(
        _ gridBounds3D: [[SIMD3<Float>]],
        plane: Plane
    ) -> [[SIMD2<Float>]] {
        projectGridWindowsToPlane(
            gridBounds3D,
            planeOrigin: plane.origin,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector
        )
    }

    static func projectGridWindowsToPlane(
        _ gridBounds3D: [[SIMD3<Float>]],
        planeOrigin: SIMD3<Float>,
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>
    ) -> [[SIMD2<Float>]] {
        gridBounds3D.map { corners in
            projectPolygonToPlane(
                corners,
                planeOrigin: planeOrigin,
                firstPlaneVector: firstPlaneVector,
                secondPlaneVector: secondPlaneVector
            )
        }
    }

    /**
        Measures how much of `polygonBase` is covered by the union of the comparison polygons.
        Union coverage prevents overlapping damage detections from being counted more than once.
     */
    static func checkOverlapBetweenPolygons(
        polygonBase: [SIMD2<Float>],
        polygonsCompare: [[SIMD2<Float>]],
        severityCompare: [Float]? = nil
    ) -> (overlapRatio: Float, maximumSeverity: Float) {
        let baseArea = polygonArea(polygonBase)
        guard baseArea > 0, polygonBase.count >= 3 else {
            return (0, 0)
        }
        let comparisonPolygons = polygonsCompare.filter { $0.count >= 3 && polygonArea($0) > 0 }
        guard !comparisonPolygons.isEmpty else {
            return (0, 0)
        }

        var maximumSeverity: Float = 0
        if let severityCompare {
            for (index, polygon) in polygonsCompare.enumerated()
                where index < severityCompare.count && polygonsIntersect(polygonBase, polygon) {
                maximumSeverity = max(maximumSeverity, severityCompare[index])
            }
        }

        let allPolygons = [polygonBase] + comparisonPolygons
        var criticalXCoordinates = allPolygons.flatMap { $0.map(\.x) }
        let allEdges = allPolygons.flatMap(edges)
        for firstIndex in allEdges.indices {
            for secondIndex in allEdges.indices where secondIndex > firstIndex {
                if let intersection = segmentIntersection(allEdges[firstIndex], allEdges[secondIndex]) {
                    criticalXCoordinates.append(intersection.x)
                }
            }
        }
        criticalXCoordinates.sort()
        let uniqueXCoordinates = criticalXCoordinates.reduce(into: [Float]()) { result, value in
            if result.last.map({ abs($0 - value) > 0.000_001 }) ?? true {
                result.append(value)
            }
        }

        var intersectionArea: Float = 0
        for index in 0..<max(uniqueXCoordinates.count - 1, 0) {
            let minX = uniqueXCoordinates[index]
            let maxX = uniqueXCoordinates[index + 1]
            let width = maxX - minX
            guard width > 0 else { continue }
            // Within a slab bounded by vertices and edge crossings, union height varies linearly.
            let firstHeight = overlapHeight(
                at: minX + width / 3,
                base: polygonBase,
                comparisons: comparisonPolygons
            )
            let secondHeight = overlapHeight(
                at: minX + 2 * width / 3,
                base: polygonBase,
                comparisons: comparisonPolygons
            )
            intersectionArea += width * (firstHeight + secondHeight) / 2
        }

        return (min(max(intersectionArea / baseArea, 0), 1), maximumSeverity)
    }

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

        // Express each 3D centroid in the sidewalk plane's physical 2D coordinate system.
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
        // Keep u as the outer dimension to match NumPy meshgrid(indexing: "ij") followed by reshape.
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
            // Reconstruct the four context-window corners in world space for later projection and overlays.
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
            // Half-open bounds reproduce the Python behavior and avoid ambiguous ownership on upper edges.
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

private extension SurfaceIntegrityProcessor {
    typealias Segment2D = (start: SIMD2<Float>, end: SIMD2<Float>)
    typealias Interval = (min: Float, max: Float)

    static func polygonArea(_ polygon: [SIMD2<Float>]) -> Float {
        guard polygon.count >= 3 else { return 0 }
        var twiceArea: Float = 0
        for index in polygon.indices {
            let nextIndex = (index + 1) % polygon.count
            twiceArea += polygon[index].x * polygon[nextIndex].y
                - polygon[nextIndex].x * polygon[index].y
        }
        return abs(twiceArea) / 2
    }

    static func edges(of polygon: [SIMD2<Float>]) -> [Segment2D] {
        guard polygon.count >= 2 else { return [] }
        return polygon.indices.map { index in
            (polygon[index], polygon[(index + 1) % polygon.count])
        }
    }

    static func segmentIntersection(_ first: Segment2D, _ second: Segment2D) -> SIMD2<Float>? {
        let firstDirection = first.end - first.start
        let secondDirection = second.end - second.start
        let denominator = cross(firstDirection, secondDirection)
        guard abs(denominator) > 0.000_001 else { return nil }
        let displacement = second.start - first.start
        let firstParameter = cross(displacement, secondDirection) / denominator
        let secondParameter = cross(displacement, firstDirection) / denominator
        guard firstParameter >= 0, firstParameter <= 1,
              secondParameter >= 0, secondParameter <= 1 else {
            return nil
        }
        return first.start + firstParameter * firstDirection
    }

    static func cross(_ first: SIMD2<Float>, _ second: SIMD2<Float>) -> Float {
        first.x * second.y - first.y * second.x
    }

    static func overlapHeight(
        at x: Float,
        base: [SIMD2<Float>],
        comparisons: [[SIMD2<Float>]]
    ) -> Float {
        let baseIntervals = verticalIntervals(in: base, at: x)
        let comparisonIntervals = mergeIntervals(comparisons.flatMap { verticalIntervals(in: $0, at: x) })
        var height: Float = 0
        for baseInterval in baseIntervals {
            for comparisonInterval in comparisonIntervals {
                height += max(
                    min(baseInterval.max, comparisonInterval.max)
                        - max(baseInterval.min, comparisonInterval.min),
                    0
                )
            }
        }
        return height
    }

    static func verticalIntervals(in polygon: [SIMD2<Float>], at x: Float) -> [Interval] {
        var intersections: [Float] = []
        for edge in edges(of: polygon) {
            let minX = min(edge.start.x, edge.end.x)
            let maxX = max(edge.start.x, edge.end.x)
            guard x > minX, x < maxX else { continue }
            let parameter = (x - edge.start.x) / (edge.end.x - edge.start.x)
            intersections.append(edge.start.y + parameter * (edge.end.y - edge.start.y))
        }
        intersections.sort()
        var intervals: [Interval] = []
        var index = 0
        while index + 1 < intersections.count {
            intervals.append((intersections[index], intersections[index + 1]))
            index += 2
        }
        return intervals
    }

    static func mergeIntervals(_ intervals: [Interval]) -> [Interval] {
        let sortedIntervals = intervals.sorted {
            $0.min == $1.min ? $0.max < $1.max : $0.min < $1.min
        }
        guard var current = sortedIntervals.first else { return [] }
        var merged: [Interval] = []
        for interval in sortedIntervals.dropFirst() {
            if interval.min <= current.max {
                current.max = max(current.max, interval.max)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }

    static func polygonsIntersect(_ first: [SIMD2<Float>], _ second: [SIMD2<Float>]) -> Bool {
        guard first.count >= 3, second.count >= 3 else { return false }
        for firstEdge in edges(of: first) {
            for secondEdge in edges(of: second) where segmentsTouch(firstEdge, secondEdge) {
                return true
            }
        }
        return pointInPolygon(first[0], polygon: second) || pointInPolygon(second[0], polygon: first)
    }

    static func segmentsTouch(_ first: Segment2D, _ second: Segment2D) -> Bool {
        if segmentIntersection(first, second) != nil { return true }
        return pointOnSegment(first.start, segment: second)
            || pointOnSegment(first.end, segment: second)
            || pointOnSegment(second.start, segment: first)
            || pointOnSegment(second.end, segment: first)
    }

    static func pointOnSegment(_ point: SIMD2<Float>, segment: Segment2D) -> Bool {
        let tolerance: Float = 0.000_001
        guard abs(cross(point - segment.start, segment.end - segment.start)) <= tolerance else {
            return false
        }
        return point.x >= min(segment.start.x, segment.end.x) - tolerance
            && point.x <= max(segment.start.x, segment.end.x) + tolerance
            && point.y >= min(segment.start.y, segment.end.y) - tolerance
            && point.y <= max(segment.start.y, segment.end.y) + tolerance
    }

    static func pointInPolygon(_ point: SIMD2<Float>, polygon: [SIMD2<Float>]) -> Bool {
        var isInside = false
        for edge in edges(of: polygon) {
            if pointOnSegment(point, segment: edge) { return true }
            let crossesScanline = (edge.start.y > point.y) != (edge.end.y > point.y)
            if crossesScanline {
                let crossingX = edge.start.x
                    + (point.y - edge.start.y) * (edge.end.x - edge.start.x)
                    / (edge.end.y - edge.start.y)
                if point.x < crossingX {
                    isInside.toggle()
                }
            }
        }
        return isInside
    }
}
