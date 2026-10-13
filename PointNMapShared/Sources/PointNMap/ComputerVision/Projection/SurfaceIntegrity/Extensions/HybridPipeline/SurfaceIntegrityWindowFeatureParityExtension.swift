import Foundation

public extension SurfaceIntegrityProcessor {
    static func compareWindowFeatures(
        cpu: [SurfaceIntegrityWindowFeatures],
        staged: [SurfaceIntegrityWindowFeatures],
        retainedWindowIndices: [Int],
        gpuSupportedColumns: Set<SurfaceIntegrityWindowFeature>,
        absoluteTolerance: Float = 1e-4,
        relativeTolerance: Float = 1e-3,
        detailLimit: Int = 5
    ) -> SurfaceIntegrityWindowFeatureParitySummary {
        var compared = 0
        var mismatches = 0
        var gpuMismatches = 0
        var cpuMismatches = 0
        var maxAbsolute: Float = 0
        var maxRelative: Float = 0
        var gpuDetails: [SurfaceIntegrityWindowFeatureParityDetail] = []
        var cpuDetails: [SurfaceIntegrityWindowFeatureParityDetail] = []
        let windowCount = min(cpu.count, staged.count, retainedWindowIndices.count)
        for window in 0..<windowCount {
            for column in cpu[window].orderedColumns {
                compared += 1
                let lhs = cpu[window][column]
                let rhs = staged[window][column]
                let matchingSpecial = (lhs.isNaN && rhs.isNaN)
                    || (lhs.isInfinite && rhs.isInfinite && lhs.sign == rhs.sign)
                let absolute = matchingSpecial ? 0 : abs(lhs - rhs)
                let relative = matchingSpecial ? 0 : absolute / max(max(abs(lhs), abs(rhs)), 1e-12)
                let matches = matchingSpecial
                    || (lhs.isFinite && rhs.isFinite
                        && (absolute <= absoluteTolerance || relative <= relativeTolerance))
                maxAbsolute = max(maxAbsolute, absolute.isFinite ? absolute : .infinity)
                maxRelative = max(maxRelative, relative.isFinite ? relative : .infinity)
                guard !matches else { continue }
                mismatches += 1
                let gpuSupported = gpuSupportedColumns.contains(column)
                if gpuSupported { gpuMismatches += 1 } else { cpuMismatches += 1 }
                let detail = SurfaceIntegrityWindowFeatureParityDetail(
                        retainedWindowIndex: window,
                        originalWindowIndex: retainedWindowIndices[window],
                        feature: column,
                        cpuValue: lhs,
                        stagedValue: rhs,
                        absoluteError: absolute,
                        relativeError: relative,
                        isGPUSupported: gpuSupported
                    )
                if gpuSupported { gpuDetails.append(detail) } else { cpuDetails.append(detail) }
            }
        }
        mismatches += abs(cpu.count - staged.count)
        let details: [SurfaceIntegrityWindowFeatureParityDetail]
        if !gpuDetails.isEmpty, !cpuDetails.isEmpty, detailLimit > 1 {
            var selected = [gpuDetails[0], cpuDetails[0]]
            selected.append(contentsOf: (gpuDetails.dropFirst() + cpuDetails.dropFirst())
                .prefix(detailLimit - selected.count))
            details = selected
        } else {
            details = Array((gpuDetails + cpuDetails).prefix(detailLimit))
        }
        return .init(
            hasParity: mismatches == 0 && cpu.count == staged.count,
            comparedValueCount: compared,
            totalMismatchCount: mismatches,
            gpuSupportedMismatchCount: gpuMismatches,
            cpuOnlyMismatchCount: cpuMismatches,
            maximumAbsoluteError: maxAbsolute,
            maximumRelativeError: maxRelative,
            details: details
        )
    }

    static func logWindowFeatureParity(
        _ summary: SurfaceIntegrityWindowFeatureParitySummary,
        originalWindowCount: Int,
        retainedWindowCount: Int,
        polygonCount: Int,
        membershipCount: Int,
        timings: SurfaceIntegrityGPUWindowFeatureTimings,
        deviceName: String
    ) {
        print("[WINDOW_FEATURE:GPU_PARITY] within_tolerance=\(summary.hasParity) original_window_count=\(originalWindowCount) retained_window_count=\(retainedWindowCount) polygon_count=\(polygonCount) membership_count=\(membershipCount) compared_values=\(summary.comparedValueCount) mismatch_count=\(summary.totalMismatchCount) gpu_mismatch_count=\(summary.gpuSupportedMismatchCount) cpu_only_mismatch_count=\(summary.cpuOnlyMismatchCount) max_absolute_error=\(summary.maximumAbsoluteError) max_relative_error=\(summary.maximumRelativeError) cpu_reference_ms=\(timings.cpuReferenceMilliseconds) reduction_ms=\(timings.reductionMilliseconds) entropy_ms=\(timings.entropyMilliseconds) order_statistics_ms=\(timings.orderStatisticsMilliseconds) assembly_ms=\(timings.assemblyMilliseconds) staged_total_ms=\(timings.totalMilliseconds) device=\(deviceName)")
        for detail in summary.details {
            print("[WINDOW_FEATURE:GPU_PARITY:DETAIL] retained_window=\(detail.retainedWindowIndex) original_window=\(detail.originalWindowIndex) feature=\(detail.feature.rawValue) cpu=\(detail.cpuValue) staged=\(detail.stagedValue) absolute_error=\(detail.absoluteError) relative_error=\(detail.relativeError) gpu_supported=\(detail.isGPUSupported)")
        }
    }
}
