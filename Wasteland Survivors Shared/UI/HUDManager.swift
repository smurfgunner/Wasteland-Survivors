//
//  HUDManager.swift
//  example-game Shared
//

import Foundation
import SpriteKit

final class HUDManager {
    let containerNode = SKNode()
    
    private var healthBarFill: SKShapeNode?
    private var healthLabel: SKLabelNode?
    private var weaponLabel: SKLabelNode?
    private var weaponTypeBadge: SKLabelNode?
    private var killScoreLabel: SKLabelNode?
    private var notificationLabel: SKLabelNode?
    private var gameOverNode: SKNode?
    
    private var joystickBase: SKShapeNode?
    private var joystickKnob: SKShapeNode?
    
    init() {
        containerNode.zPosition = 1000
    }
    
    func setup(in cameraNode: SKCameraNode, sceneSize: CGSize) {
        containerNode.removeFromParent()
        cameraNode.addChild(containerNode)
        buildHUD(sceneSize: sceneSize)
    }
    
    func buildHUD(sceneSize: CGSize) {
        containerNode.removeAllChildren()
        
        let halfW = sceneSize.width / 2
        let halfH = sceneSize.height / 2
        
        // 1. Health Bar (Top Left)
        let barWidth: CGFloat = 200
        let barHeight: CGFloat = 18
        let barBg = SKShapeNode(rectOf: CGSize(width: barWidth, height: barHeight), cornerRadius: 4)
        barBg.name = "healthBar"
        barBg.fillColor = SKColor(white: 0.1, alpha: 0.8)
        barBg.strokeColor = .lightGray
        barBg.lineWidth = 1.5
        barBg.position = CGPoint(x: -halfW + barWidth / 2 + 30, y: halfH - 45)
        containerNode.addChild(barBg)
        
        let fill = SKShapeNode(rectOf: CGSize(width: barWidth - 4, height: barHeight - 4), cornerRadius: 2)
        fill.name = "healthBarFill"
        fill.fillColor = .systemGreen
        fill.strokeColor = .clear
        fill.position = barBg.position
        containerNode.addChild(fill)
        self.healthBarFill = fill
        
        let hpText = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        hpText.text = "HP: 100/100"
        hpText.fontSize = 12
        hpText.fontColor = .white
        hpText.verticalAlignmentMode = .center
        hpText.horizontalAlignmentMode = .center
        hpText.position = barBg.position
        containerNode.addChild(hpText)
        self.healthLabel = hpText
        
        // 2. Weapon Indicator (Bottom Left)
        let weaponBg = SKShapeNode(rectOf: CGSize(width: 220, height: 64), cornerRadius: 8)
        weaponBg.name = "weaponPanel"
        weaponBg.fillColor = SKColor(white: 0.1, alpha: 0.8)
        weaponBg.strokeColor = .orange
        weaponBg.lineWidth = 1.5
        weaponBg.position = CGPoint(x: -halfW + 130, y: -halfH + 50)
        containerNode.addChild(weaponBg)
        
        let wLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        wLabel.text = "Pistol"
        wLabel.fontSize = 15
        wLabel.fontColor = .systemYellow
        wLabel.horizontalAlignmentMode = .left
        wLabel.position = CGPoint(x: -halfW + 30, y: -halfH + 58)
        containerNode.addChild(wLabel)
        self.weaponLabel = wLabel
        
        let badge = SKLabelNode(fontNamed: "HelveticaNeue-Medium")
        badge.text = "[RANGED] • DMG: 30 • RNG: 280\nFIR: 0.35"
        badge.fontSize = 10
        badge.fontColor = .lightGray
        badge.horizontalAlignmentMode = .left
        badge.verticalAlignmentMode = .center
        badge.position = CGPoint(x: -halfW + 30, y: -halfH + 35)
        containerNode.addChild(badge)
        self.weaponTypeBadge = badge
        
        // 3. Kill Counter (Top Right)
        let kills = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        kills.text = "ZOMBIES PURGED: 0"
        kills.fontSize = 15
        kills.fontColor = .systemOrange
        kills.horizontalAlignmentMode = .right
        kills.position = CGPoint(x: halfW - 30, y: halfH - 45)
        containerNode.addChild(kills)
        self.killScoreLabel = kills
        
        // 4. Instructions / Controls Hint (Bottom Center)
        let controlsHint = SKLabelNode(fontNamed: "HelveticaNeue")
        #if os(macOS)
        controlsHint.text = "WASD / Arrows to Move • Auto-Firing Active"
        #elseif os(tvOS)
        controlsHint.text = "Swipe/Click Remote to Move • Auto-Firing Active"
        #else
        controlsHint.text = "Touch & Drag to Move • Auto-Firing Active"
        #endif
        controlsHint.fontSize = 12
        controlsHint.fontColor = SKColor(white: 0.8, alpha: 0.7)
        controlsHint.position = CGPoint(x: 0, y: -halfH + 25)
        containerNode.addChild(controlsHint)
        
        // 5. Notification Banner
        let notif = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        notif.text = ""
        notif.fontSize = 18
        notif.fontColor = .systemYellow
        notif.position = CGPoint(x: 0, y: halfH - 100)
        notif.alpha = 0
        containerNode.addChild(notif)
        self.notificationLabel = notif
    }
    
    func updateHealth(current: CGFloat, max: CGFloat, sceneWidth: CGFloat) {
        guard let fill = healthBarFill, let label = healthLabel else { return }
        
        let validMax = Swift.max(1, max)
        let cur = Swift.max(0, current)
        let ratio = Swift.max(0, Swift.min(1, cur / validMax))
        
        let barWidth: CGFloat = 196
        fill.xScale = ratio
        fill.position.x = (-sceneWidth / 2 + 30 + 100) - (barWidth * (1 - ratio) / 2)
        
        label.text = "HP: \(Int(cur))/\(Int(validMax))"
        
        if ratio > 0.5 {
            fill.fillColor = .systemGreen
        } else if ratio > 0.25 {
            fill.fillColor = .systemYellow
        } else {
            fill.fillColor = .systemRed
        }
    }
    
    func updateWeapon(
        weapon: WeaponType,
        damage: CGFloat? = nil,
        range: CGFloat? = nil,
        fireRate: TimeInterval? = nil
    ) {
        let displayedDamage = damage ?? weapon.damage
        let displayedRange = range ?? weapon.range
        let displayedFireRate = fireRate ?? weapon.fireRate

        weaponLabel?.text = weapon.rawValue
        weaponLabel?.fontColor = weapon.color
        weaponTypeBadge?.text = "[\(weapon.category.rawValue)] • DMG: \(Int(displayedDamage)) • RNG: \(Int(displayedRange))\nFIR: \(String(format: "%.2f", displayedFireRate))"
    }
    
    func updateKillCount(_ count: Int) {
        killScoreLabel?.text = "ZOMBIES PURGED: \(count)"
    }
    
    func showNotification(text: String) {
        guard let notif = notificationLabel else { return }
        notif.text = text
        notif.removeAllActions()
        notif.alpha = 1.0
        notif.setScale(1.2)
        notif.run(.sequence([
            .scale(to: 1.0, duration: 0.15),
            .wait(forDuration: 1.8),
            .fadeOut(withDuration: 0.5)
        ]))
    }
    
    func showGameOver(kills: Int, sceneSize: CGSize) {
        guard gameOverNode == nil else { return }
        
        let goContainer = SKNode()
        goContainer.zPosition = 2000
        
        let bg = SKShapeNode(rectOf: CGSize(width: sceneSize.width * 2, height: sceneSize.height * 2))
        bg.fillColor = SKColor(white: 0, alpha: 0.75)
        bg.strokeColor = .clear
        goContainer.addChild(bg)
        
        let title = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        title.text = "YOU WERE OVERRUN"
        title.fontSize = 32
        title.fontColor = .systemRed
        title.position = CGPoint(x: 0, y: 40)
        goContainer.addChild(title)
        
        let subtitle = SKLabelNode(fontNamed: "HelveticaNeue")
        subtitle.text = "Zombies Eliminated: \(kills)"
        subtitle.fontSize = 18
        subtitle.fontColor = .white
        subtitle.position = CGPoint(x: 0, y: 0)
        goContainer.addChild(subtitle)
        
        let restartLabel = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        restartLabel.text = "Tap or Press Any Key to Restart"
        restartLabel.fontSize = 15
        restartLabel.fontColor = .systemYellow
        restartLabel.position = CGPoint(x: 0, y: -45)
        goContainer.addChild(restartLabel)
        
        restartLabel.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.3, duration: 0.5),
            .fadeAlpha(to: 1.0, duration: 0.5)
        ])))
        
        containerNode.addChild(goContainer)
        self.gameOverNode = goContainer
    }
    
    func hideGameOver() {
        gameOverNode?.removeFromParent()
        gameOverNode = nil
    }
    
    // MARK: - Joystick Display
    func showJoystick(at location: CGPoint) {
        hideJoystick()
        
        let base = SKShapeNode(circleOfRadius: 45)
        base.fillColor = SKColor(white: 1.0, alpha: 0.15)
        base.strokeColor = SKColor(white: 1.0, alpha: 0.4)
        base.lineWidth = 2
        base.position = location
        containerNode.addChild(base)
        self.joystickBase = base
        
        let knob = SKShapeNode(circleOfRadius: 22)
        knob.fillColor = SKColor(white: 1.0, alpha: 0.6)
        knob.strokeColor = .white
        knob.position = location
        containerNode.addChild(knob)
        self.joystickKnob = knob
    }
    
    func updateJoystickKnob(position: CGPoint) {
        joystickKnob?.position = position
    }
    
    func hideJoystick() {
        joystickBase?.removeFromParent()
        joystickKnob?.removeFromParent()
        joystickBase = nil
        joystickKnob = nil
    }
}
