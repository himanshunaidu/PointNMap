//
//  SurfaceIntegrityMeshFeaturesExtension.swift
//  PointNMapShared
//

import Foundation
import simd

public enum SurfaceIntegrityMeshFeatureError: Error, LocalizedError {
    case mismatchedPolygonData
    case invalidPlaneBasis

    public var errorDescription: String? {
        switch self {
        case .mismatchedPolygonData:
            return "Mesh centroid, normal, and area collections must have matching counts."
        case .invalidPlaneBasis:
            return "Surface-integrity mesh features require finite, non-zero plane vectors."
        }
    }
}

public struct MeshSurfaceDetail: Sendable, Equatable {
    public let centroid: SIMD3<Float>
    public let normal: SIMD3<Float>
    public let area: Float
    public let angularDeviationDegrees: Float

    public init(
        centroid: SIMD3<Float>,
        normal: SIMD3<Float>,
        area: Float,
        angularDeviationDegrees: Float
    ) {
        self.centroid = centroid
        self.normal = normal
        self.area = area
        self.angularDeviationDegrees = angularDeviationDegrees
    }
}

public struct SignedTiltData: Sendable, Equatable {
    public let tiltUDegrees: Float
    public let tiltVDegrees: Float
    public let tiltMagnitudeDegrees: Float

    public init(tiltUDegrees: Float, tiltVDegrees: Float, tiltMagnitudeDegrees: Float) {
        self.tiltUDegrees = tiltUDegrees
        self.tiltVDegrees = tiltVDegrees
        self.tiltMagnitudeDegrees = tiltMagnitudeDegrees
    }
}

public extension SurfaceIntegrityProcessor {
    static func getSurfaceDetailsFromMesh(
        meshPolygons: [MeshPolygon],
        plane: Plane
    ) throws -> [MeshSurfaceDetail] {
        try getSurfaceDetailsFromMesh(
            centroids: meshPolygons.map(\.centroid),
            normals: meshPolygons.map(\.normal),
            areas: meshPolygons.map(\.area),
            planeNormal: plane.normalVector
        )
    }

    static func getSurfaceDetailsFromMesh(
        centroids: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        areas: [Float],
        planeNormal: SIMD3<Float>
    ) throws -> [MeshSurfaceDetail] {
        guard centroids.count == normals.count, normals.count == areas.count else {
            throw SurfaceIntegrityMeshFeatureError.mismatchedPolygonData
        }
        let normalizedPlaneNormal = try normalizedPlaneVector(planeNormal)
        var surfaceDetails: [MeshSurfaceDetail] = []
        surfaceDetails.reserveCapacity(normals.count)

        for index in normals.indices {
            let normalLength = simd_length(normals[index])
            guard normalLength.isFinite, normalLength > 0.000_000_01 else {
                continue
            }
            let normalizedNormal = normals[index] / normalLength
            let dotProduct = abs(simd_dot(normalizedNormal, normalizedPlaneNormal))
            let angularDeviation = acos(min(max(dotProduct, -1), 1)) * 180 / .pi
            surfaceDetails.append(
                MeshSurfaceDetail(
                    centroid: centroids[index],
                    normal: normalizedNormal,
                    area: areas[index],
                    angularDeviationDegrees: angularDeviation
                )
            )
        }
        return surfaceDetails
    }

    static func calculateHeightResiduals(
        surfaceDetails: [MeshSurfaceDetail],
        plane: Plane
    ) -> [Float] {
        calculateHeightResiduals(
            surfaceDetails: surfaceDetails,
            planeOrigin: plane.origin,
            planeNormal: plane.normalVector
        )
    }

    static func calculateHeightResiduals(
        surfaceDetails: [MeshSurfaceDetail],
        planeOrigin: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) -> [Float] {
        surfaceDetails.map { detail in
            simd_dot(detail.centroid - planeOrigin, planeNormal)
        }
    }

    static func calculateSignedTiltData(
        surfaceDetails: [MeshSurfaceDetail],
        plane: Plane
    ) throws -> [SignedTiltData] {
        try calculateSignedTiltData(
            surfaceDetails: surfaceDetails,
            firstPlaneVector: plane.firstVector,
            secondPlaneVector: plane.secondVector,
            planeNormal: plane.normalVector
        )
    }

    static func calculateSignedTiltData(
        surfaceDetails: [MeshSurfaceDetail],
        firstPlaneVector: SIMD3<Float>,
        secondPlaneVector: SIMD3<Float>,
        planeNormal: SIMD3<Float>
    ) throws -> [SignedTiltData] {
        let normalizedFirstVector = try normalizedPlaneVector(firstPlaneVector)
        let normalizedSecondVector = try normalizedPlaneVector(secondPlaneVector)
        let normalizedPlaneNormal = try normalizedPlaneVector(planeNormal)

        return surfaceDetails.map { detail in
            let normalLength = simd_length(detail.normal)
            guard normalLength.isFinite, normalLength > 0 else {
                return SignedTiltData(
                    tiltUDegrees: .nan,
                    tiltVDegrees: .nan,
                    tiltMagnitudeDegrees: .nan
                )
            }
            let normal = detail.normal / normalLength
            let normalU = simd_dot(normal, normalizedFirstVector)
            let normalV = simd_dot(normal, normalizedSecondVector)
            let normalN = simd_dot(normal, normalizedPlaneNormal)
            let radiansToDegrees = Float(180 / Double.pi)
            return SignedTiltData(
                tiltUDegrees: atan2(normalU, normalN) * radiansToDegrees,
                tiltVDegrees: atan2(normalV, normalN) * radiansToDegrees,
                // This intentionally mirrors the Python model feature definition.
                tiltMagnitudeDegrees: atan2(normalN, sqrt(normalU * normalU + normalV * normalV))
                    * radiansToDegrees
            )
        }
    }
}

private extension SurfaceIntegrityProcessor {
    static func normalizedPlaneVector(_ vector: SIMD3<Float>) throws -> SIMD3<Float> {
        let length = simd_length(vector)
        guard length.isFinite, length > 0.000_000_01 else {
            throw SurfaceIntegrityMeshFeatureError.invalidPlaneBasis
        }
        return vector / length
    }
}
