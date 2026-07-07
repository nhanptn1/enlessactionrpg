extends AttackBehavior
class_name ContactAttack


func on_contact(enemy: EnemyBase, body: Node) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		enemy._player_in_contact = body
		body.take_damage(enemy.data.base_damage * enemy._damage_mult)
		enemy.contact_timer.start()
		enemy._play_attack_lunge()


func on_contact_tick(enemy: EnemyBase) -> void:
	if is_instance_valid(enemy._player_in_contact):
		enemy._player_in_contact.take_damage(enemy.data.base_damage * enemy._damage_mult)
		enemy._play_attack_lunge()
