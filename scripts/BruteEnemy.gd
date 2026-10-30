class_name BruteEnemy
extends Enemy

## 덩치: 느리게 쫓아와 2 m 안에 들면 바닥에 경고 원을 띄우고 반경 2.5 m를 내려찍는다.
## 공격 판정은 공통 스크립트의 hit_range(= 내려찍기 반경)를 그대로 쓴다.

@onready var _warning_area: MeshInstance3D = $WarningArea
@onready var _warning_fill: MeshInstance3D = $WarningFill


func _ready() -> void:
	super()
	# 경고 원 메시는 반지름 1로 만들어 두고 내려찍기 반경에 맞게 키운다.
	_warning_area.scale = Vector3(hit_range, 1.0, hit_range)


func _update_state(delta: float) -> void:
	super(delta)
	if state == State.WINDUP:
		# 안쪽 원이 예비 동작 동안 차올라 떨어지는 때를 보여준다.
		var t := clampf(_state_time / windup_time, 0.05, 1.0) * hit_range
		_warning_fill.scale = Vector3(t, 1.0, t)


func _on_state_changed(_old_state: State, new_state: State) -> void:
	var show := new_state == State.WINDUP
	_warning_area.visible = show
	_warning_fill.visible = show
	if show:
		_warning_fill.scale = Vector3(0.05, 1.0, 0.05)


func _show_for_prewarm() -> void:
	super()
	_warning_area.visible = true
	_warning_fill.visible = true
