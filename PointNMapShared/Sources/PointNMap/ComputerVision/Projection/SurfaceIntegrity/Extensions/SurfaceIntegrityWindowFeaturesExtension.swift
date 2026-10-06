//
//  SurfaceIntegrityWindowFeaturesExtension.swift
//  PointNMapShared
//

import Foundation

public enum SurfaceIntegrityWindowFeature: String, CaseIterable, Sendable {
    case normalDeviationMean = "normal_deviation_mean"
    case normalDeviationMedian = "normal_deviation_median"
    case normalDeviationStandardDeviation = "normal_deviation_std"
    case normalDeviationMedianAbsoluteDeviation = "normal_deviation_mad"
    case normalDeviationP75 = "normal_deviation_p75"
    case normalDeviationP90 = "normal_deviation_p90"
    case normalDeviationProportionAbove5 = "normal_deviation_proportion_above_5"
    case normalDeviationProportionAbove10 = "normal_deviation_proportion_above_10"
    case normalDeviationProportionAbove20 = "normal_deviation_proportion_above_20"
    case normalDeviationSkewness = "normal_deviation_skewness"
    case normalDeviationKurtosis = "normal_deviation_kurtosis"
    case normalDeviationEntropy = "normal_deviation_entropy"

    case heightResidualsStandardDeviation = "height_residuals_std"
    case heightResidualsMedianAbsoluteDeviation = "height_residuals_mad"
    case heightResidualsSkewness = "height_residuals_skewness"
    case heightResidualsKurtosis = "height_residuals_kurtosis"
    case heightResidualsEntropy = "height_residuals_entropy"

    case heightResidualsAbsoluteMean = "height_residuals_absolute_mean"
    case heightResidualsAbsoluteMedian = "height_residuals_absolute_median"
    case heightResidualsAbsoluteP75 = "height_residuals_absolute_p75"
    case heightResidualsAbsoluteP90 = "height_residuals_absolute_p90"

    case signedTiltUStandardDeviation = "signed_tilt_u_std"
    case signedTiltUMedianAbsoluteDeviation = "signed_tilt_u_mad"
    case signedTiltUSkewness = "signed_tilt_u_skewness"
    case signedTiltUKurtosis = "signed_tilt_u_kurtosis"
    case signedTiltUEntropy = "signed_tilt_u_entropy"

    case signedTiltVStandardDeviation = "signed_tilt_v_std"
    case signedTiltVMedianAbsoluteDeviation = "signed_tilt_v_mad"
    case signedTiltVSkewness = "signed_tilt_v_skewness"
    case signedTiltVKurtosis = "signed_tilt_v_kurtosis"
    case signedTiltVEntropy = "signed_tilt_v_entropy"

    case signedTiltMagnitudeMean = "signed_tilt_magnitude_mean"
    case signedTiltMagnitudeMedian = "signed_tilt_magnitude_median"
    case signedTiltMagnitudeP75 = "signed_tilt_magnitude_p75"
    case signedTiltMagnitudeP90 = "signed_tilt_magnitude_p90"

    case numberOfPolygons = "num_polygons"
    case totalSidewalkArea = "total_sidewalk_area"
    case averagePolygonArea = "average_polygon_area"
    case polygonDensity = "polygon_density"
    case heightFromGround = "height_from_ground"
}

public struct SurfaceIntegrityWindowFeatures: Sendable, Equatable {
    public let values: [SurfaceIntegrityWindowFeature: Float]

    public init(values: [SurfaceIntegrityWindowFeature: Float]) {
        self.values = values
    }

    public subscript(feature: SurfaceIntegrityWindowFeature) -> Float {
        values[feature] ?? 0
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
        heightFromGround: Float?
    ) throws -> SurfaceIntegrityWindowFeatures {
        guard surfaceDetails.count == heightResiduals.count,
              surfaceDetails.count == signedTiltData.count else {
            throw SurfaceIntegrityWindowFeatureError.mismatchedInputCounts
        }

        var features = Dictionary(
            uniqueKeysWithValues: SurfaceIntegrityWindowFeature.allCases.map { ($0, Float.zero) }
        )
        features[.heightFromGround] = heightFromGround ?? .nan

        guard !surfaceDetails.isEmpty else {
            return SurfaceIntegrityWindowFeatures(values: features)
        }

        let areas = surfaceDetails.map(\.area)
        let normalDeviations = surfaceDetails.map(\.angularDeviationDegrees)
        let absoluteHeightResiduals = heightResiduals.map(abs)
        let signedTiltU = signedTiltData.map(\.tiltUDegrees)
        let signedTiltV = signedTiltData.map(\.tiltVDegrees)

        // The training pipeline uses the norm of all three tilt columns here.
        let signedTiltMagnitude = signedTiltData.map {
            sqrt(
                $0.tiltUDegrees * $0.tiltUDegrees
                    + $0.tiltVDegrees * $0.tiltVDegrees
                    + $0.tiltMagnitudeDegrees * $0.tiltMagnitudeDegrees
            )
        }

        addNormalDeviationFeatures(
            values: normalDeviations,
            weights: areas,
            to: &features
        )
        addDistributionFeatures(
            values: heightResiduals,
            weights: areas,
            standardDeviation: .heightResidualsStandardDeviation,
            medianAbsoluteDeviation: .heightResidualsMedianAbsoluteDeviation,
            skewness: .heightResidualsSkewness,
            kurtosis: .heightResidualsKurtosis,
            entropy: .heightResidualsEntropy,
            to: &features
        )
        addAbsoluteHeightResidualFeatures(
            values: absoluteHeightResiduals,
            weights: areas,
            to: &features
        )
        addDistributionFeatures(
            values: signedTiltU,
            weights: areas,
            standardDeviation: .signedTiltUStandardDeviation,
            medianAbsoluteDeviation: .signedTiltUMedianAbsoluteDeviation,
            skewness: .signedTiltUSkewness,
            kurtosis: .signedTiltUKurtosis,
            entropy: .signedTiltUEntropy,
            to: &features
        )
        addDistributionFeatures(
            values: signedTiltV,
            weights: areas,
            standardDeviation: .signedTiltVStandardDeviation,
            medianAbsoluteDeviation: .signedTiltVMedianAbsoluteDeviation,
            skewness: .signedTiltVSkewness,
            kurtosis: .signedTiltVKurtosis,
            entropy: .signedTiltVEntropy,
            to: &features
        )
        addTiltMagnitudeFeatures(
            values: signedTiltMagnitude,
            weights: areas,
            to: &features
        )

        let totalArea = areas.reduce(0, +)
        features[.numberOfPolygons] = Float(surfaceDetails.count)
        features[.totalSidewalkArea] = totalArea
        features[.averagePolygonArea] = mean(areas)
        features[.polygonDensity] = totalArea > 0 ? Float(surfaceDetails.count) / totalArea : 0

        return SurfaceIntegrityWindowFeatures(values: features)
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
        let deviations = values.map { abs($0 - median) }
        return weightedMedian(values: deviations, weights: weights)
    }

    static func weightedProportion(mask: [Bool], weights: [Float]) -> Float {
        guard mask.count == weights.count else {
            return .nan
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return .nan
        }
        let matchingWeight = zip(mask, weights).reduce(Float.zero) { result, item in
            result + (item.0 ? item.1 : 0)
        }
        return matchingWeight / totalWeight
    }
}

private extension SurfaceIntegrityProcessor {
    static func addNormalDeviationFeatures(
        values: [Float],
        weights: [Float],
        to features: inout [SurfaceIntegrityWindowFeature: Float]
    ) {
        features[.normalDeviationMean] = mean(values)
        features[.normalDeviationMedian] = weightedMedian(values: values, weights: weights)
        features[.normalDeviationStandardDeviation] = populationStandardDeviation(values)
        features[.normalDeviationMedianAbsoluteDeviation] =
            zeroIfNaN(weightedMedianAbsoluteDeviation(values: values, weights: weights))
        features[.normalDeviationP75] =
            weightedPercentile(values: values, weights: weights, percentile: 75)
        features[.normalDeviationP90] =
            weightedPercentile(values: values, weights: weights, percentile: 90)
        features[.normalDeviationProportionAbove5] =
            weightedProportion(mask: values.map { $0 > 5 }, weights: weights)
        features[.normalDeviationProportionAbove10] =
            weightedProportion(mask: values.map { $0 > 10 }, weights: weights)
        features[.normalDeviationProportionAbove20] =
            weightedProportion(mask: values.map { $0 > 20 }, weights: weights)
        features[.normalDeviationSkewness] = zeroIfNaN(skewness(values))
        features[.normalDeviationKurtosis] = zeroIfNaN(excessKurtosis(values))
        features[.normalDeviationEntropy] = zeroIfNaN(histogramEntropy(values))
    }

    static func addDistributionFeatures(
        values: [Float],
        weights: [Float],
        standardDeviation: SurfaceIntegrityWindowFeature,
        medianAbsoluteDeviation: SurfaceIntegrityWindowFeature,
        skewness skewnessFeature: SurfaceIntegrityWindowFeature,
        kurtosis kurtosisFeature: SurfaceIntegrityWindowFeature,
        entropy entropyFeature: SurfaceIntegrityWindowFeature,
        to features: inout [SurfaceIntegrityWindowFeature: Float]
    ) {
        features[standardDeviation] = populationStandardDeviation(values)
        features[medianAbsoluteDeviation] =
            zeroIfNaN(weightedMedianAbsoluteDeviation(values: values, weights: weights))
        features[skewnessFeature] = zeroIfNaN(skewness(values))
        features[kurtosisFeature] = zeroIfNaN(excessKurtosis(values))
        features[entropyFeature] = zeroIfNaN(histogramEntropy(values))
    }

    static func addAbsoluteHeightResidualFeatures(
        values: [Float],
        weights: [Float],
        to features: inout [SurfaceIntegrityWindowFeature: Float]
    ) {
        features[.heightResidualsAbsoluteMean] = mean(values)
        features[.heightResidualsAbsoluteMedian] = weightedMedian(values: values, weights: weights)
        features[.heightResidualsAbsoluteP75] =
            weightedPercentile(values: values, weights: weights, percentile: 75)
        features[.heightResidualsAbsoluteP90] =
            weightedPercentile(values: values, weights: weights, percentile: 90)
    }

    static func addTiltMagnitudeFeatures(
        values: [Float],
        weights: [Float],
        to features: inout [SurfaceIntegrityWindowFeature: Float]
    ) {
        features[.signedTiltMagnitudeMean] = mean(values)
        features[.signedTiltMagnitudeMedian] = weightedMedian(values: values, weights: weights)
        features[.signedTiltMagnitudeP75] =
            weightedPercentile(values: values, weights: weights, percentile: 75)
        features[.signedTiltMagnitudeP90] =
            weightedPercentile(values: values, weights: weights, percentile: 90)
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
        let variance = values.reduce(Float.zero) { result, value in
            let difference = value - average
            return result + difference * difference
        } / Float(values.count)
        return sqrt(variance)
    }

    // These biased central moments match scipy.stats skew/kurtosis defaults.
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
            let index = min(max(rawIndex, 0), binCount - 1)
            counts[index] += 1
        }

        let total = counts.reduce(0, +)
        return counts.reduce(Float.zero) { entropy, count in
            let probability = count / total
            return entropy - probability * log(probability)
        }
    }

    static func zeroIfNaN(_ value: Float) -> Float {
        value.isNaN ? 0 : value
    }
}
