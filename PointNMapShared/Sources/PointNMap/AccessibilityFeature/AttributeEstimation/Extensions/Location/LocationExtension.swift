//
//  LocationExtension.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 1/25/26.
//
import SwiftUI
import CoreLocation

public extension AttributeEstimationPipeline {
    func calculateLocation(
        deviceLocation: CLLocationCoordinate2D,
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> LocationRequestResult {
        let isMeshEnabled: Bool = self.captureMeshData != nil
        let geometry = accessibilityFeature.accessibilityFeatureClass.kind.geometry
        switch(geometry) {
        case .linestring:
            if isMeshEnabled {
                return try self.calculateLocationFromMeshForLineString(
                    deviceLocation: deviceLocation,
                    accessibilityFeature: accessibilityFeature
                )
            }
            return try self.calculateLocationFromImageForLineString(
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        case .polygon:
            return try self.calculateLocationFromImageForPolygon(
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        case .point:
            return try self.calculateLocationFromImageForPoint(
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        }
    }
}

/**
 Extension for additional location processing methods.
 */
public extension AttributeEstimationPipeline {
    func calculateLocationFromImageForPoint(
        deviceLocation: CLLocationCoordinate2D,
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> LocationRequestResult {
        guard let depthMapProcessor = self.depthMapProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.depthMapProcessorKey)
        }
        guard let localizationProcessor = self.localizationProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.localizationProcessorKey)
        }
        guard let captureImageData = self.captureImageData else {
            throw AttributeEstimationPipelineError.missingCaptureData
        }
        let captureImageDataConcrete = CaptureImageData(captureImageData)
        return try getLocationFromImageByCentroid(
            depthMapProcessor: depthMapProcessor,
            localizationProcessor: localizationProcessor,
            captureImageData: captureImageDataConcrete,
            deviceLocation: deviceLocation,
            accessibilityFeature: accessibilityFeature
        )
    }
    
    func calculateLocationFromImageForLineString(
        deviceLocation: CLLocationCoordinate2D,
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> LocationRequestResult {
        guard let depthMapProcessor = self.depthMapProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.depthMapProcessorKey)
        }
        guard let localizationProcessor = self.localizationProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.localizationProcessorKey)
        }
        guard let captureImageData = self.captureImageData else {
            throw AttributeEstimationPipelineError.missingCaptureData
        }
        let captureImageDataConcrete = CaptureImageData(captureImageData)
        let worldPoints = try self.getCachedWorldPoints(
            accessibilityFeature: accessibilityFeature
        )
        let alignedPlane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, worldPoints: worldPoints
        )
        do {
            return try getLocationFromImageForLineStringByPlane(
                depthMapProcessor: depthMapProcessor,
                localizationProcessor: localizationProcessor,
                captureImageData: captureImageDataConcrete,
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature,
                plane: alignedPlane, worldPoints: worldPoints
            )
        } catch {
            return try getLocationFromImageForLineStringByTrapezoid(
                depthMapProcessor: depthMapProcessor,
                localizationProcessor: localizationProcessor,
                captureImageData: captureImageDataConcrete,
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        }
    }
    
    func calculateLocationFromImageForPolygon(
        deviceLocation: CLLocationCoordinate2D,
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> LocationRequestResult {
        guard let depthMapProcessor = self.depthMapProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.depthMapProcessorKey)
        }
        guard let localizationProcessor = self.localizationProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.localizationProcessorKey)
        }
        guard let captureImageData = self.captureImageData else {
            throw AttributeEstimationPipelineError.missingCaptureData
        }
        let captureImageDataConcrete = CaptureImageData(captureImageData)
        do {
            return try getLocationFromImageByPolygon(
                depthMapProcessor: depthMapProcessor,
                localizationProcessor: localizationProcessor,
                captureImageData: captureImageDataConcrete,
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        } catch {
            return try getLocationFromImageByCentroid(
                depthMapProcessor: depthMapProcessor,
                localizationProcessor: localizationProcessor,
                captureImageData: captureImageDataConcrete,
                deviceLocation: deviceLocation,
                accessibilityFeature: accessibilityFeature
            )
        }
    }
}

public extension AttributeEstimationPipeline {
    func calculateLocationFromMeshForLineString(
        deviceLocation: CLLocationCoordinate2D,
        accessibilityFeature: any EditableAccessibilityFeatureProtocol
    ) throws -> LocationRequestResult {
        guard let depthMapProcessor = self.depthMapProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.depthMapProcessorKey)
        }
        guard let localizationProcessor = self.localizationProcessor else {
            throw AttributeEstimationPipelineError.configurationError(AttributeEstimationPipelineConstants.Texts.localizationProcessorKey)
        }
        guard let captureImageData = self.captureImageData else {
            throw AttributeEstimationPipelineError.missingCaptureData
        }
        let captureImageDataConcrete = CaptureImageData(captureImageData)
        let meshContents: MeshContents = try self.getCachedMeshContents(
            accessibilityFeature: accessibilityFeature
        )
        let meshPolygons: [MeshPolygon] = meshContents.polygons
        let alignedPlane: Plane = try self.getCachedAlignedPlane(
            accessibilityFeature: accessibilityFeature, meshPolygons: meshPolygons
        )
        return try getLocationFromMeshForLineStringByPlane(
            depthMapProcessor: depthMapProcessor,
            localizationProcessor: localizationProcessor,
            captureImageData: captureImageDataConcrete,
            deviceLocation: deviceLocation,
            accessibilityFeature: accessibilityFeature,
            plane: alignedPlane, meshContents: meshContents
        )
    }
}
