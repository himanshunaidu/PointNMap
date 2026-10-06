//
//  SurfaceIntegrityWindowFeaturesExtension.swift
//  PointNMapShared
//

import Foundation

public struct SurfaceIntegrityWindowFeature: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let numberOfPolygons = Self("num_polygons")
    public static let totalSidewalkArea = Self("total_sidewalk_area")
    public static let averagePolygonArea = Self("average_polygon_area")
    public static let polygonDensity = Self("polygon_density")
    public static let heightFromGround = Self("height_from_ground")
}

public enum SurfaceIntegrityFeatureValueSource: String, CaseIterable, Sendable {
    case normalDeviation = "normal_deviation"
    case heightResidual = "height_residuals"
    case absoluteHeightResidual = "height_residuals_absolute"
    case signedTiltU = "signed_tilt_u"
    case signedTiltV = "signed_tilt_v"
    case signedTiltMagnitude = "signed_tilt_magnitude"
}

public enum SurfaceIntegrityCentralTendencyFeature: String, Sendable {
    case mean
    case median
    case standardDeviation = "std"
    case medianAbsoluteDeviation = "mad"
}

public enum SurfaceIntegrityDistributionShapeFeature: String, Sendable {
    case skewness
    case kurtosis
    case entropy
}

public struct SurfaceIntegrityFeatureGroupConfiguration: Sendable, Equatable {
    public let source: SurfaceIntegrityFeatureValueSource
    public let label: String
    public let centralTendencyFeatures: [SurfaceIntegrityCentralTendencyFeature]
    public let percentileFeatures: [Int]
    public let tailFeatures: [Float]
    public let distributionShapeFeatures: [SurfaceIntegrityDistributionShapeFeature]

    public init(
        source: SurfaceIntegrityFeatureValueSource,
        label: String? = nil,
        centralTendencyFeatures: [SurfaceIntegrityCentralTendencyFeature],
        percentileFeatures: [Int],
        tailFeatures: [Float],
        distributionShapeFeatures: [SurfaceIntegrityDistributionShapeFeature]
    ) {
        self.source = source
        self.label = label ?? source.rawValue
        self.centralTendencyFeatures = centralTendencyFeatures
        self.percentileFeatures = percentileFeatures
        self.tailFeatures = tailFeatures
        self.distributionShapeFeatures = distributionShapeFeatures
    }

    public var columns: [SurfaceIntegrityWindowFeature] {
        var result = centralTendencyFeatures.map {
            SurfaceIntegrityWindowFeature("\(label)_\($0.rawValue)")
        }
        result += percentileFeatures.map {
            SurfaceIntegrityWindowFeature("\(label)_p\($0)")
        }
        result += tailFeatures.map {
            SurfaceIntegrityWindowFeature(
                "\(label)_proportion_above_\(Self.columnToken(for: $0))"
            )
        }
        result += distributionShapeFeatures.map {
            SurfaceIntegrityWindowFeature("\(label)_\($0.rawValue)")
        }
        return result
    }

    fileprivate static func columnToken(for value: Float) -> String {
        let number = NSNumber(value: value)
        let text = NumberFormatter.surfaceIntegrityColumn.string(from: number)
            ?? String(value)
        return text.replacingOccurrences(of: ".", with: "_")
    }
}

public struct SurfaceIntegrityFeatureConfiguration: Sendable, Equatable {
    public let featureGroups: [SurfaceIntegrityFeatureGroupConfiguration]

    public init(featureGroups: [SurfaceIntegrityFeatureGroupConfiguration]) {
        self.featureGroups = featureGroups
    }

    public var allColumns: [SurfaceIntegrityWindowFeature] {
        featureGroups.flatMap(\.columns) + Self.globalColumns
    }

    public static let globalColumns: [SurfaceIntegrityWindowFeature] = [
        .numberOfPolygons,
        .totalSidewalkArea,
        .averagePolygonArea,
        .polygonDensity,
        .heightFromGround
    ]

    // Keep this block in the same order as SurfaceDetailFeatureGroups in Python.
    public static let pythonModelDefault = Self(featureGroups: [
        .init(
            source: .normalDeviation,
            centralTendencyFeatures: [.mean, .median, .standardDeviation, .medianAbsoluteDeviation],
            percentileFeatures: [75, 90],
            tailFeatures: [5, 10, 20],
            distributionShapeFeatures: [.skewness, .kurtosis, .entropy]
        ),
        .init(
            source: .heightResidual,
            centralTendencyFeatures: [.standardDeviation, .medianAbsoluteDeviation],
            percentileFeatures: [],
            tailFeatures: [],
            distributionShapeFeatures: [.skewness, .kurtosis, .entropy]
        ),
        .init(
            source: .absoluteHeightResidual,
            centralTendencyFeatures: [.mean, .median],
            percentileFeatures: [75, 90],
            tailFeatures: [],
            distributionShapeFeatures: []
        ),
        .init(
            source: .signedTiltU,
            centralTendencyFeatures: [.standardDeviation, .medianAbsoluteDeviation],
            percentileFeatures: [],
            tailFeatures: [],
            distributionShapeFeatures: [.skewness, .kurtosis, .entropy]
        ),
        .init(
            source: .signedTiltV,
            centralTendencyFeatures: [.standardDeviation, .medianAbsoluteDeviation],
            percentileFeatures: [],
            tailFeatures: [],
            distributionShapeFeatures: [.skewness, .kurtosis, .entropy]
        ),
        .init(
            source: .signedTiltMagnitude,
            centralTendencyFeatures: [.mean, .median],
            percentileFeatures: [75, 90],
            tailFeatures: [],
            distributionShapeFeatures: []
        )
    ])
}

public struct SurfaceIntegrityWindowFeatures: Sendable, Equatable {
    public let values: [SurfaceIntegrityWindowFeature: Float]
    public let orderedColumns: [SurfaceIntegrityWindowFeature]

    public init(
        values: [SurfaceIntegrityWindowFeature: Float],
        orderedColumns: [SurfaceIntegrityWindowFeature]
    ) {
        self.values = values
        self.orderedColumns = orderedColumns
    }

    public subscript(feature: SurfaceIntegrityWindowFeature) -> Float {
        values[feature] ?? 0
    }

    public var orderedValues: [Float] {
        orderedColumns.map { self[$0] }
    }
}

public enum SurfaceIntegrityWindowFeatureError: Error, LocalizedError {
    case mismatchedInputCounts

    public var errorDescription: String? {
        switch self {
        case .mismatchedInputCounts:
            return "Surface details, height residuals, and signed tilt data must have matching counts."
        }
    }
}

public extension SurfaceIntegrityProcessor {
    static func processWindowFeatures(
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData],
        heightFromGround: Float?,
        configuration: SurfaceIntegrityFeatureConfiguration = .pythonModelDefault
    ) throws -> SurfaceIntegrityWindowFeatures {
        guard surfaceDetails.count == heightResiduals.count,
              surfaceDetails.count == signedTiltData.count else {
            throw SurfaceIntegrityWindowFeatureError.mismatchedInputCounts
        }

        let columns = configuration.allColumns
        var features = Dictionary(
            uniqueKeysWithValues: columns.map { ($0, Float.zero) }
        )
        features[.heightFromGround] = heightFromGround ?? .nan

        guard !surfaceDetails.isEmpty else {
            return SurfaceIntegrityWindowFeatures(values: features, orderedColumns: columns)
        }

        let areas = surfaceDetails.map(\.area)
        let groupValues = makeGroupValues(
            surfaceDetails: surfaceDetails,
            heightResiduals: heightResiduals,
            signedTiltData: signedTiltData
        )

        for group in configuration.featureGroups {
            guard let values = groupValues[group.source] else {
                continue
            }
            addFeatures(for: group, values: values, weights: areas, to: &features)
        }

        let totalArea = areas.reduce(0, +)
        features[.numberOfPolygons] = Float(surfaceDetails.count)
        features[.totalSidewalkArea] = totalArea
        features[.averagePolygonArea] = mean(areas)
        features[.polygonDensity] = totalArea > 0 ? Float(surfaceDetails.count) / totalArea : 0

        return SurfaceIntegrityWindowFeatures(values: features, orderedColumns: columns)
    }

    static func weightedPercentile(
        values: [Float],
        weights: [Float],
        percentile: Float
    ) -> Float {
        guard !values.isEmpty, values.count == weights.count else {
            return .nan
        }

        let sorted = zip(values, weights).sorted { $0.0 < $1.0 }
        var cumulativeWeights: [Double] = []
        cumulativeWeights.reserveCapacity(sorted.count)
        var totalWeight = 0.0
        for item in sorted {
            totalWeight += Double(item.1)
            cumulativeWeights.append(totalWeight)
        }
        guard totalWeight > 0 else {
            return .nan
        }

        let position = Double(percentile) / 100 * totalWeight
        guard position > cumulativeWeights[0] else {
            return sorted[0].0
        }
        guard position < totalWeight else {
            return sorted[sorted.count - 1].0
        }

        let upperIndex = cumulativeWeights.firstIndex(where: { $0 >= position })
            ?? cumulativeWeights.index(before: cumulativeWeights.endIndex)
        let lowerIndex = upperIndex - 1
        let lowerPosition = cumulativeWeights[lowerIndex]
        let upperPosition = cumulativeWeights[upperIndex]
        guard upperPosition > lowerPosition else {
            return sorted[upperIndex].0
        }

        let fraction = (position - lowerPosition) / (upperPosition - lowerPosition)
        let lowerValue = Double(sorted[lowerIndex].0)
        let upperValue = Double(sorted[upperIndex].0)
        return Float(lowerValue + fraction * (upperValue - lowerValue))
    }

    static func weightedMedian(values: [Float], weights: [Float]) -> Float {
        weightedPercentile(values: values, weights: weights, percentile: 50)
    }

    static func weightedMedianAbsoluteDeviation(values: [Float], weights: [Float]) -> Float {
        let median = weightedMedian(values: values, weights: weights)
        return weightedMedian(
            values: values.map { abs($0 - median) },
            weights: weights
        )
    }

    static func weightedProportion(mask: [Bool], weights: [Float]) -> Float {
        guard mask.count == weights.count else {
            return .nan
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return .nan
        }
        let matchingWeight = zip(mask, weights).reduce(Float.zero) {
            $0 + ($1.0 ? $1.1 : 0)
        }
        return matchingWeight / totalWeight
    }
}

private extension SurfaceIntegrityProcessor {
    static func makeGroupValues(
        surfaceDetails: [MeshSurfaceDetail],
        heightResiduals: [Float],
        signedTiltData: [SignedTiltData]
    ) -> [SurfaceIntegrityFeatureValueSource: [Float]] {
        [
            .normalDeviation: surfaceDetails.map(\.angularDeviationDegrees),
            .heightResidual: heightResiduals,
            .absoluteHeightResidual: heightResiduals.map(abs),
            .signedTiltU: signedTiltData.map(\.tiltUDegrees),
            .signedTiltV: signedTiltData.map(\.tiltVDegrees),
            // Python applies np.linalg.norm to all three signed-tilt columns.
            .signedTiltMagnitude: signedTiltData.map {
                sqrt(
                    $0.tiltUDegrees * $0.tiltUDegrees
                        + $0.tiltVDegrees * $0.tiltVDegrees
                        + $0.tiltMagnitudeDegrees * $0.tiltMagnitudeDegrees
                )
            }
        ]
    }

    static func addFeatures(
        for group: SurfaceIntegrityFeatureGroupConfiguration,
        values: [Float],
        weights: [Float],
        to features: inout [SurfaceIntegrityWindowFeature: Float]
    ) {
        for feature in group.centralTendencyFeatures {
            let value: Float
            switch feature {
            case .mean:
                value = mean(values)
            case .median:
                value = weightedMedian(values: values, weights: weights)
            case .standardDeviation:
                value = populationStandardDeviation(values)
            case .medianAbsoluteDeviation:
                value = zeroIfNaN(
                    weightedMedianAbsoluteDeviation(values: values, weights: weights)
                )
            }
            features[SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)")] = value
        }

        for percentile in group.percentileFeatures {
            features[SurfaceIntegrityWindowFeature("\(group.label)_p\(percentile)")] =
                weightedPercentile(
                    values: values,
                    weights: weights,
                    percentile: Float(percentile)
                )
        }

        for tail in group.tailFeatures {
            let token = SurfaceIntegrityFeatureGroupConfiguration.columnToken(for: tail)
            let key = SurfaceIntegrityWindowFeature(
                "\(group.label)_proportion_above_\(token)"
            )
            features[key] = weightedProportion(
                mask: values.map { $0 > tail },
                weights: weights
            )
        }

        for feature in group.distributionShapeFeatures {
            let value: Float
            switch feature {
            case .skewness:
                value = zeroIfNaN(skewness(values))
            case .kurtosis:
                value = zeroIfNaN(excessKurtosis(values))
            case .entropy:
                value = zeroIfNaN(histogramEntropy(values))
            }
            features[SurfaceIntegrityWindowFeature("\(group.label)_\(feature.rawValue)")] = value
        }
    }

    static func mean(_ values: [Float]) -> Float {
        guard !values.isEmpty else {
            return .nan
        }
        return values.reduce(0, +) / Float(values.count)
    }

    static func populationStandardDeviation(_ values: [Float]) -> Float {
        let average = mean(values)
        guard average.isFinite else {
            return .nan
        }
        let variance = values.reduce(Float.zero) {
            let difference = $1 - average
            return $0 + difference * difference
        } / Float(values.count)
        return sqrt(variance)
    }

    static func skewness(_ values: [Float]) -> Float {
        let average = mean(values)
        guard average.isFinite else {
            return .nan
        }
        let count = Float(values.count)
        let secondMoment = values.reduce(Float.zero) {
            $0 + pow($1 - average, 2)
        } / count
        guard secondMoment > 0 else {
            return .nan
        }
        let thirdMoment = values.reduce(Float.zero) {
            $0 + pow($1 - average, 3)
        } / count
        return thirdMoment / pow(secondMoment, 1.5)
    }

    static func excessKurtosis(_ values: [Float]) -> Float {
        let average = mean(values)
        guard average.isFinite else {
            return .nan
        }
        let count = Float(values.count)
        let secondMoment = values.reduce(Float.zero) {
            $0 + pow($1 - average, 2)
        } / count
        guard secondMoment > 0 else {
            return .nan
        }
        let fourthMoment = values.reduce(Float.zero) {
            $0 + pow($1 - average, 4)
        } / count
        return fourthMoment / (secondMoment * secondMoment) - 3
    }

    static func histogramEntropy(_ values: [Float]) -> Float {
        guard let minimum = values.min(), let maximum = values.max(),
              minimum.isFinite, maximum.isFinite else {
            return .nan
        }

        let binCount = 30
        var lowerBound = minimum
        var upperBound = maximum
        if lowerBound == upperBound {
            lowerBound -= 0.5
            upperBound += 0.5
        }
        let binWidth = (upperBound - lowerBound) / Float(binCount)
        guard binWidth > 0, binWidth.isFinite else {
            return .nan
        }

        var counts = Array(repeating: Float(1e-10), count: binCount)
        for value in values {
            guard value.isFinite else {
                return .nan
            }
            let rawIndex = Int(floor((value - lowerBound) / binWidth))
            counts[min(max(rawIndex, 0), binCount - 1)] += 1
        }

        let total = counts.reduce(0, +)
        return counts.reduce(Float.zero) {
            let probability = $1 / total
            return $0 - probability * log(probability)
        }
    }

    static func zeroIfNaN(_ value: Float) -> Float {
        value.isNaN ? 0 : value
    }
}

private extension NumberFormatter {
    static let surfaceIntegrityColumn: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter
    }()
}
