//
//  SurfaceIntegrity.metal
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/9/26.
//

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>
using namespace metal;
#import "ShaderTypes.h"

kernel void countSlidingWindowMemberships(
    device const float2* uvCoordinates [[buffer(0)]],
    constant uint& centroidCount [[buffer(1)]],
    constant float2& gridOrigin [[buffer(2)]],
    constant uint2& gridShape [[buffer(3)]],
    constant float& cellSize [[buffer(4)]],
    constant float& stride [[buffer(5)]],
    constant uint& candidateSpan [[buffer(6)]],
    device atomic_uint* windowCounts [[buffer(7)]],
    uint centroidIndex [[thread_position_in_grid]]
) {
    if (centroidIndex >= centroidCount) {
        return;
    }

    float2 coordinate = uvCoordinates[centroidIndex];
    int2 baseIndex = int2(floor((coordinate - gridOrigin) / stride));
    for (uint uOffset = 0; uOffset < candidateSpan; ++uOffset) {
        int uIndex = baseIndex.x - int(uOffset);
        if (uIndex < 0 || uIndex >= int(gridShape.x)) {
            continue;
        }
        for (uint vOffset = 0; vOffset < candidateSpan; ++vOffset) {
            int vIndex = baseIndex.y - int(vOffset);
            if (vIndex < 0 || vIndex >= int(gridShape.y)) {
                continue;
            }

            float2 windowMinimum = gridOrigin + float2(uIndex, vIndex) * stride;
            float2 windowMaximum = windowMinimum + cellSize;
            if (coordinate.x >= windowMinimum.x && coordinate.x < windowMaximum.x &&
                coordinate.y >= windowMinimum.y && coordinate.y < windowMaximum.y) {
                uint windowIndex = uint(uIndex) * gridShape.y + uint(vIndex);
                atomic_fetch_add_explicit(&windowCounts[windowIndex], 1, memory_order_relaxed);
            }
        }
    }
}

kernel void scatterSlidingWindowMemberships(
    device const float2* uvCoordinates [[buffer(0)]],
    constant uint& centroidCount [[buffer(1)]],
    constant float2& gridOrigin [[buffer(2)]],
    constant uint2& gridShape [[buffer(3)]],
    constant float& cellSize [[buffer(4)]],
    constant float& stride [[buffer(5)]],
    constant uint& candidateSpan [[buffer(6)]],
    device atomic_uint* windowWriteCursors [[buffer(7)]],
    device uint* meshIndices [[buffer(8)]],
    uint centroidIndex [[thread_position_in_grid]]
) {
    if (centroidIndex >= centroidCount) {
        return;
    }

    float2 coordinate = uvCoordinates[centroidIndex];
    int2 baseIndex = int2(floor((coordinate - gridOrigin) / stride));
    for (uint uOffset = 0; uOffset < candidateSpan; ++uOffset) {
        int uIndex = baseIndex.x - int(uOffset);
        if (uIndex < 0 || uIndex >= int(gridShape.x)) {
            continue;
        }
        for (uint vOffset = 0; vOffset < candidateSpan; ++vOffset) {
            int vIndex = baseIndex.y - int(vOffset);
            if (vIndex < 0 || vIndex >= int(gridShape.y)) {
                continue;
            }

            float2 windowMinimum = gridOrigin + float2(uIndex, vIndex) * stride;
            float2 windowMaximum = windowMinimum + cellSize;
            if (coordinate.x >= windowMinimum.x && coordinate.x < windowMaximum.x &&
                coordinate.y >= windowMinimum.y && coordinate.y < windowMaximum.y) {
                uint windowIndex = uint(uIndex) * gridShape.y + uint(vIndex);
                uint destination = atomic_fetch_add_explicit(
                    &windowWriteCursors[windowIndex],
                    1,
                    memory_order_relaxed
                );
                meshIndices[destination] = centroidIndex;
            }
        }
    }
}

inline float surfaceIntegrityValue(
    SurfaceIntegrityPackedPolygonFeaturesGPU value,
    uint source
) {
    switch (source) {
        case 0: return value.normalDeviation;
        case 1: return value.heightResidual;
        case 2: return value.absoluteHeightResidual;
        case 3: return value.signedTiltU;
        case 4: return value.signedTiltV;
        default: return value.signedTiltMagnitude;
    }
}

kernel void reduceSurfaceIntegrityWindowFeatures(
    device const uint* offsets [[buffer(0)]],
    device const uint* meshIndices [[buffer(1)]],
    device const SurfaceIntegrityPackedPolygonFeaturesGPU* polygonFeatures [[buffer(2)]],
    constant uint& windowCount [[buffer(3)]],
    constant uint& polygonCount [[buffer(4)]],
    device SurfaceIntegrityWindowReductionGPU* output [[buffer(5)]],
    uint tid [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    uint3 threadsPerGroup [[threads_per_threadgroup]]
) {
    threadgroup float areaValues[256];
    threadgroup float deltaSums[256];
    threadgroup float minima[256];
    threadgroup float maxima[256];
    threadgroup uint counts[256];
    uint window = group.x;
    uint source = group.y;
    if (window >= windowCount || source >= 6) return;
    uint firstPosition = offsets[window];
    float reference = firstPosition < offsets[window + 1]
        ? surfaceIntegrityValue(polygonFeatures[meshIndices[firstPosition]], source)
        : 0.0f;
    float area = 0.0f, deltaSum = 0.0f;
    float minimum = INFINITY, maximum = -INFINITY;
    uint count = 0;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount) continue;
        SurfaceIntegrityPackedPolygonFeaturesGPU packed = polygonFeatures[polygon];
        float value = surfaceIntegrityValue(packed, source);
        area += packed.area;
        deltaSum += value - reference;
        count += 1;
        minimum = min(minimum, value);
        maximum = max(maximum, value);
    }
    areaValues[tid] = area; deltaSums[tid] = deltaSum; minima[tid] = minimum;
    maxima[tid] = maximum; counts[tid] = count;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
        if (tid < offset) {
            areaValues[tid] += areaValues[tid + offset];
            deltaSums[tid] += deltaSums[tid + offset];
            minima[tid] = min(minima[tid], minima[tid + offset]);
            maxima[tid] = max(maxima[tid], maxima[tid + offset]);
            counts[tid] += counts[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        uint index = window * 6 + source;
        output[index].count = counts[0]; output[index].totalArea = areaValues[0];
        output[index].mean = counts[0] == 0
            ? 0.0f
            : reference + deltaSums[0] / float(counts[0]);
        output[index].centeredMoment2Sum = 0.0f;
        output[index].centeredMoment3Sum = 0.0f;
        output[index].centeredMoment4Sum = 0.0f;
        output[index].minimum = counts[0] == 0 ? 0.0f : minima[0];
        output[index].maximum = counts[0] == 0 ? 0.0f : maxima[0];
    }
}

kernel void computeSurfaceIntegrityWindowCenteredMoments(
    device const uint* offsets [[buffer(0)]],
    device const uint* meshIndices [[buffer(1)]],
    device const SurfaceIntegrityPackedPolygonFeaturesGPU* polygonFeatures [[buffer(2)]],
    constant uint& windowCount [[buffer(3)]],
    constant uint& polygonCount [[buffer(4)]],
    device SurfaceIntegrityWindowReductionGPU* reductions [[buffer(5)]],
    uint tid [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    uint3 threadsPerGroup [[threads_per_threadgroup]]
) {
    threadgroup float moment2[256];
    threadgroup float moment3[256];
    threadgroup float moment4[256];
    uint window = group.x;
    uint source = group.y;
    if (window >= windowCount || source >= 6) return;
    uint reductionIndex = window * 6 + source;
    SurfaceIntegrityWindowReductionGPU reduction = reductions[reductionIndex];
    float mean = reduction.mean;
    float m2 = 0.0f, m3 = 0.0f, m4 = 0.0f;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount) continue;
        float delta = surfaceIntegrityValue(polygonFeatures[polygon], source) - mean;
        float delta2 = delta * delta;
        m2 += delta2;
        m3 += delta2 * delta;
        m4 += delta2 * delta2;
    }
    moment2[tid] = m2;
    moment3[tid] = m3;
    moment4[tid] = m4;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
        if (tid < offset) {
            moment2[tid] += moment2[tid + offset];
            moment3[tid] += moment3[tid + offset];
            moment4[tid] += moment4[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        reductions[reductionIndex].centeredMoment2Sum = moment2[0];
        reductions[reductionIndex].centeredMoment3Sum = moment3[0];
        reductions[reductionIndex].centeredMoment4Sum = moment4[0];
    }
}

kernel void computeSurfaceIntegrityWindowEntropy(
    device const uint* offsets [[buffer(0)]],
    device const uint* meshIndices [[buffer(1)]],
    device const SurfaceIntegrityPackedPolygonFeaturesGPU* polygonFeatures [[buffer(2)]],
    device const SurfaceIntegrityWindowReductionGPU* reductions [[buffer(3)]],
    constant uint& windowCount [[buffer(4)]],
    constant uint& polygonCount [[buffer(5)]],
    device float* entropies [[buffer(6)]],
    device atomic_uint* histograms [[buffer(7)]],
    uint tid [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    uint3 threadsPerGroup [[threads_per_threadgroup]]
) {
    uint window = group.x, source = group.y;
    if (window >= windowCount || source >= 6) return;
    SurfaceIntegrityWindowReductionGPU reduction = reductions[window * 6 + source];
    float lower = reduction.minimum, upper = reduction.maximum;
    if (lower == upper) { lower -= 0.5f; upper += 0.5f; }
    float width = (upper - lower) / 30.0f;
    uint histogramOffset = (window * 6 + source) * 30;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount || width <= 0.0f) continue;
        float value = surfaceIntegrityValue(polygonFeatures[polygon], source);
        // Counteract fast-math division landing infinitesimally below an exact bin edge.
        int bin = clamp(int(floor((value - lower) / width + 1e-6f)), 0, 29);
        atomic_fetch_add_explicit(&histograms[histogramOffset + bin], 1, memory_order_relaxed);
    }
    threadgroup_barrier(mem_flags::mem_device);
    if (tid != 0) return;
    float total = float(reduction.count) + 30.0f * 1e-10f;
    float entropy = 0.0f;
    if (reduction.count > 0) {
        for (uint bin = 0; bin < 30; ++bin) {
            float probability = (float(atomic_load_explicit(&histograms[histogramOffset + bin], memory_order_relaxed)) + 1e-10f) / total;
            entropy -= probability * log(probability);
        }
    }
    entropies[window * 6 + source] = entropy;
}

kernel void computeSurfaceIntegrityWindowTails(
    device const uint* offsets [[buffer(0)]],
    device const uint* meshIndices [[buffer(1)]],
    device const SurfaceIntegrityPackedPolygonFeaturesGPU* polygonFeatures [[buffer(2)]],
    device const SurfaceIntegrityTailDescriptorGPU* descriptors [[buffer(3)]],
    constant uint& windowCount [[buffer(4)]],
    constant uint& polygonCount [[buffer(5)]],
    constant uint& descriptorCount [[buffer(6)]],
    device float* output [[buffer(7)]],
    uint tid [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    uint3 threadsPerGroup [[threads_per_threadgroup]]
) {
    threadgroup float totalWeights[256];
    threadgroup float matchingWeights[256];
    uint window = group.x, descriptorIndex = group.y;
    if (window >= windowCount || descriptorIndex >= descriptorCount) return;
    SurfaceIntegrityTailDescriptorGPU descriptor = descriptors[descriptorIndex];
    float total = 0.0f, matching = 0.0f;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount) continue;
        SurfaceIntegrityPackedPolygonFeaturesGPU packed = polygonFeatures[polygon];
        total += packed.area;
        if (surfaceIntegrityValue(packed, descriptor.source) > descriptor.threshold) matching += packed.area;
    }
    totalWeights[tid] = total; matchingWeights[tid] = matching;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
        if (tid < offset) {
            totalWeights[tid] += totalWeights[tid + offset];
            matchingWeights[tid] += matchingWeights[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) output[window * descriptorCount + descriptorIndex] =
        totalWeights[0] > 0.0f ? matchingWeights[0] / totalWeights[0] : 0.0f;
}

inline uint surfaceIntegritySortableFloatKey(float value) {
    uint bits = as_type<uint>(value);
    return (bits & 0x80000000u) != 0 ? ~bits : (bits ^ 0x80000000u);
}

inline float surfaceIntegrityFloatFromSortableKey(uint key) {
    uint bits = (key & 0x80000000u) != 0 ? (key ^ 0x80000000u) : ~key;
    return as_type<float>(bits);
}

inline float surfaceIntegrityOrderStatisticValue(
    SurfaceIntegrityPackedPolygonFeaturesGPU packed,
    SurfaceIntegrityOrderStatisticDescriptorGPU descriptor,
    uint window,
    device const float* dependencyValues,
    uint dependencyStride
) {
    float value = surfaceIntegrityValue(packed, descriptor.source);
    if (descriptor.operation == 1u) {
        float median = dependencyValues[window * dependencyStride + descriptor.dependencySlot];
        return abs(value - median);
    }
    return value;
}

kernel void selectSurfaceIntegrityWeightedPercentiles(
    device const uint* offsets [[buffer(0)]],
    device const uint* meshIndices [[buffer(1)]],
    device const SurfaceIntegrityPackedPolygonFeaturesGPU* polygonFeatures [[buffer(2)]],
    device const SurfaceIntegrityOrderStatisticDescriptorGPU* descriptors [[buffer(3)]],
    constant uint& windowCount [[buffer(4)]],
    constant uint& polygonCount [[buffer(5)]],
    constant uint& descriptorCount [[buffer(6)]],
    device float* output [[buffer(7)]],
    device atomic_uint* status [[buffer(8)]],
    device const float* dependencyValues [[buffer(9)]],
    constant uint& dependencyStride [[buffer(10)]],
    uint tid [[thread_index_in_threadgroup]],
    uint3 group [[threadgroup_position_in_grid]],
    uint3 threadsPerGroup [[threads_per_threadgroup]]
) {
    threadgroup float partialWeights[256];
    threadgroup uint partialCounts[256];
    threadgroup ulong predecessorKeys[256];
    threadgroup ulong selectedKey;
    threadgroup float targetPosition;
    threadgroup float weightBelow;
    uint window = group.x;
    uint descriptorIndex = group.y;
    if (window >= windowCount || descriptorIndex >= descriptorCount) return;
    SurfaceIntegrityOrderStatisticDescriptorGPU descriptor = descriptors[descriptorIndex];

    float localTotal = 0.0f;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount) {
            atomic_store_explicit(status, 1u, memory_order_relaxed);
            continue;
        }
        SurfaceIntegrityPackedPolygonFeaturesGPU packed = polygonFeatures[polygon];
        float value = surfaceIntegrityOrderStatisticValue(
            packed, descriptor, window, dependencyValues, dependencyStride
        );
        if (!isfinite(value) || !isfinite(packed.area) || packed.area < 0.0f) {
            atomic_store_explicit(status, 1u, memory_order_relaxed);
            continue;
        }
        localTotal += packed.area;
    }
    partialWeights[tid] = localTotal;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
        if (tid < offset) partialWeights[tid] += partialWeights[tid + offset];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    float totalWeight = partialWeights[0];
    if (totalWeight <= 0.0f) {
        if (tid == 0) output[window * descriptorCount + descriptorIndex] = NAN;
        return;
    }
    if (tid == 0) {
        selectedKey = 0ul;
        weightBelow = 0.0f;
        targetPosition = clamp(descriptor.percentile, 0.0f, 100.0f) * 0.01f * totalWeight;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (int bit = 63; bit >= 0; --bit) {
        ulong higherMask = bit == 63 ? 0ul : (~0ul << uint(bit + 1));
        float zeroWeight = 0.0f;
        uint zeroCount = 0;
        for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
            uint polygon = meshIndices[position];
            if (polygon >= polygonCount) continue;
            SurfaceIntegrityPackedPolygonFeaturesGPU packed = polygonFeatures[polygon];
            float value = surfaceIntegrityOrderStatisticValue(
                packed, descriptor, window, dependencyValues, dependencyStride
            );
            if (!isfinite(value) || !isfinite(packed.area) || packed.area < 0.0f) continue;
            ulong key = (ulong(surfaceIntegritySortableFloatKey(value)) << 32) | ulong(polygon);
            if ((key & higherMask) == (selectedKey & higherMask)
                && ((key >> uint(bit)) & 1ul) == 0ul) {
                zeroWeight += packed.area;
                zeroCount += 1;
            }
        }
        partialWeights[tid] = zeroWeight;
        partialCounts[tid] = zeroCount;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
            if (tid < offset) {
                partialWeights[tid] += partialWeights[tid + offset];
                partialCounts[tid] += partialCounts[tid + offset];
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (tid == 0) {
            bool chooseOne = partialCounts[0] == 0
                || targetPosition > weightBelow + partialWeights[0];
            if (chooseOne) {
                selectedKey |= 1ul << uint(bit);
                weightBelow += partialWeights[0];
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    float selectedWeight = 0.0f;
    ulong localPredecessor = 0ul;
    for (uint position = offsets[window] + tid; position < offsets[window + 1]; position += threadsPerGroup.x) {
        uint polygon = meshIndices[position];
        if (polygon >= polygonCount) continue;
        SurfaceIntegrityPackedPolygonFeaturesGPU packed = polygonFeatures[polygon];
        float value = surfaceIntegrityOrderStatisticValue(
            packed, descriptor, window, dependencyValues, dependencyStride
        );
        if (!isfinite(value) || !isfinite(packed.area) || packed.area < 0.0f) continue;
        ulong key = (ulong(surfaceIntegritySortableFloatKey(value)) << 32) | ulong(polygon);
        if (key == selectedKey) selectedWeight += packed.area;
        if (key < selectedKey) localPredecessor = max(localPredecessor, key);
    }
    partialWeights[tid] = selectedWeight;
    predecessorKeys[tid] = localPredecessor;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threadsPerGroup.x / 2; offset > 0; offset /= 2) {
        if (tid < offset) {
            partialWeights[tid] += partialWeights[tid + offset];
            predecessorKeys[tid] = max(predecessorKeys[tid], predecessorKeys[tid + offset]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
        float upperValue = surfaceIntegrityFloatFromSortableKey(uint(selectedKey >> 32));
        float result = upperValue;
        if (weightBelow > 0.0f && partialWeights[0] > 0.0f && targetPosition < totalWeight) {
            float lowerValue = surfaceIntegrityFloatFromSortableKey(uint(predecessorKeys[0] >> 32));
            float fraction = clamp((targetPosition - weightBelow) / partialWeights[0], 0.0f, 1.0f);
            result = mix(lowerValue, upperValue, fraction);
        }
        output[window * descriptorCount + descriptorIndex] = result;
    }
}

// Needed for mesh normals which are not pre-aligned to reference direction
inline float3 alignNormalWithReference(float3 normal, float3 reference) {
    if (dot(normal, reference) < 0.0) {
        return -normal;
    }
    return normal;
}

kernel void countDeviantNormals(
    device const SurfaceNormalsForPointsGridCell* grid [[buffer(0)]],
    constant uint& width [[buffer(1)]],
    constant uint& height [[buffer(2)]],
    constant DeviantNormalParams& params [[buffer(3)]],
    device atomic_uint* totalValid [[buffer(4)]],
    device atomic_uint* totalDeviant [[buffer(5)]],
    uint id [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]]
) {
    threadgroup uint localValid[256];
    threadgroup uint localDeviant[256];
    
    uint valid = 0;
    uint deviant = 0;
    
    uint x = id % width;
    uint y = id / width;
    if (x < width && y < height) {
        SurfaceNormalsForPointsGridCell cell = grid[id];
        if (cell.isValid != 0) {
            valid = 1;
            float3 n = cell.surfaceNormal;
            float cosTheta = dot(n, params.normalVector);
            // clamp
            cosTheta = clamp(cosTheta, -1.0f, 1.0f);
            if (cosTheta < params.angularDeviationCosThreshold) {
                deviant = 1;
            }
        }
    }
    
    localValid[tid] = valid;
    localDeviant[tid] = deviant;
    
    // Perform parallel reduction within the threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = 128; offset > 0; offset /= 2) {
        if (tid < offset) {
            localValid[tid] += localValid[tid + offset];
            localDeviant[tid] += localDeviant[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    // Thread 0 of the group writes the result to global memory
    if (tid == 0) {
        atomic_fetch_add_explicit(totalValid, localValid[0], memory_order_relaxed);
        atomic_fetch_add_explicit(totalDeviant, localDeviant[0], memory_order_relaxed);
    }
}

kernel void stdFromNormals(
    device const SurfaceNormalsForPointsGridCell* grid [[buffer(0)]],
    constant uint& width [[buffer(1)]],
    constant uint& height [[buffer(2)]],
    constant BoundsParams& boundsParams [[buffer(3)]],
    constant StdNormalParams& params [[buffer(4)]],
    device float* deviationSum [[buffer(5)]],
    device float* deviationSquaredSum [[buffer(6)]],
    device uint* totalValid [[buffer(7)]],
    uint id [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    threadgroup float localDeviationSum[256];
    threadgroup float localDeviationSquaredSum[256];
    threadgroup uint localValid[256];
    
    float deviationThread = 0.0f;
    float deviationSquaredThread = 0.0f;
    uint validThread = 0;
    
    uint x = id % width;
    uint y = id / width;
    if (x >= boundsParams.minX && x <= boundsParams.maxX && y >= boundsParams.minY && y <= boundsParams.maxY) {
        SurfaceNormalsForPointsGridCell cell = grid[id];
        if (cell.isValid != 0) {
            validThread = 1;
            float3 n = cell.surfaceNormal;
            float cosTheta = dot(n, params.normalVector);
            // clamp
            cosTheta = clamp(cosTheta, -1.0f, 1.0f);
            float deviation = acos(cosTheta);
            deviationThread = deviation;
            deviationSquaredThread = deviation * deviation;
        }
    }
    
    localDeviationSum[tid] = deviationThread;
    localDeviationSquaredSum[tid] = deviationSquaredThread;
    localValid[tid] = validThread;
    
    // Perform parallel reduction within the threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = 128; offset > 0; offset /= 2) {
        if (tid < offset) {
            localDeviationSum[tid] += localDeviationSum[tid + offset];
            localDeviationSquaredSum[tid] += localDeviationSquaredSum[tid + offset];
            localValid[tid] += localValid[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    // Thread 0 of the group writes the result to global memory
    if (tid == 0) {
        deviationSum[gid] = localDeviationSum[0];
        deviationSquaredSum[gid] = localDeviationSquaredSum[0];
        totalValid[gid] = localValid[0];
    }
}

inline float2 unprojectWorldPointToPixel(
    float3 worldPoint,
    constant float4x4& viewMatrix,
    constant float3x3& intrinsics,
    uint2 imageSize
) {
    float4 worldPoint4 = float4(worldPoint, 1.0);
    float4 imageVertex = viewMatrix * worldPoint4;
    
    if (imageVertex.z > 0) {
        return float2(-1, -1);
    }
    float3 imagePoint = imageVertex.xyz / imageVertex.z;
    float xNormalized = - imagePoint.x / imagePoint.z;
    float yNormalized = - imagePoint.y / (- imagePoint.z);
    
    float3 pixelHomogeneous = intrinsics * float3(xNormalized, yNormalized, 1.0);
    float2 pixelCoord = pixelHomogeneous.xy / pixelHomogeneous.z;
    
    if (pixelCoord.x < 0 || pixelCoord.x >= imageSize.x ||
        pixelCoord.y < 0 || pixelCoord.y >= imageSize.y) {
        return float2(-1, -1);
    }
    float2 pixelCoordRounded = round(pixelCoord);
    return pixelCoordRounded;
}

kernel void countDeviantPolygonNormals(
    device const MeshTriangle* meshTriangles [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    constant DeviantNormalParams& params [[buffer(2)]],
    device atomic_uint* totalValid [[buffer(3)]],
    device atomic_uint* totalDeviant [[buffer(4)]],
    uint id [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    threadgroup uint localValid[256];
    threadgroup uint localDeviant[256];
    
    uint valid = 0;
    uint deviant = 0;
    
    if (id < count) {
        valid = 1;
        MeshTriangle tri = meshTriangles[id];
        // Calculate normal from the points
        // First convert to float3 for cross product
        float3 edge1 = tri.b - tri.a;
        float3 edge2 = tri.c - tri.a;
        float3 normal = cross(edge1, edge2);
        normal = alignNormalWithReference(normal, params.normalVector);
        normal = normalize(normal);
        float cosTheta = dot(normal, params.normalVector);
        // clamp
        cosTheta = clamp(cosTheta, -1.0f, 1.0f);
        if (cosTheta < params.angularDeviationCosThreshold) {
            deviant = 1;
        }
    }
    
    localValid[tid] = valid;
    localDeviant[tid] = deviant;
    
    // Perform parallel reduction within the threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = 128; offset > 0; offset /= 2) {
        if (tid < offset) {
            localValid[tid] += localValid[tid + offset];
            localDeviant[tid] += localDeviant[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    // Thread 0 of the group writes the result to global memory
    if (tid == 0) {
        atomic_fetch_add_explicit(totalValid, localValid[0], memory_order_relaxed);
        atomic_fetch_add_explicit(totalDeviant, localDeviant[0], memory_order_relaxed);
    }
}

kernel void areaWithinBoundsPolygon(
    device const MeshTriangle* meshTriangles [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    constant BoundsParams& boundsParams [[buffer(2)]],
    constant AreaWithinBoundsPolygonParams& params [[buffer(3)]],
    device float* area [[buffer(4)]],
    uint id [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    threadgroup float localArea[256];
    
    float areaThread = 0.0f;
    
    if (id < count) {
        MeshTriangle tri = meshTriangles[id];
        // Get the centroid and check if it's within bounds
        float3 centroid = (tri.a + tri.b + tri.c) / 3.0f;
        float2 unprojectedCentroid = unprojectWorldPointToPixel(
            centroid, params.viewMatrix, params.cameraIntrinsics, params.imageSize
        );
        if (unprojectedCentroid.x >= boundsParams.minX && unprojectedCentroid.x <= boundsParams.maxX &&
            unprojectedCentroid.y >= boundsParams.minY && unprojectedCentroid.y <= boundsParams.maxY) {
            // Calculate area using cross product
            packed_float3 edge1 = tri.b - tri.a;
            packed_float3 edge2 = tri.c - tri.a;
            float triangleArea = length(cross(edge1, edge2)) / 2.0f;
            areaThread = triangleArea;
        }
    }
    
    localArea[tid] = areaThread;
    
    // Perform parallel reduction within the threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = 128; offset > 0; offset /= 2) {
        if (tid < offset) {
            localArea[tid] += localArea[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    // Thread 0 of the group writes the result to global memory
    if (tid == 0) {
        area[gid] = localArea[0];
    }
}

kernel void stdFromPolygonNormals(
    device const MeshTriangle* meshTriangles [[buffer(0)]],
    constant uint& count [[buffer(1)]],
    constant BoundsParams& boundsParams [[buffer(2)]],
    constant StdPolygonParams& params [[buffer(3)]],
    device float* deviationSum [[buffer(4)]],
    device float* deviationSquaredSum [[buffer(5)]],
    device uint* totalValid [[buffer(6)]],
    uint id [[thread_position_in_grid]],
    uint tid [[thread_index_in_threadgroup]],
    uint gid [[threadgroup_position_in_grid]]
) {
    threadgroup float localDeviationSum[256];
    threadgroup float localDeviationSquaredSum[256];
    threadgroup uint localValid[256];
    
    float deviationThread = 0.0f;
    float deviationSquaredThread = 0.0f;
    uint validThread = 0;
    
    if (id < count) {
        MeshTriangle tri = meshTriangles[id];
        // Get the centroid and check if it's within bounds
        float3 centroid = (tri.a + tri.b + tri.c) / 3.0f;
        float2 unprojectedCentroid = unprojectWorldPointToPixel(
            centroid, params.viewMatrix, params.cameraIntrinsics, params.imageSize
        );
        if (unprojectedCentroid.x >= boundsParams.minX && unprojectedCentroid.x <= boundsParams.maxX &&
            unprojectedCentroid.y >= boundsParams.minY && unprojectedCentroid.y <= boundsParams.maxY) {
            validThread = 1;
            // Calculate normal from the points
            packed_float3 edge1 = tri.b - tri.a;
            packed_float3 edge2 = tri.c - tri.a;
            float3 normal = cross(edge1, edge2);
            normal = normalize(normal);
            normal = alignNormalWithReference(normal, params.normalVector);
            float cosTheta = dot(normal, params.normalVector);
            // clamp
            cosTheta = clamp(cosTheta, -1.0f, 1.0f);
            float deviation = acos(cosTheta);
            deviationThread = deviation;
            deviationSquaredThread = deviation * deviation;
        }
    }
    
    localDeviationSum[tid] = deviationThread;
    localDeviationSquaredSum[tid] = deviationSquaredThread;
    localValid[tid] = validThread;
    
    // Perform parallel reduction within the threadgroup
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = 128; offset > 0; offset /= 2) {
        if (tid < offset) {
            localDeviationSum[tid] += localDeviationSum[tid + offset];
            localDeviationSquaredSum[tid] += localDeviationSquaredSum[tid + offset];
            localValid[tid] += localValid[tid + offset];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    
    // Thread 0 of the group writes the result to global memory
    if (tid == 0) {
        deviationSum[gid] = localDeviationSum[0];
        deviationSquaredSum[gid] = localDeviationSquaredSum[0];
        totalValid[gid] = localValid[0];
    }
}
