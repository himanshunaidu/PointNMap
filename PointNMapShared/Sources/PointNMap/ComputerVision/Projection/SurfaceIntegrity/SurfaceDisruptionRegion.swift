//
//  SurfaceDisruptionRegion.swift
//  PointNMapShared
//

import simd

public struct SurfaceDisruptionRegion: Identifiable, Equatable, Sendable {
    public let id: String
    public let windowIndices: [Int]
    public let gridIndices: [SIMD2<Int32>]
    public let planeCenter: SIMD2<Float>
    public let worldCenter: SIMD3<Float>
    public let areaSquareMeters: Double

    public init(
        id: String,
        windowIndices: [Int],
        gridIndices: [SIMD2<Int32>],
        planeCenter: SIMD2<Float>,
        worldCenter: SIMD3<Float>,
        areaSquareMeters: Double
    ) {
        self.id = id
        self.windowIndices = windowIndices
        self.gridIndices = gridIndices
        self.planeCenter = planeCenter
        self.worldCenter = worldCenter
        self.areaSquareMeters = areaSquareMeters
    }
}

public struct SurfaceDisruptionClusteringConfiguration: Equatable, Sendable {
    public let adjacencyThresholdMeters: Float?
    public let minimumWindowCount: Int

    public init(
        adjacencyThresholdMeters: Float? = nil,
        minimumWindowCount: Int = 2
    ) {
        self.adjacencyThresholdMeters = adjacencyThresholdMeters
        self.minimumWindowCount = minimumWindowCount
    }
}

public struct SurfaceDisruptionClusteringResult: Equatable, Sendable {
    public let regions: [SurfaceDisruptionRegion]
    public let noiseWindowIndices: [Int]

    public init(
        regions: [SurfaceDisruptionRegion],
        noiseWindowIndices: [Int]
    ) {
        self.regions = regions
        self.noiseWindowIndices = noiseWindowIndices
    }

    public var totalRegionAreaSquareMeters: Double {
        regions.reduce(0) { $0 + $1.areaSquareMeters }
    }
}
