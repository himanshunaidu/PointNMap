//
//  SlidingWindowGridDiagnosticExtension.swift
//  PointNMapShared
//

import Foundation
import os
import simd

public struct SlidingWindowCentroidDiagnostic: Sendable, Equatable {
    public let meshIndex: Int
    public let uvCoordinate: SIMD2<Float>
    public let normalizedU: Float
    public let normalizedV: Float
    public let baseU: Int
    public let baseV: Int
    public let distanceFromMinU: Float
    public let distanceFromMaxU: Float
    public let distanceFromMinV: Float
    public let distanceFromMaxV: Float
}

public struct SlidingWindowMembershipDifference: Sendable, Equatable {
    public let windowPosition: Int
    public let gridIndex: SIMD2<Int32>
    public let bounds: SlidingWindowBounds
    public let optimizedCount: Int
    public let referenceCount: Int
    public let missingMeshIndices: [Int]
    public let unexpectedMeshIndices: [Int]
    public let centroids: [SlidingWindowCentroidDiagnostic]
}

public struct SlidingWindowMembershipDiagnostic: Sendable, Equatable {
    public let comparedWindowCount: Int
    public let differingWindowCount: Int
    public let missingMembershipCount: Int
    public let unexpectedMembershipCount: Int
    public let details: [SlidingWindowMembershipDifference]

    public var hasExactParity: Bool {
        differingWindowCount == 0
    }
}

public extension SurfaceIntegrityProcessor {
    static func diagnoseSlidingWindowGrids(
        optimized: SlidingWindowGrid,
        reference: SlidingWindowGrid,
        maximumDetailedWindows: Int = 10
    ) -> SlidingWindowMembershipDiagnostic {
        diagnoseSlidingWindowMemberships(
            optimizedMemberships: optimized.windowToMeshIndices,
            referenceMemberships: reference.windowToMeshIndices,
            gridIndices: optimized.gridIndices,
            gridBounds: optimized.gridBounds,
            uvCoordinates: optimized.uvCoordinates,
            gridOriginU: optimized.gridOriginU,
            gridOriginV: optimized.gridOriginV,
            stride: optimized.stride,
            maximumDetailedWindows: maximumDetailedWindows
        )
    }

    static func diagnoseSlidingWindowMemberships(
        optimizedMemberships: [[Int]],
        referenceMemberships: [[Int]],
        gridIndices: [SIMD2<Int32>],
        gridBounds: [SlidingWindowBounds],
        uvCoordinates: [SIMD2<Float>],
        gridOriginU: Float,
        gridOriginV: Float,
        stride: Float,
        maximumDetailedWindows: Int = 10
    ) -> SlidingWindowMembershipDiagnostic {
        let comparedWindowCount = min(optimizedMemberships.count, referenceMemberships.count)
        var differingWindowCount = abs(optimizedMemberships.count - referenceMemberships.count)
        var missingMembershipCount = 0
        var unexpectedMembershipCount = 0
        var details: [SlidingWindowMembershipDifference] = []
        details.reserveCapacity(min(maximumDetailedWindows, comparedWindowCount))

        for windowPosition in 0..<comparedWindowCount {
            let optimized = Set(optimizedMemberships[windowPosition])
            let reference = Set(referenceMemberships[windowPosition])
            let missing = reference.subtracting(optimized).sorted()
            let unexpected = optimized.subtracting(reference).sorted()
            guard !missing.isEmpty || !unexpected.isEmpty else { continue }

            differingWindowCount += 1
            missingMembershipCount += missing.count
            unexpectedMembershipCount += unexpected.count
            guard details.count < maximumDetailedWindows,
                  windowPosition < gridIndices.count,
                  windowPosition < gridBounds.count else {
                continue
            }

            let bounds = gridBounds[windowPosition]
            let implicatedIndices = Array(Set(missing + unexpected)).sorted()
            let centroidDetails = implicatedIndices.compactMap { meshIndex -> SlidingWindowCentroidDiagnostic? in
                guard uvCoordinates.indices.contains(meshIndex) else { return nil }
                let coordinate = uvCoordinates[meshIndex]
                let normalizedU = (coordinate.x - gridOriginU) / stride
                let normalizedV = (coordinate.y - gridOriginV) / stride
                return SlidingWindowCentroidDiagnostic(
                    meshIndex: meshIndex,
                    uvCoordinate: coordinate,
                    normalizedU: normalizedU,
                    normalizedV: normalizedV,
                    baseU: Int(floor(normalizedU)),
                    baseV: Int(floor(normalizedV)),
                    distanceFromMinU: coordinate.x - bounds.minU,
                    distanceFromMaxU: coordinate.x - bounds.maxU,
                    distanceFromMinV: coordinate.y - bounds.minV,
                    distanceFromMaxV: coordinate.y - bounds.maxV
                )
            }
            details.append(
                SlidingWindowMembershipDifference(
                    windowPosition: windowPosition,
                    gridIndex: gridIndices[windowPosition],
                    bounds: bounds,
                    optimizedCount: optimizedMemberships[windowPosition].count,
                    referenceCount: referenceMemberships[windowPosition].count,
                    missingMeshIndices: missing,
                    unexpectedMeshIndices: unexpected,
                    centroids: centroidDetails
                )
            )
        }

        if optimizedMemberships.count < referenceMemberships.count {
            missingMembershipCount += referenceMemberships[comparedWindowCount...]
                .reduce(0) { $0 + $1.count }
        } else if optimizedMemberships.count > referenceMemberships.count {
            unexpectedMembershipCount += optimizedMemberships[comparedWindowCount...]
                .reduce(0) { $0 + $1.count }
        }

        return SlidingWindowMembershipDiagnostic(
            comparedWindowCount: comparedWindowCount,
            differingWindowCount: differingWindowCount,
            missingMembershipCount: missingMembershipCount,
            unexpectedMembershipCount: unexpectedMembershipCount,
            details: details
        )
    }

    static func logSlidingWindowGridDiagnostic(
        _ diagnostic: SlidingWindowMembershipDiagnostic,
        optimized: SlidingWindowGrid,
        reference: SlidingWindowGrid,
        optimizedDurationMilliseconds: Double,
        referenceDurationMilliseconds: Double
    ) {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "PointNMapShared",
            category: "SlidingWindowGridDiagnostic"
        )
        let gridIndexMismatchCount = positionalMismatchCount(
            optimized.gridIndices,
            reference.gridIndices
        )
        let csrOffsetMismatchCount = positionalMismatchCount(
            optimized.membershipCSR.windowOffsets,
            reference.membershipCSR.windowOffsets
        )
        let csrPositionalIndexMismatchCount = positionalMismatchCount(
            optimized.membershipCSR.meshIndices,
            reference.membershipCSR.meshIndices
        )
        let speedup = optimizedDurationMilliseconds > 0
            ? referenceDurationMilliseconds / optimizedDurationMilliseconds
            : 0
        let summaryDescription =
            "[GRID:DIAGNOSTIC] exact_parity=\(diagnostic.hasExactParity) "
                + "compared_windows=\(diagnostic.comparedWindowCount) "
                + "differing_windows=\(diagnostic.differingWindowCount) "
                + "missing_memberships=\(diagnostic.missingMembershipCount) "
                + "unexpected_memberships=\(diagnostic.unexpectedMembershipCount) "
                + "grid_index_mismatches=\(gridIndexMismatchCount) "
                + "csr_offset_positional_mismatches=\(csrOffsetMismatchCount) "
                + "csr_index_positional_mismatches=\(csrPositionalIndexMismatchCount) "
                + "optimized_total_memberships=\(optimized.membershipCSR.membershipCount) "
                + "reference_total_memberships=\(reference.membershipCSR.membershipCount) "
                + "optimized_ms=\(String(format: "%.3f", optimizedDurationMilliseconds)) "
                + "reference_ms=\(String(format: "%.3f", referenceDurationMilliseconds)) "
                + "speedup=\(String(format: "%.3f", speedup))"
        logger.notice("\(summaryDescription, privacy: .public)")

        for detail in diagnostic.details {
            let centroidDescription = detail.centroids.map { centroid in
                "mesh=\(centroid.meshIndex) "
                    + "uv=(\(centroid.uvCoordinate.x),\(centroid.uvCoordinate.y)) "
                    + "normalized=(\(centroid.normalizedU),\(centroid.normalizedV)) "
                    + "base=(\(centroid.baseU),\(centroid.baseV)) "
                    + "edge_delta=(\(centroid.distanceFromMinU),\(centroid.distanceFromMaxU),"
                    + "\(centroid.distanceFromMinV),\(centroid.distanceFromMaxV))"
            }.joined(separator: "; ")
            let windowDescription =
                "[GRID:DIAGNOSTIC:WINDOW] position=\(detail.windowPosition) "
                    + "grid=(\(detail.gridIndex.x),\(detail.gridIndex.y)) "
                    + "bounds=(\(detail.bounds.minU),\(detail.bounds.maxU),"
                    + "\(detail.bounds.minV),\(detail.bounds.maxV)) "
                    + "optimized_count=\(detail.optimizedCount) "
                    + "reference_count=\(detail.referenceCount) "
                    + "missing=\(String(describing: detail.missingMeshIndices)) "
                    + "unexpected=\(String(describing: detail.unexpectedMeshIndices)) "
                    + "centroids=\(centroidDescription)"
            logger.notice("\(windowDescription, privacy: .public)")
        }
    }

    private static func positionalMismatchCount<Element: Equatable>(
        _ lhs: [Element],
        _ rhs: [Element]
    ) -> Int {
        zip(lhs, rhs).reduce(0) { count, pair in
            count + (pair.0 == pair.1 ? 0 : 1)
        } + abs(lhs.count - rhs.count)
    }
}
