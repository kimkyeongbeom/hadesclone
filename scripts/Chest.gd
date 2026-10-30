extends Node3D

## 보물상자: 플레이어가 TriggerArea에 들어오면 open 애니메이션을 한 번 재생하고
## 열린 채로 둔다. 열리면 플레이어가 검을 손에 든다. 다시 다가가도 재생하지 않는다.

## 재생할 애니메이션 이름
@export var open_animation := &"open"

var _opened := false

@onready var _animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var _trigger: Area3D = $TriggerArea


func _ready() -> void:
	_trigger.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _opened or not body is Player:
		return
	_opened = true
	_animation_player.play(open_animation)
	# 상자 안에서 검을 꺼내 든다.
	body.equip_sword()
	_trigger.set_deferred("monitoring", false)
