extends Area3D

## 커서 방향으로 곧게 날아가 처음 맞은 적 하나에 피해를 주고 사라진다.
## 나무·벽에 닿거나 최대 거리를 날면 사라진다.

## 피해
@export var damage := 15.0
## 속도 (m/s)
@export var speed := 12.0
## 최대 비행 거리 (m)
@export var max_distance := 12.0
## 맞았을 때 퍼지는 효과 시간 (초)
@export var hit_effect_time := 0.12
## 맞았을 때 퍼지는 크기 (배)
@export var hit_effect_scale := 2.5

## 날아가는 방향 (발사할 때 정해 준다)
var direction := Vector3.FORWARD

var _traveled := 0.0
var _done := false

@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _done:
		return
	var step := speed * delta
	global_position += direction * step
	_traveled += step
	if _traveled >= max_distance:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _done:
		return
	if body is Enemy:
		if body.is_dead():
			return
		body.take_damage(damage, global_position)
	_finish()


## 그 자리에 멈춰 작게 퍼진 뒤 사라진다.
func _finish() -> void:
	_done = true
	set_deferred("monitoring", false)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_mesh, "scale", Vector3.ONE * hit_effect_scale, hit_effect_time)
	tween.tween_callback(queue_free)
