//
//  SlidingWindowMembershipCountExtension.swift
//  PointNMapShared
//

import Foundation
import Metal
import simd

public struct SlidingWindowMembershipCountResult: Sendable, Equatable {
    public let windowCounts: [UInt32]
    public let windowOffsets: [UInt32]

    public init(windowCounts: [UInt32], windowOffsets: [UInt32]) {
        self.windowCounts = windowCounts
        self.windowOffsets = windowOffsets
    }

    public var windowCount: Int {
        windowCounts.count
    }

    public var membershipCount: Int {
        Int(windowOffsets.last ?? 0)
    }
}

public extension SurfaceIntegrityProcessor {
    /// Counts centroid memberships on Metal. CSR scatter is intentionally deferred to a later stage.
    func computeSlidingWindowMembershipCounts(
        uvCoordinates: [SIMD2<Float>],
        gridOriginU: Float,
        gridOriginV: Float,
        gridShape: SIMD2<Int32>,
        cellSize: Float = 0.27,
        stride: Float = 0.09
    ) throws -> SlidingWindowMembershipCountResult {
        guard cellSize.isFinite, cellSize > 0 else {
            throw SlidingWindowGridError.invalidCellSize
        }
        guard stride.isFinite, stride > 0 else {
            throw SlidingWindowGridError.invalidStride
        }
        guard gridShape.x >= 0, gridShape.y >= 0,
              let windowCount = Int(exactly: Int64(gridShape.x) * Int64(gridShape.y)) else {
            throw SlidingWindowGridError.gridDimensionOverflow
        }
        guard let centroidCount = UInt32(exactly: uvCoordinates.count),
              let gridWidth = UInt32(exactly: gridShape.x),
              let gridHeight = UInt32(exactly: gridShape.y),
              let candidateSpan = UInt32(exactly: Int(ceil(cellSize / stride))) else {
            throw SlidingWindowGridError.membershipIndexOverflow
        }

        guard windowCount > 0, !uvCoordinates.isEmpty else {
            let counts = Array(repeating: UInt32.zero, count: windowCount)
            return SlidingWindowMembershipCountResult(
                windowCounts: counts,
                windowOffsets: try Self.exclusivePrefixSum(counts)
            )
        }
        guard let coordinateBuffer = device.makeBuffer(
            bytes: uvCoordinates,
            length: MemoryLayout<SIMD2<Float>>.stride * uvCoordinates.count,
            options: .storageModeShared
        ), let countBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride * windowCount,
            options: .storageModeShared
        ), let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }

        countBuffer.contents().bindMemory(to: UInt32.self, capacity: windowCount)
            .initialize(repeating: 0, count: windowCount)
        var origin = SIMD2<Float>(gridOriginU, gridOriginV)
        var unsignedGridShape = SIMD2<UInt32>(gridWidth, gridHeight)
        var mutableCellSize = cellSize
        var mutableStride = stride
        var mutableCentroidCount = centroidCount
        var mutableCandidateSpan = candidateSpan

        encoder.setComputePipelineState(slidingWindowMembershipCountPipeline)
        encoder.setBuffer(coordinateBuffer, offset: 0, index: 0)
        encoder.setBytes(&mutableCentroidCount, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&origin, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        encoder.setBytes(&unsignedGridShape, length: MemoryLayout<SIMD2<UInt32>>.stride, index: 3)
        encoder.setBytes(&mutableCellSize, length: MemoryLayout<Float>.stride, index: 4)
        encoder.setBytes(&mutableStride, length: MemoryLayout<Float>.stride, index: 5)
        encoder.setBytes(&mutableCandidateSpan, length: MemoryLayout<UInt32>.stride, index: 6)
        encoder.setBuffer(countBuffer, offset: 0, index: 7)
        let threadgroupWidth = min(
            slidingWindowMembershipCountPipeline.maxTotalThreadsPerThreadgroup,
            256
        )
        encoder.dispatchThreads(
            MTLSize(width: uvCoordinates.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw SurfaceIntegrityProcessorError.unableToProcessBufferData
        }

        let countsPointer = countBuffer.contents().bindMemory(to: UInt32.self, capacity: windowCount)
        let counts = Array(UnsafeBufferPointer(start: countsPointer, count: windowCount))
        return SlidingWindowMembershipCountResult(
            windowCounts: counts,
            windowOffsets: try Self.exclusivePrefixSum(counts)
        )
    }

    private static func exclusivePrefixSum(_ counts: [UInt32]) throws -> [UInt32] {
        var offsets: [UInt32] = [0]
        offsets.reserveCapacity(counts.count + 1)
        var total: UInt32 = 0
        for count in counts {
            let (nextTotal, overflow) = total.addingReportingOverflow(count)
            guard !overflow else {
                throw SlidingWindowGridError.membershipIndexOverflow
            }
            total = nextTotal
            offsets.append(total)
        }
        return offsets
    }
}
