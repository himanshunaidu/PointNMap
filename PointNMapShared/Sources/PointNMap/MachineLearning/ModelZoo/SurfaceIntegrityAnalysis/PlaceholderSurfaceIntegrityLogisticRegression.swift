//
//  PlaceholderSurfaceIntegrityLogisticRegression.swift
//  PointNMapShared
//

import Foundation

public enum SurfaceIntegrityAnalysisModelZoo {
    /// Demonstrates every value that must be replaced when trained parameters are exported.
    /// These numbers are placeholders and must not be interpreted as a validated model.
    public static let placeholderLogisticRegression = SurfaceIntegrityLogisticRegression(
        identifier: "surface-integrity-placeholder-v1",
        schemaVersion: 1,
        terms: [
            .init(
                feature: .damageOverlapRatio,
                coefficient: 2.0,
                mean: 0.10,
                scale: 0.20,
                missingValue: 0
            ),
            .init(
                feature: .maximumDamageConfidence,
                coefficient: 1.0,
                mean: 0.50,
                scale: 0.25,
                missingValue: 0
            ),

            windowTerm("normal_deviation_mean", 0.10, 5, 5),
            windowTerm("normal_deviation_median", 0.10, 5, 5),
            windowTerm("normal_deviation_std", 0.10, 3, 3),
            windowTerm("normal_deviation_mad", 0.10, 2, 2),
            windowTerm("normal_deviation_p75", 0.10, 8, 6),
            windowTerm("normal_deviation_p90", 0.10, 12, 8),
            windowTerm("normal_deviation_proportion_above_5", 0.10, 0.25, 0.20),
            windowTerm("normal_deviation_proportion_above_10", 0.10, 0.10, 0.15),
            windowTerm("normal_deviation_proportion_above_20", 0.10, 0.03, 0.08),
            windowTerm("normal_deviation_skewness", 0.05, 0, 1),
            windowTerm("normal_deviation_kurtosis", 0.05, 0, 2),
            windowTerm("normal_deviation_entropy", 0.05, 1, 0.5),

            windowTerm("height_residuals_std", 0.10, 0.01, 0.01),
            windowTerm("height_residuals_mad", 0.10, 0.005, 0.005),
            windowTerm("height_residuals_skewness", 0.05, 0, 1),
            windowTerm("height_residuals_kurtosis", 0.05, 0, 2),
            windowTerm("height_residuals_entropy", 0.05, 1, 0.5),

            windowTerm("height_residuals_absolute_mean", 0.10, 0.01, 0.01),
            windowTerm("height_residuals_absolute_median", 0.10, 0.005, 0.005),
            windowTerm("height_residuals_absolute_p75", 0.10, 0.015, 0.015),
            windowTerm("height_residuals_absolute_p90", 0.10, 0.025, 0.025),

            windowTerm("signed_tilt_u_std", 0.05, 3, 3),
            windowTerm("signed_tilt_u_mad", 0.05, 2, 2),
            windowTerm("signed_tilt_u_skewness", 0.05, 0, 1),
            windowTerm("signed_tilt_u_kurtosis", 0.05, 0, 2),
            windowTerm("signed_tilt_u_entropy", 0.05, 1, 0.5),

            windowTerm("signed_tilt_v_std", 0.05, 3, 3),
            windowTerm("signed_tilt_v_mad", 0.05, 2, 2),
            windowTerm("signed_tilt_v_skewness", 0.05, 0, 1),
            windowTerm("signed_tilt_v_kurtosis", 0.05, 0, 2),
            windowTerm("signed_tilt_v_entropy", 0.05, 1, 0.5),

            windowTerm("signed_tilt_magnitude_mean", 0.05, 90, 15),
            windowTerm("signed_tilt_magnitude_median", 0.05, 90, 15),
            windowTerm("signed_tilt_magnitude_p75", 0.05, 100, 20),
            windowTerm("signed_tilt_magnitude_p90", 0.05, 110, 25),

            windowTerm("num_polygons", -0.05, 20, 10),
            windowTerm("total_sidewalk_area", 0.05, 0.01, 0.01),
            windowTerm("average_polygon_area", 0.05, 0.0005, 0.0005),
            windowTerm("polygon_density", 0.05, 2_000, 1_000),
            windowTerm("height_from_ground", 0.05, 1.2, 0.3, missingValue: 1.2)
        ],
        intercept: -1.0,
        classificationThreshold: 0.5
    )

    private static func windowTerm(
        _ name: String,
        _ coefficient: Double,
        _ mean: Double,
        _ scale: Double,
        missingValue: Double = 0
    ) -> SurfaceIntegrityLogisticRegressionTerm {
        SurfaceIntegrityLogisticRegressionTerm(
            feature: .windowFeature(SurfaceIntegrityWindowFeature(name)),
            coefficient: coefficient,
            mean: mean,
            scale: scale,
            missingValue: missingValue
        )
    }
}
