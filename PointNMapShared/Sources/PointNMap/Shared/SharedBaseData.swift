//
//  SharedBaseData.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/9/25.
//

import SwiftUI
import Combine
import simd

@MainActor
public final class SharedBaseData: ObservableObject {
    @Published var isUploadReady: Bool = false
    public var isLidarAvailable: Bool = ARCameraUtils.checkDepthSupport()
    
    public var currentCaptureDataRecord: CaptureData?
    /// A queue to hold recent capture image data.
    public var captureDataQueue: SafeDeque<CaptureImageData>
    public var captureDataCapacity: Int
    
    public init(captureDataCapacity: Int = 5) {
        self.captureDataCapacity = captureDataCapacity
        self.captureDataQueue = SafeDeque<CaptureImageData>(capacity: captureDataCapacity)
    }
    
    public func refreshQueue() async {
        await self.captureDataQueue.removeAll()
    }
    
    public func refreshData() {
        self.isUploadReady = false
        self.currentCaptureDataRecord = nil
    }
    
    public func saveCaptureData(_ data: CaptureData) {
        self.currentCaptureDataRecord = data
    }
    
    public func appendCaptureDataToQueue(_ data: (any CaptureImageDataProtocol)) async {
        let captureImageData = CaptureImageData(data)
        await self.captureDataQueue.appendBack(captureImageData)
    }
}
