//
//  SurfaceIntegrityLogisticRegression.swift
//  PointNMapShared
//

import Foundation

public enum SurfaceIntegrityModelFeature: Hashable, Sendable {
    case damageOverlapRatio
    case maximumDamageConfidence
    case windowFeature(SurfaceIntegrityWindowFeature)

    public var name: String {
        switch self {
        case .damageOverlapRatio:
            return "damage_prediction_model_issue_overlap"
        case .maximumDamageConfidence:
            return "damage_prediction_model_issue_confidence"
        case .windowFeature(let feature):
            return feature.rawValue
        }
    }
}

public struct SurfaceIntegrityLogisticRegressionTerm: Sendable, Equatable {
    public let feature: SurfaceIntegrityModelFeature
    public let coefficient: Double
    public let mean: Double
    public let scale: Double
    /// Value substituted before standardization when the feature is missing or non-finite.
    public let missingValue: Double?

    public init(
        feature: SurfaceIntegrityModelFeature,
        coefficient: Double,
        mean: Double,
        scale: Double,
        missingValue: Double?
    ) {
        self.feature = feature
        self.coefficient = coefficient
        self.mean = mean
        self.scale = scale
        self.missingValue = missingValue
    }
}

public struct SurfaceIntegrityPrediction: Sendable, Equatable {
    public let probability: Double
    public let isDisrupted: Bool
    public let logit: Double
}

public enum SurfaceIntegrityLogisticRegressionError: Error, LocalizedError {
    case emptyIdentifier
    case invalidSchemaVersion
    case emptyFeatureSchema
    case duplicateFeature(String)
    case invalidCoefficient(String)
    case invalidMean(String)
    case invalidScale(String)
    case invalidMissingValue(String)
    case invalidIntercept
    case invalidClassificationThreshold
    case missingFeature(String)

    public var errorDescription: String? {
        switch self {
        case .emptyIdentifier:
            return "The logistic-regression model identifier cannot be empty."
        case .invalidSchemaVersion:
            return "The logistic-regression schema version must be positive."
        case .emptyFeatureSchema:
            return "The logistic-regression model must declare at least one feature."
        case .duplicateFeature(let name):
            return "The logistic-regression feature schema contains duplicate feature '\(name)'."
        case .invalidCoefficient(let name):
            return "The coefficient for feature '\(name)' must be finite."
        case .invalidMean(let name):
            return "The standardization mean for feature '\(name)' must be finite."
        case .invalidScale(let name):
            return "The standardization scale for feature '\(name)' must be finite and greater than zero."
        case .invalidMissingValue(let name):
            return "The missing-value replacement for feature '\(name)' must be finite."
        case .invalidIntercept:
            return "The logistic-regression intercept must be finite."
        case .invalidClassificationThreshold:
            return "The classification threshold must be finite and between zero and one."
        case .missingFeature(let name):
            return "No finite input or missing-value replacement was provided for feature '\(name)'."
        }
    }
}

public protocol SurfaceIntegrityWindowPredicting: Sendable {
    var identifier: String { get }
    var schemaVersion: Int { get }
    var featureSchema: [SurfaceIntegrityModelFeature] { get }
    var classificationThreshold: Double { get }

    func predict(
        features: [SurfaceIntegrityModelFeature: Double]
    ) throws -> SurfaceIntegrityPrediction

    func predict(
        window: SurfaceIntegrityWindowAnalysis
    ) throws -> SurfaceIntegrityPrediction
}

public struct SurfaceIntegrityLogisticRegression: SurfaceIntegrityWindowPredicting {
    public let identifier: String
    public let schemaVersion: Int
    public let terms: [SurfaceIntegrityLogisticRegressionTerm]
    public let intercept: Double
    public let classificationThreshold: Double

    public init(
        identifier: String,
        schemaVersion: Int,
        terms: [SurfaceIntegrityLogisticRegressionTerm],
        intercept: Double,
        classificationThreshold: Double
    ) {
        self.identifier = identifier
        self.schemaVersion = schemaVersion
        self.terms = terms
        self.intercept = intercept
        self.classificationThreshold = classificationThreshold
    }

    public var featureSchema: [SurfaceIntegrityModelFeature] {
        terms.map(\.feature)
    }

    public func validate() throws {
        guard !identifier.isEmpty else {
            throw SurfaceIntegrityLogisticRegressionError.emptyIdentifier
        }
        guard schemaVersion > 0 else {
            throw SurfaceIntegrityLogisticRegressionError.invalidSchemaVersion
        }
        guard !terms.isEmpty else {
            throw SurfaceIntegrityLogisticRegressionError.emptyFeatureSchema
        }
        guard intercept.isFinite else {
            throw SurfaceIntegrityLogisticRegressionError.invalidIntercept
        }
        guard classificationThreshold.isFinite,
              (0...1).contains(classificationThreshold) else {
            throw SurfaceIntegrityLogisticRegressionError.invalidClassificationThreshold
        }

        var encounteredFeatures = Set<SurfaceIntegrityModelFeature>()
        for term in terms {
            let name = term.feature.name
            guard encounteredFeatures.insert(term.feature).inserted else {
                throw SurfaceIntegrityLogisticRegressionError.duplicateFeature(name)
            }
            guard term.coefficient.isFinite else {
                throw SurfaceIntegrityLogisticRegressionError.invalidCoefficient(name)
            }
            guard term.mean.isFinite else {
                throw SurfaceIntegrityLogisticRegressionError.invalidMean(name)
            }
            guard term.scale.isFinite, term.scale > 0 else {
                throw SurfaceIntegrityLogisticRegressionError.invalidScale(name)
            }
            if let missingValue = term.missingValue, !missingValue.isFinite {
                throw SurfaceIntegrityLogisticRegressionError.invalidMissingValue(name)
            }
        }
    }

    public func predict(
        features: [SurfaceIntegrityModelFeature: Double]
    ) throws -> SurfaceIntegrityPrediction {
        try validate()

        var logit = intercept
        for term in terms {
            let suppliedValue = features[term.feature]
            let rawValue: Double
            if let suppliedValue, suppliedValue.isFinite {
                rawValue = suppliedValue
            } else if let missingValue = term.missingValue, missingValue.isFinite {
                rawValue = missingValue
            } else {
                throw SurfaceIntegrityLogisticRegressionError.missingFeature(term.feature.name)
            }

            let standardizedValue = (rawValue - term.mean) / term.scale
            logit += standardizedValue * term.coefficient
        }

        let probability: Double
        if logit >= 0 {
            probability = 1 / (1 + exp(-logit))
        } else {
            let exponential = exp(logit)
            probability = exponential / (1 + exponential)
        }
        return SurfaceIntegrityPrediction(
            probability: probability,
            isDisrupted: probability >= classificationThreshold,
            logit: logit
        )
    }

    public func predict(
        window: SurfaceIntegrityWindowAnalysis
    ) throws -> SurfaceIntegrityPrediction {
        var features: [SurfaceIntegrityModelFeature: Double] = [
            .damageOverlapRatio: Double(window.damageOverlapRatio),
            .maximumDamageConfidence: Double(window.maximumDamageConfidence)
        ]
        for (feature, value) in window.features.values {
            features[.windowFeature(feature)] = Double(value)
        }
        return try predict(features: features)
    }

    public func predict(
        windows: [SurfaceIntegrityWindowAnalysis]
    ) throws -> [SurfaceIntegrityPrediction] {
        try windows.map(predict(window:))
    }
}
