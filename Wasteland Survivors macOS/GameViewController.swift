//
//  GameViewController.swift
//  example-game macOS
//
//  Created by Vahid Ghanbarpour on 17/08/2026.
//

import Cocoa
import SpriteKit
import GameplayKit

final class GameViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let view = self.view as? SKView {
            let scene = GameScene.newGameScene(size: view.bounds.size)
            scene.onExitRequested = { NSApplication.shared.terminate(nil) }
            view.preferredFramesPerSecond = 120
            view.presentScene(scene)
            view.ignoresSiblingOrder = true
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }
}