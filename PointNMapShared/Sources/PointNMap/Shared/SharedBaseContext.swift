//
//  SharedBaseContext.swift
//  IOSAccessAssessment
//
//  Created by Himanshu on 11/24/25.
//
import SwiftUI
import Combine

public final class SharedBaseContext: ObservableObject {
    public var metalContext: MetalContext?
    
    public init() {}
    
    public func configure() throws {
        metalContext = try MetalContext()
    }
}

/// MARK: Additional settings struct that can be used or replaced by the main app as needed.
public final class SharedBaseSettings: ObservableObject {
    public var isEnhancedAnalysisEnabled: Bool = false
    
    public init(isEnhancedAnalysisEnabled: Bool = false) {
        self.isEnhancedAnalysisEnabled = isEnhancedAnalysisEnabled
    }
}
