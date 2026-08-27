//
//  GameViewController.swift
//  example-game iOS
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

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
