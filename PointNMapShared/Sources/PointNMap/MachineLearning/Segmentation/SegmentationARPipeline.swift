//
//  SegmentationARPipeline.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 4/17/25.
//

import SwiftUI
import Combine
import Vision
import CoreML

import simd

public enum SegmentationARPipelineError: Error, LocalizedError {
    case isProcessingTrue
    case emptySegmentation
    case segmentationResourcesNotConfigured
    case invalidSegmentation
    case invalidContour
    case invalidTransform
    case unexpectedError
    
    public var errorDescription: String? {
        switch self {
        case .isProcessingTrue:
            return "The Segmentation Image Pipeline is already processing a request."
        case .emptySegmentation:
            return "The Segmentation array is Empty"
        case .segmentationResourcesNotConfigured:
            return "The Segmentation Image Pipeline resources are not configured"
        case .invalidSegmentation:
            return "The Segmentation is invalid"
        case .invalidContour:
            return "The Contour is invalid"
        case .invalidTransform:
            return "The Homography Transform is invalid"
        case .unexpectedError:
            return "An unexpected error occurred in the Segmentation Image Pipeline."
        }
    }
}

public struct SegmentationARPipelineResults {
    public var segmentationImage: CIImage
    public var originalSegmentationImage: CIImage
    public var segmentationColorImage: CIImage
    public var segmentedClasses: [AccessibilityFeatureClass]
    public var detectedFeatureMap: [UUID: DetectedAccessibilityFeature]
    
    public init(segmentationImage: CIImage, segmentationColorImage: CIImage,
         segmentedClasses: [AccessibilityFeatureClass], detectedFeatureMap: [UUID: DetectedAccessibilityFeature],
         originalSegmentationImage: CIImage
    ) {
        self.segmentationImage = segmentationImage
        self.originalSegmentationImage = originalSegmentationImage
        self.segmentationColorImage = segmentationColorImage
        self.segmentedClasses = segmentedClasses
        self.detectedFeatureMap = detectedFeatureMap
    }
}

/**
    A class to handle segmentation as well as the post-processing of the segmentation results on demand.
 
    TODO: Rename this to `SegmentationImagePipeline` since AR is not a necessary component here.
 */
public final class SegmentationARPipeline: ObservableObject {
//    private var isProcessing = false
    private typealias SegmentationTask = Task<SegmentationARPipelineResults, Error>
    private var currentTask: SegmentationTask?
    private var currentTaskLock = NSLock()
    private var currentTaskId: UUID?
    /// Prevents new processing from beginning while reset() is
    /// waiting for an existing request to finish.
    private var isResetting = false
    private var timeoutInSeconds: Double = 1.0
    
    private var selectedClasses: [AccessibilityFeatureClass] = []
    private var selectedClassLabels: [UInt8] = []
    private var selectedClassGrayscaleValues: [Float] = []
    private var selectedClassColors: [CIColor] = []
    
    // TODO: Check what would be the appropriate value for this
    private var contourEpsilon: Float = 0.01
    // TODO: Check what would be the appropriate value for this
    // For normalized points
    private var perimeterThreshold: Float = 0.01
    
    private var grayscaleToColorFilter: GrayscaleToColorFilter?
    private var depthFilter: DepthFilter?
    private var segmentationModelRequestProcessor: SegmentationModelRequestProcessor?
    private var contourRequestProcessor: ContourRequestProcessor?
    
    public init() {}
    
    public func configure() throws {
        self.segmentationModelRequestProcessor = try SegmentationModelRequestProcessor(
            selectedClasses: self.selectedClasses)
        self.contourRequestProcessor = try ContourRequestProcessor(
            contourEpsilon: self.contourEpsilon,
            perimeterThreshold: self.perimeterThreshold,
            selectedClasses: self.selectedClasses)
        self.grayscaleToColorFilter = try GrayscaleToColorFilter()
        self.depthFilter = try DepthFilter()
    }
    
    public func reset() async {
//        self.isProcessing = false
//        self.setSelectedClasses([])
        let resetState = beginReset()
        guard resetState.started else {
            return
        }
        defer {
            finishReset()
        }
        if let task = resetState.task {
            _ = try? await task.value
        }
        /*
         No segmentation request can begin while
         isResetting == true.
         */
        setSelectedClasses([])
    }
    
    private func beginReset() -> (started: Bool, task: SegmentationTask?) {
        currentTaskLock.lock()
        defer {
            currentTaskLock.unlock()
        }
        guard !isResetting else {
            return (false, nil)
        }
        isResetting = true
        let task = currentTask
        task?.cancel()
        return (true, task)
    }
    
    private func finishReset() {
        currentTaskLock.lock()
        isResetting = false
        currentTaskLock.unlock()
    }
    
    public func setSelectedClasses(_ selectedClasses: [AccessibilityFeatureClass]) {
        self.selectedClasses = selectedClasses
        self.selectedClassLabels = selectedClasses.map { $0.labelValue }
        self.selectedClassGrayscaleValues = selectedClasses.map { $0.grayscaleValue }
        self.selectedClassColors = selectedClasses.map { $0.color }
        
        self.segmentationModelRequestProcessor?.setSelectedClasses(self.selectedClasses)
        self.contourRequestProcessor?.setSelectedClasses(self.selectedClasses)
    }
    
    /**
        Function to process the segmentation request with the given CIImage.
     */
    public func processRequest(
        with cIImage: CIImage, depthImage: CIImage? = nil,
        highPriority: Bool = false
    ) async throws -> SegmentationARPipelineResults {
        let task = try makeProcessingTask(cIImage: cIImage, depthImage: depthImage, highPriority: highPriority)
        /*
         Propagate cancellation of the CALLER into the internal
         segmentation task.

         Awaiting task.value by itself does not give us the
         cancellation semantics we want here.
         */
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
    
    private func makeProcessingTask(cIImage: CIImage, depthImage: CIImage?, highPriority: Bool) throws -> SegmentationTask {
        currentTaskLock.lock()
        defer {
            currentTaskLock.unlock()
        }
        guard !isResetting else {
            throw SegmentationARPipelineError.isProcessingTrue
        }
        let previousTask: SegmentationTask?
        if (highPriority) {
            previousTask = currentTask
            // Cancellation is cooperative.
            // The replacement task will wait for this task below.
            previousTask?.cancel()
        } else {
            // A cancelled task is STILL considered active
            // until it actually completes.
            guard currentTask == nil else {
                throw SegmentationARPipelineError.isProcessingTrue
            }
            previousTask = nil
        }
        let taskId = UUID()
        let newTask = Task { [weak self] () throws -> SegmentationARPipelineResults in
            guard let self = self else { throw SegmentationARPipelineError.unexpectedError }
            defer {
                self.clearCurrentTask(ifMatching: taskId)
            }
            /*
             If this is a high-priority replacement, do not begin
             segmentation merely because the previous task was cancelled.

             Wait until the previous task has ACTUALLY finished.
             */
            if let previousTask {
                _ = try? await previousTask.value
            }
            try Task.checkCancellation()
            let results = try await self.processImageWithTimeout(cIImage, depthImage: depthImage)
            try Task.checkCancellation()
            return results
        }
        self.currentTask = newTask
        self.currentTaskId = taskId
        return newTask
    }
    
    private func clearCurrentTask(
        ifMatching taskId: UUID
    ) {
        currentTaskLock.lock()
        defer { currentTaskLock.unlock() }
        guard currentTaskId == taskId else { return }
        currentTask = nil
        currentTaskId = nil
    }
    
    private func processImageWithTimeout(
        _ cIImage: CIImage, depthImage: CIImage? = nil
    ) async throws -> SegmentationARPipelineResults {
        let timeout = timeoutInSeconds
        return try await withThrowingTaskGroup(
                of: SegmentationARPipelineResults.self
        ) { group in
            group.addTask {
                return try self.processImage(cIImage, depthImage: depthImage)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw SegmentationARPipelineError.unexpectedError
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw SegmentationARPipelineError.unexpectedError
            }
            return result
        }
    }
    
    /**
     Function to process the given CIImage.
     This function will perform the processing within the thread in which it is called.
     Optionally, it can also perform depth filtering if a depth image is provided.
     It will either return the SegmentationARPipelineResults or throw an error.
     
     The entire procedure has the following main steps:
     1. Get the segmentation mask from the camera image using the segmentation model
     2. Get the objects from the segmentation image
     3. Return the segmentation image, segmented indices, and detected objects, to the caller function
     
     Since this function can be called within a Task, it checks for cancellation at various points to ensure that it can exit early if needed.
     */
    private func processImage(
        _ cIImage: CIImage, depthImage: CIImage? = nil
    ) throws -> SegmentationARPipelineResults {
        guard let segmentationModelRequestProcessor = self.segmentationModelRequestProcessor,
              let contourRequestProcessor = self.contourRequestProcessor,
              let grayscaleToColorFilter = self.grayscaleToColorFilter else {
            throw SegmentationARPipelineError.segmentationResourcesNotConfigured
        }
        try Task.checkCancellation()
        
        let segmentationResults = try segmentationModelRequestProcessor.processSegmentationRequest(with: cIImage)
        let segmentationImage = segmentationResults.segmentationImage
        
        try Task.checkCancellation()
        
        var depthFilteredSegmentationImage: CIImage? = nil
        if let depthImage, let depthFilter = self.depthFilter {
            // Apply depth filtering to the segmentation image
            let depthMinThresholdValue = PointNMapConstants.DepthConstants.depthMinThreshold
            let depthMaxThresholdValue = PointNMapConstants.DepthConstants.depthMaxThreshold
            depthFilteredSegmentationImage = try depthFilter.apply(
                to: segmentationImage, depthImage: depthImage,
                depthMinThreshold: depthMinThresholdValue, depthMaxThreshold: depthMaxThresholdValue
            )
        }
        let finalSegmentationImage = depthFilteredSegmentationImage ?? segmentationImage
        
        try Task.checkCancellation()
        
        // MARK: Ignoring the object tracking for now
        // Get the objects from the segmentation image
        let detectedFeatures: [DetectedAccessibilityFeature] = try contourRequestProcessor.processRequest(
            from: finalSegmentationImage
        )
        // MARK: The temporary UUIDs can be removed if we do not need to track objects across frames
        let detectedFeatureMap: [UUID: DetectedAccessibilityFeature] = Dictionary(
            uniqueKeysWithValues: detectedFeatures.map { (UUID(), $0) }
        )
        
        try Task.checkCancellation()
        
        let segmentationColorImage = try grayscaleToColorFilter.apply(
            to: finalSegmentationImage,
            grayscaleValues: self.selectedClassGrayscaleValues, colorValues: self.selectedClassColors
        )
        
        return SegmentationARPipelineResults(
            segmentationImage: finalSegmentationImage,
            segmentationColorImage: segmentationColorImage,
            segmentedClasses: segmentationResults.segmentedClasses,
            detectedFeatureMap: detectedFeatureMap,
            originalSegmentationImage: segmentationImage
        )
    }
}
