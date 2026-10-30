class_name RangedEnemy
extends Enemy

## 원거리(궁수): 플레이어와 7~9 m 거리를 유지하며 조준 후 화살을 쏜다.

## 화살 씬
@export var arrow_scene: PackedScene
## 이보다 가까우면 물러난다 (m)
@export var min_distance := 7.0
## 이보다 멀면 다가간다 (m)
@export var max_distance := 9.0
## min_distance에서 이만큼 더 가까우면 쏘지 않고 먼저 물러난다 (m)
@export var too_close_margin := 1.0
## 화살이 나오는 위치: 몸 중심에서 앞으로 (m)
@export var arrow_spawn_forward := 0.5
## 화살이 나오는 높이 (m)
@export var arrow_spawn_height := 0.8


func _update_state(delta: float) -> void:
	if state != State.CHASE:
		# 조준(예비 동작)과 대기는 공통 처리를 쓴다.
		super(delta)
		return
	var distance := _distance_to_player()
	var can_shoot := distance >= min_distance - too_close_margin \
		and distance <= max_distance + too_close_margin
	if can_shoot and _attack_cooldown <= 0.0:
		_start_windup()
	elif distance < min_distance:
		var away := global_position * 2.0 - _player.global_position
		_move_toward(away, move_speed)
	elif distance > max_distance:
		_move_toward(_player.global_position, move_speed)
	else:
		velocity = Vector3.ZERO


## 조준이 끝나는 순간의 플레이어 방향으로 화살을 쏜다.
func _attack() -> void:
	var direction := Movement.flat_direction(global_position, _player.global_position)
	var arrow := arrow_scene.instantiate()
	arrow.direction = direction
	arrow.position = global_position + direction * arrow_spawn_forward + Vector3.UP * arrow_spawn_height
	_get_projectile_parent().add_child(arrow)
