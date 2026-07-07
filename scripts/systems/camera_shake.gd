extends Camera2D
class_name ShakeCamera

var _shake_tween: Tween


func shake(intensity: float = 8.0, duration: float = 0.2) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := 6
	for i in steps:
		var mag := intensity * (1.0 - float(i) / steps)
		_shake_tween.tween_property(self, "offset", Vector2(randf_range(-mag, mag), randf_range(-mag, mag)), duration / steps)
	_shake_tween.tween_property(self, "offset", Vector2.ZERO, duration / steps)
