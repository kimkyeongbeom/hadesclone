extends Node3D

## 따라갈 대상 (플레이어)
@export var target: Node3D
## 따라가는 빠르기. 클수록 바짝 붙는다.
@export var follow_speed := 6.0


func _ready() -> void:
	if target:
		global_position = target.global_position
		reset_physics_interpolation()


# 물리 보간을 쓰므로 카메라도 _physics_process에서 움직인다.
func _physics_process(delta: float) -> void:
	if target == null:
		return
	var goal := target.global_position
	goal.y = 0.0
	global_position = global_position.lerp(goal, 1.0 - exp(-follow_speed * delta))
