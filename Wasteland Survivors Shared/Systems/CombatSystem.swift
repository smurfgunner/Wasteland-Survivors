//
//  CombatSystem.swift
//  example-game Shared
//

import SpriteKit

final class CombatSystem {
    private let targetSelection: SelectCombatTargetUseCase
    private let meleeHitResolution: ResolveMeleeHitsUseCase
    private let effectsRenderer: GameEffectsRenderer

    init(
        targetSelection: SelectCombatTargetUseCase = SelectCombatTargetUseCase(),
        meleeHitResolution: ResolveMeleeHitsUseCase = ResolveMeleeHitsUseCase(),
        effectsRenderer: GameEffectsRenderer = GameEffectsRenderer()
    ) {
        self.targetSelection = targetSelection
        self.meleeHitResolution = meleeHitResolution
        self.effectsRenderer = effectsRenderer
    }

    func updateAutoCombat(
        player: PlayerNode,
        zombies: [ZombieNode],
        world: SKNode,
        currentTime: TimeInterval,
        onDamageZombie: (ZombieNode, CGFloat) -> Void
    ) {
        guard player.canFire(currentTime: currentTime),
              let target = targetSelection.execute(player: player, zombies: zombies) else {
            return
        }

        let targetAngle = atan2(
            target.position.y - player.position.y,
            target.position.x - player.position.x
        )
        let weapon = player.currentWeapon

        player.aim(towards: targetAngle)
        player.recordFire(currentTime: currentTime)

        switch weapon.category {
        case .ranged:
            fireRangedAttack(
                player: player,
                weapon: weapon,
                damage: player.currentWeaponDamage,
                targetAngle: targetAngle,
                world: world
            )
        case .melee:
            performMeleeAttack(
                player: player,
                zombies: zombies,
                weapon: weapon,
                range: player.currentWeaponRange,
                targetAngle: targetAngle,
                world: world,
                onDamageZombie: onDamageZombie
            )
        }
    }

    private func fireRangedAttack(
        player: PlayerNode,
        weapon: WeaponType,
        damage: CGFloat,
        targetAngle: CGFloat,
        world: SKNode
    ) {
        let spreadAngles = weapon == .shotgun ? [-0.18, 0.0, 0.18] : [0.0]

        for offset in spreadAngles {
            spawnProjectile(
                from: player.position,
                angle: targetAngle + offset,
                weapon: weapon,
                damage: damage,
                world: world
            )
        }

        effectsRenderer.renderMuzzleFlash(
            weapon: weapon,
            at: player.position,
            angle: targetAngle,
            in: world
        )
    }

    private func spawnProjectile(
        from origin: CGPoint,
        angle: CGFloat,
        weapon: WeaponType,
        damage: CGFloat,
        world: SKNode
    ) {
        let projectile = ProjectileNode(weapon: weapon, damage: damage, directionAngle: angle)
        projectile.position = CGPoint(
            x: origin.x + cos(angle) * 18,
            y: origin.y + sin(angle) * 18
        )
        projectile.zPosition = 12
        world.addChild(projectile)
    }

    private func performMeleeAttack(
        player: PlayerNode,
        zombies: [ZombieNode],
        weapon: WeaponType,
        range: CGFloat,
        targetAngle: CGFloat,
        world: SKNode,
        onDamageZombie: (ZombieNode, CGFloat) -> Void
    ) {
        let slash = MeleeSlashNode(weapon: weapon, range: range, angle: targetAngle)
        slash.position = player.position
        slash.zPosition = 14
        world.addChild(slash)

        meleeHitResolution.execute(
            player: player,
            zombies: zombies,
            weapon: weapon,
            targetAngle: targetAngle,
            onHit: onDamageZombie
        )
    }
}
