extends Area3D

## 궁수의 화살: 곧게 날아가 플레이어에게 맞으면 피해를 주고 사라진다.
## 나무·벽에 닿거나 최대 거리를 날면 사라진다.

## 피해
@export var damage := 8.0
## 속도 (m/s)
@export var speed := 7.0
## 최대 비행 거리 (m)
@export var max_distance := 20.0

## 날아가는 방향 (쏠 때 정해 준다)
var direction := Vector3.FORWARD

var _traveled := 0.0


func _ready() -> void:
	# 화살 메시는 -Z 쪽이 앞이다.
	basis = Basis.looking_at(direction)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += direction * step
	_traveled += step
	if _traveled >= max_distance:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		body.take_damage(damage, global_position)
	queue_free()
