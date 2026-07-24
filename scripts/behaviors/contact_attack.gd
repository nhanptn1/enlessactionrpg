extends AttackBehavior
class_name ContactAttack

# (2026-07-24) The actual "touching the player deals damage" logic moved to
# EnemyBase._on_hurtbox_body_entered()/_on_contact_timer_timeout(), because it
# has to apply to every species, not just the ones wired to this behavior --
# see the comment there. This stays as the explicit "melee only, no ranged
# attack" marker every melee enemy's .tres points at, so the data still says
# out loud how each species fights and there's a place for melee-only extras
# to live if any are ever added.
