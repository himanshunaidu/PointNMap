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

    /// Parameters exported from the second sklearn placeholder model.
    /// Features not listed here are intentionally ignored during inference.
    public static let placeholderLogisticRegression2 = SurfaceIntegrityLogisticRegression(
        identifier: "surface-integrity-placeholder-v2",
        schemaVersion: 2,
        terms: [
            windowTerm("normal_deviation_mean", -0.4525534356078896, 7.062221258807511, 5.725402558286666),
            windowTerm("normal_deviation_median", -0.27289325343020215, 5.673470484482631, 4.748458505759306),
            windowTerm("normal_deviation_std", 0.24485819198752523, 4.394094927319742, 4.102079974138102),
            windowTerm("normal_deviation_mad", -0.005912123689155021, 2.1734432557495245, 2.0859871572441744),
            windowTerm("normal_deviation_p75", -0.13237364883638206, 8.615683655496122, 7.439663177284939),
            windowTerm("normal_deviation_p90", -0.10128916737441197, 12.087428751861479, 10.56978000903731),
            windowTerm("normal_deviation_proportion_above_5", 0.27668450374854353, 0.4363540805220845, 0.28581180907378817),
            windowTerm("normal_deviation_proportion_above_10", -0.005896340042764673, 0.1700285940009546, 0.23266148397174638),
            windowTerm("normal_deviation_proportion_above_20", 0.2942491966954483, 0.04614260417664438, 0.1209185993368325),
            windowTerm("normal_deviation_skewness", -0.0520409181100595, 0.9820016290629889, 0.9618281115119373),
            windowTerm("normal_deviation_kurtosis", 0.1249174380619934, 1.7577727695094463, 6.848674701393602),
            windowTerm("normal_deviation_entropy", 0.14938884012316658, 2.8254971389968557, 0.34919526743728574),
            windowTerm("height_residuals_std", 0.04064329873669177, 0.003211695056817562, 0.006311854580115707),
            windowTerm("height_residuals_mad", 0.16602202578249017, 0.0019420101265420402, 0.004205339884822755),
            windowTerm("height_residuals_skewness", 0.021662990374723773, 0.05314690687661724, 0.7058176385649388),
            windowTerm("height_residuals_kurtosis", -0.006688121375419371, 0.02154504266996985, 2.4347624857660284),
            windowTerm("height_residuals_entropy", -0.10841641712605977, 3.0352715655136455, 0.28091535154655783),
            windowTerm("height_residuals_absolute_mean", 0.19692837558198956, 0.008634878769634178, 0.010459318767209673),
            windowTerm("height_residuals_absolute_median", 0.005552371139428901, 0.00833571622862364, 0.010435630306519608),
            windowTerm("height_residuals_absolute_p75", -0.022919149886281277, 0.010257717871373627, 0.0128631223297248),
            windowTerm("height_residuals_absolute_p90", 0.05338636950834884, 0.011995198353840877, 0.015272392419891747),
            windowTerm("signed_tilt_u_std", -0.6263734134948873, 68.73597723829768, 78.51833712346841),
            windowTerm("signed_tilt_u_mad", -0.048342490371173004, 6.216938693639915, 14.316707039286426),
            windowTerm("signed_tilt_u_skewness", -0.03396309774077205, -0.009512690190813397, 0.922969005481601),
            windowTerm("signed_tilt_u_kurtosis", -0.010945744438499948, 0.108959730492894, 5.921553952742875),
            windowTerm("signed_tilt_u_entropy", -0.5953376987104377, 2.059132710971663, 1.0359013162780017),
            windowTerm("signed_tilt_v_std", 0.2627865621127378, 65.56162398149571, 77.086671162827),
            windowTerm("signed_tilt_v_mad", -0.012871766642653656, 3.3818640975205834, 11.904530416832872),
            windowTerm("signed_tilt_v_skewness", 0.03645577754058493, -0.005038857462438101, 1.4365797646491654),
            windowTerm("signed_tilt_v_kurtosis", 0.046983045742383406, 1.8719907442671064, 6.881545937213798),
            windowTerm("signed_tilt_v_entropy", 0.8014851417634662, 1.8779557428156355, 0.9875586021952578),
            windowTerm("signed_tilt_magnitude_mean", 2.484602649000087, 153.85435635740288, 86.73803080640887),
            windowTerm("signed_tilt_magnitude_median", -0.7903311808751577, 154.70223109423435, 87.41487392992867),
            windowTerm("signed_tilt_magnitude_p75", -2.014531930367664, 157.33076622445293, 87.6059271966577),
            windowTerm("signed_tilt_magnitude_p90", 0.5389200228883934, 159.13130250931852, 87.71788194105748),
            .init(
                feature: .damageOverlapRatio,
                coefficient: 0.6864087152318423,
                mean: 0.41737614458358274,
                scale: 0.4217959681181562,
                missingValue: 0
            ),
            .init(
                feature: .maximumDamageConfidence,
                coefficient: 0.5014038228008307,
                mean: 0.1101860564644111,
                scale: 0.16397857264713334,
                missingValue: 0
            )
        ],
        intercept: -2.0442088686876745,
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
