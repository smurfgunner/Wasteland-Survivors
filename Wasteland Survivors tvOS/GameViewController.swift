//
//  GameViewController.swift
//  example-game tvOS
//
//  Created by Vahid Ghanbarpour on 17/08/2026.
//

import UIKit
import SpriteKit
import GameplayKit

final class GameViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let view = self.view as? SKView {
            let scene = GameScene.newGameScene(size: view.bounds.size)
            view.preferredFramesPerSecond = 120
            view.presentScene(scene)
            view.ignoresSiblingOrder = true
            view.showsFPS = true
            view.showsNodeCount = true
        }
    }
}
