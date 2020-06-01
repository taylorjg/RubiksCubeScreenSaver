//
//  DefaultsManager.swift
//  RubiksCube
//
//  Created by Administrator on 24/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Foundation
import ScreenSaver

private let KEY_CUBE_SIZES = "cube-sizes"
private let KEY_PAUSE_INTERVAL = "pause-interval"
private let KEY_ENABLE_MSAA = "enable-msaa"

private let DEFAULTS: [String: Any] = [
    KEY_CUBE_SIZES: Settings.defaultCubeSizes,
    KEY_PAUSE_INTERVAL: Settings.defaultPauseInterval,
    KEY_ENABLE_MSAA: Settings.defaultEnableMSAA
]

class DefaultsManager {
    
    let screenSaverDefaults: ScreenSaverDefaults
    
    init() {
        let identifier = Bundle(for: DefaultsManager.self).bundleIdentifier!
        screenSaverDefaults = ScreenSaverDefaults.init(forModuleWithName: identifier)!
        screenSaverDefaults.register(defaults: DEFAULTS)
    }
    
    var cubeSizes: [Int] {
        get {
            let array = screenSaverDefaults.array(forKey: KEY_CUBE_SIZES) ?? []
            return array.map { el in el as! Int }
        }
        set {
            screenSaverDefaults.set(newValue, forKey: KEY_CUBE_SIZES)
            screenSaverDefaults.synchronize()
        }
    }

    var pauseInterval: Int {
        get {
            return screenSaverDefaults.integer(forKey: KEY_PAUSE_INTERVAL)
        }
        set {
            screenSaverDefaults.set(newValue, forKey: KEY_PAUSE_INTERVAL)
            screenSaverDefaults.synchronize()
        }
    }
    
    var enableMSAA: Bool {
        get {
            return screenSaverDefaults.bool(forKey: KEY_ENABLE_MSAA)
        }
        set {
            screenSaverDefaults.set(newValue, forKey: KEY_ENABLE_MSAA)
            screenSaverDefaults.synchronize()
        }
    }
}
