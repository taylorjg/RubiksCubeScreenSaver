//
//  MyMTKView.swift
//  RubiksCubeApp
//
//  Created by Administrator on 24/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Cocoa
import MetalKit
import Carbon.HIToolbox.Events

class MyMTKView: MTKView {
    
    var keyboardControlDelegate: KeyboardControlDelegate?
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        default:
            break
        }
    }
}
