class_name Player
extends CharacterBody3D

## 이동 속도 (m/s)
@export var move_speed := 5.0
## 목표 지점까지 이 거리 안으로 들어오면 멈춤 (m)
@export var stop_distance := 0.2
## 몸을 이동 방향으로 돌리는 빠르기
@export var turn_speed := 15.0
## 클릭 목표를 이 범위(±m) 안으로 잘라 벽 앞에서 멈추게 함
@export var map_half_size := 19.5
## 나무에 정면으로 막혔다고 보는 기준 (실제 속도 / 원래 속도)
@export var stuck_ratio := 0.5
## 클릭 표시 원이 보이는 시간 (초)
@export var click_marker_time := 0.3

var _target := Vector3.ZERO
var _has_target := false
var _marker_tween: Tween

@onready var _click_marker: MeshInstance3D = $ClickMarker


func _ready() -> void:
	# 클릭 표시는 플레이어를 따라다니지 않도록 월드 기준으로 둔다.
	_click_marker.top_level = true
	_prewarm_click_marker()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("move"):
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)
			_show_click_marker(_target)


func _physics_process(delta: float) -> void:
	var wasd := _get_wasd_direction()
	if wasd != Vector3.ZERO:
		_has_target = false
	elif Input.is_action_pressed("move"):
		# 누르고 있으면 커서를 계속 따라간다.
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)

	var direction := wasd
	if direction == Vector3.ZERO and _has_target:
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() <= stop_distance:
			_has_target = false
		else:
			direction = to_target.normalized()

	velocity = direction * move_speed
	move_and_slide()
	if direction != Vector3.ZERO:
		_avoid_tree(direction)
		_face(direction, delta)


## 카메라에서 마우스 위치로 광선을 쏴 바닥(y = 0)과 만나는 점. 못 만나면 null.
func get_mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)


func _set_target(point: Vector3) -> void:
	_target = Vector3(
		clampf(point.x, -map_half_size, map_half_size),
		0.0,
		clampf(point.z, -map_half_size, map_half_size))
	_has_target = true


## WASD를 화면 기준 방향으로 바꾼다 (W = 화면 위쪽, D = 화면 오른쪽).
func _get_wasd_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0.0
	forward.y = 0.0
	var direction := right.normalized() * input.x - forward.normalized() * input.y
	return direction.normalized()


## 나무에 정면으로 부딪혀 미끄러질 방향이 없으면 옆으로 살짝 틀어 비켜간다.
func _avoid_tree(direction: Vector3) -> void:
	if get_real_velocity().length() >= move_speed * stuck_ratio:
		return
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		if not (collider is Node and collider.is_in_group("trees")):
			continue
		var tangent := collision.get_normal().cross(Vector3.UP)
		tangent.y = 0.0
		if tangent.dot(direction) < 0.0:
			tangent = -tangent
		velocity = tangent.normalized() * move_speed
		move_and_slide()
		return


func _face(direction: Vector3, delta: float) -> void:
	# 앞쪽은 -Z 방향(코 상자가 있는 쪽)이다.
	var yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _show_click_marker(point: Vector3) -> void:
	if _marker_tween:
		_marker_tween.kill()
	_click_marker.global_position = Vector3(point.x, 0.02, point.z)
	_click_marker.reset_physics_interpolation()
	_click_marker.scale = Vector3.ONE
	_click_marker.transparency = 0.0
	_click_marker.visible = true
	_marker_tween = create_tween().set_parallel()
	_marker_tween.tween_property(_click_marker, "transparency", 1.0, click_marker_time)
	_marker_tween.tween_property(_click_marker, "scale", Vector3.ONE * 0.5, click_marker_time)
	_marker_tween.chain().tween_callback(_click_marker.hide)


## 첫 클릭 때 셰이더 컴파일로 멈추지 않도록 시작할 때 한 번 그려 둔다.
func _prewarm_click_marker() -> void:
	_click_marker.global_position = global_position + Vector3(0.0, 0.02, 0.0)
	_click_marker.transparency = 0.99
	_click_marker.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_click_marker.visible = false
