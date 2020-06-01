//
//  ConfigSheetViewController.swift
//  RubiksCube
//
//  Created by Administrator on 24/05/2020.
//  Copyright © 2020 Jon Taylor. All rights reserved.
//

import Cocoa

class ConfigSheetViewController: NSViewController {
    
    let defaultsManager = DefaultsManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let cubeSizes = defaultsManager.cubeSizes
        cubeSize2Check.state = cubeSizes.contains(2) ? .on : .off
        cubeSize3Check.state = cubeSizes.contains(3) ? .on : .off
        cubeSize4Check.state = cubeSizes.contains(4) ? .on : .off
        cubeSize5Check.state = cubeSizes.contains(5) ? .on : .off
        pauseIntervalPopUp.selectItem(withTag: defaultsManager.pauseInterval)
        enableMSAACheck.state = defaultsManager.enableMSAA ? .on : .off
    }
    
    @IBOutlet weak var cubeSize2Check: NSButton!
    @IBOutlet weak var cubeSize3Check: NSButton!
    @IBOutlet weak var cubeSize4Check: NSButton!
    @IBOutlet weak var cubeSize5Check: NSButton!
    @IBOutlet weak var pauseIntervalPopUp: NSPopUpButton!
    @IBOutlet weak var enableMSAACheck: NSButton!
    @IBOutlet weak var okButton: NSButton!
    
    @IBAction func cubeSizeCheckChanged(_ sender: NSButton) {
        updateButtonState()
    }

    @IBAction func cancelButtonTapped(_ sender: NSButton) {
        close()
    }
    
    @IBAction func okButtonTapped(_ sender: NSButton) {
        defaultsManager.cubeSizes = cubeSizes
        defaultsManager.pauseInterval = pauseIntervalPopUp.selectedTag()
        defaultsManager.enableMSAA = enableMSAACheck.state == .on
        close()
    }
    
    private func updateButtonState() {
        okButton.isEnabled = !cubeSizes.isEmpty
    }

    private var cubeSizes: [Int] {
        var cubeSizes = [Int]()
        if cubeSize2Check.state == .on { cubeSizes.append(2) }
        if cubeSize3Check.state == .on { cubeSizes.append(3) }
        if cubeSize4Check.state == .on { cubeSizes.append(4) }
        if cubeSize5Check.state == .on { cubeSizes.append(5) }
        return cubeSizes
    }

    private func close() {
        guard let window = view.window else { return }
        window.endSheet(window)
    }
}
