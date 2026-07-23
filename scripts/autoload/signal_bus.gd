extends Node
## Global signal hub — decouple gameplay systems from audio, UI, and persistence.

signal player_shot
signal player_damaged(amount: float)
signal enemy_hit
signal enemy_died
signal item_collected(item_id: String, rarity: String)
signal player_healed(amount: float)
signal elite_spawned
signal enemy_ranged_attack
signal wave_started(wave_number: int, is_boss: bool)
signal wave_cleared(wave_number: int, was_boss: bool)
signal level_up(level: int)
signal skill_unlocked(skill: SkillData)
signal player_died
# (2026-07-21) Emitted when the player's HP hits 0 but a continue is still
# available (see Player.MAX_CONTINUES) -- ContinuePopup offers a revive
# instead of letting player_died (the final game-over) fire. `continues_used`
# is how many have already been spent this run (0 = the first, free one).
signal player_downed(continues_used: int)
signal player_dashed
signal player_ultimate_used
signal game_paused(source: String)
signal game_unpaused(source: String)
signal boss_phase_changed(phase: int)
signal boss_attack_telegraph
signal boss_hp_changed(current: float, max_hp: float)
# "" = no mutation on this boss spawn -- emitted once from BossBase._ready()
# either way, so HUD resets the label correctly on every boss wave, not just
# mutated ones. See boss_base.gd::MUTATIONS.
signal boss_mutation_announced(mutation_name: String)
# "" = no affinity on this boss spawn -- emitted once from BossBase._ready()
# either way (same contract as boss_mutation_announced above). HUD uses it to
# show/hide the element-counter cycle reference. See boss_base.gd::AFFINITIES.
signal boss_affinity_announced(affinity_id: String)
# (2026-07-22) Emitted once when a late-game elemental fusion unlocks (two
# element lines both hit max tier) -- HUD shows a toast. See ElementFusions
# and Player._maybe_unlock_fusions().
signal fusion_unlocked(pair_id: String, display_name: String)
# (2026-07-23) Emitted once when a boss spawns, carrying its aura colour --
# HUD paints a brief full-screen flash so the arrival lands. See BossBase's
# _play_entrance().
signal boss_entrance(color: Color)
