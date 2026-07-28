//
//  CocoCustomClassConfig.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 7/4/25.
//
import Foundation
import CoreImage
import ARKit

public extension AccessibilityFeatureConfig {
    // Accessible color palette: https://www.sussex.ac.uk/tel/resource/tel_website/accessiblecontrast/?q=FFFFFF~003b49~1d4289~94a596~e56db1~d3273e~00bfb2~d6d2c4~ffc845~dc582a~41b6e6~1b365d~be84a3~5d3754~7da1c4~f2c75c~d0d3d4~007a78~000000
    static let mapillaryCustom12Config: AccessibilityFeatureClassConfig = AccessibilityFeatureClassConfig(
        modelURL: PointNMapSharedResources.bundle.url(forResource: "bisenetv2_12_640_640_model_final_accessibility_12_short", withExtension: "mlmodelc"),
        classes: [
//            AccessibilityFeatureClass(
//                id: "background", name: "Background", grayscaleValue: 0.0 / 255.0, labelValue: 0,
//                color: CIColor(red: 0.000, green: 0.000, blue: 0.000)
//            ),
            AccessibilityFeatureClass(id: "road", name: "Road", grayscaleValue: 1.0 / 255.0, labelValue: 1,
                color: CIColor(red: 0.502, green: 0.251, blue: 0.502),
                bounds: CGRect(
                x: 0.0, y: 0.1, width: 1.0, height: 0.4
            )),
            AccessibilityFeatureClass(
                id: "sidewalk", name: "Sidewalk", kind: .sidewalk,
                grayscaleValue: 2.0 / 255.0, labelValue: 2,
                color: CIColor(red: 0.957, green: 0.137, blue: 0.910),
                meshClassification: [.floor]
            ),
            
            AccessibilityFeatureClass(
                id: "building", name: "Building", kind: .building,
                grayscaleValue: 3.0 / 255.0, labelValue: 3,
//                color: CIColor(red: 0.275, green: 0.275, blue: 0.275),
                color: CIColor(red: 0.114, green: 0.259, blue: 0.537) // blue
            ),
            
            AccessibilityFeatureClass(
                id: "pole", name: "Pole", kind: .pole,
                grayscaleValue: 4.0 / 255.0, labelValue: 4,
                color: CIColor(red: 0, green: 0.749, blue: 0.698), // light blue
            ),
            
            AccessibilityFeatureClass(
                id: "traffic_light", name: "Traffic light", kind: .trafficLight,
                grayscaleValue: 5.0 / 255.0, labelValue: 5,
                color: CIColor(red: 0.827, green: 0.153, blue: 0.243) // red
            ),
            
            AccessibilityFeatureClass(
                id: "traffic_sign", name: "Traffic sign", kind: .trafficSign,
                grayscaleValue: 6.0 / 255.0, labelValue: 6,
                color: CIColor(red: 0.863, green: 0.345, blue: 0.165), // orange
            ),
            
            AccessibilityFeatureClass(
                id: "curb_ramp", name: "Curb Ramp", kind: .curbRamp,
                grayscaleValue: 7.0 / 255.0, labelValue: 7,
                color: CIColor(red: 1.0, green: 0.784, blue: 0.271), // yellow
                meshClassification: [.floor]
            ),
            
            AccessibilityFeatureClass(
                id: "vegetation", name: "Vegetation", kind: .vegetation,
                grayscaleValue: 8.0 / 255.0, labelValue: 8,
                color: CIColor(red: 0.420, green: 0.557, blue: 0.137),
            ),
            
            AccessibilityFeatureClass(
                id: "terrain", name: "Terrain", grayscaleValue: 9.0 / 255.0, labelValue: 9,
                color: CIColor(red: 0.596, green: 0.984, blue: 0.596)
            ),
            
            AccessibilityFeatureClass(
                id: "static", name: "Static", grayscaleValue: 10.0 / 255.0, labelValue: 10,
                color: CIColor(red: 0.863, green: 0.078, blue: 0.235)
            ),
            
            AccessibilityFeatureClass(
                id: "dynamic", name: "Dynamic", grayscaleValue: 11.0 / 255.0, labelValue: 11,
                color: CIColor(red: 0.000, green: 0.000, blue: 0.557)
            ),
        ],
        inputSize: CGSize(width: 640, height: 640)
    )
}
