//
//  PointNMapShared.swift
//  PointNMapShared
//
//  Created by Himanshu on 4/30/26.
//

import Foundation

public final class PointNMapSharedBundleToken {}

public enum PointNMapSharedResources {
    public static var bundle: Bundle {
        Bundle(for: PointNMapSharedBundleToken.self)
    }
}

public enum PointNMapSharedBuildMarker {
    public static let value = "Submodule build marker 2026-06-07"
}
