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
signal game_paused(source: String)
signal game_unpaused(source: String)
signal boss_phase_changed(phase: int)
signal boss_attack_telegraph
signal boss_hp_changed(current: float, max_hp: float)
# "" = no mutation on this boss spawn -- emitted once from BossBase._ready()
# either way, so HUD resets the label correctly on every boss wave, not just
# mutated ones. See boss_base.gd::MUTATIONS.
signal boss_mutation_announced(mutation_name: String)
