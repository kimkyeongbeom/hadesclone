class_name Enemy
extends CharacterBody3D

## 적 3종의 공통 스크립트. 기본 동작은 근거리(졸개)이고,
## 원거리·덩치는 이 스크립트를 상속해 필요한 함수만 덮어쓴다.

signal died(enemy: Enemy)

## 추적 → 예비 동작 → (공격) → 대기, 체력 0이면 사망
enum State { CHASE, WINDUP, RECOVER, DEAD }

## 체력 바 텍스처 크기 (픽셀). 모든 적이 텍스처 하나를 같이 쓴다.
const BAR_PIXELS := Vector2i(100, 12)

## 최대 체력
@export var max_health := 30.0
## 이동 속도 (m/s)
@export var move_speed := 3.5
## 나무에 정면으로 막혔다고 보는 기준 (실제 속도 / 원래 속도)
@export var stuck_ratio := 0.5
## 이 거리 안에 들면 예비 동작 시작 (m)
@export var attack_range := 1.2
## 예비 동작이 끝나는 순간 이 거리 밖이면 빗나감 (m)
@export var hit_range := 1.6
## 예비 동작 시간 (초)
@export var windup_time := 0.3
## 공격 간격 (초)
@export var attack_interval := 1.0
## 공격 후 제자리에 서 있는 시간 (초)
@export var recover_time := 0.2
## 공격 피해
@export var damage := 10.0
## 넉백을 받는지
@export var takes_knockback := true
## 넉백으로 밀려나는 시간 (초)
@export var knockback_time := 0.15
## 피격 시 흰색 깜빡임 시간 (초)
@export var flash_time := 0.1
## 사망 시 작아지며 사라지는 시간 (초)
@export var death_time := 0.3
## 평소 색
@export var body_color := Color(0.85, 0.18, 0.18)
## 예비 동작 중 색
@export var windup_color := Color(1.0, 0.8, 0.15)
## 피격 깜빡임 색
@export var flash_color := Color(1.0, 1.0, 1.0)
## 체력 바 높이 (m)
@export var health_bar_height := 1.8
## 체력 바 너비 (m)
@export var health_bar_width := 0.9

## true면 셰이더를 미리 컴파일하려고 잠깐 띄운 것이라 게임에 참여하지 않는다.
var prewarm := false
var health: float
var state := State.CHASE

static var _bar_texture: ImageTexture

var _state_time := 0.0
var _attack_cooldown := 0.0
var _flash_left := 0.0
var _knockback_left := 0.0
var _knockback_velocity := Vector3.ZERO
var _material: StandardMaterial3D
var _bar_back: Sprite3D
var _bar_fill: Sprite3D
var _player: Player

@onready var _body: MeshInstance3D = $Body


func _ready() -> void:
	health = max_health
	# 색을 적마다 따로 바꾸므로 머티리얼은 적마다 하나씩 만든다 (스폰 때 한 번만).
	_material = StandardMaterial3D.new()
	_material.albedo_color = body_color
	_body.material_override = _material
	_create_health_bar()
	if prewarm:
		_show_for_prewarm()
		return
	add_to_group("enemies")
	_player = get_tree().get_first_node_in_group("player") as Player


func _physics_process(delta: float) -> void:
	if state == State.DEAD or prewarm:
		return
	_state_time += delta
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_flash_left = maxf(_flash_left - delta, 0.0)

	if _knockback_left > 0.0:
		_knockback_left -= delta
		velocity = _knockback_velocity
		move_and_slide()
	elif _player == null or _player.is_dead:
		# 플레이어가 쓰러지면 공격을 멈추고 제자리에 선다.
		velocity = Vector3.ZERO
		if state != State.CHASE:
			_change_state(State.CHASE)
	else:
		_update_state(delta)
	_update_color()


func take_damage(amount: float, from_position: Vector3, knockback := 0.0) -> void:
	if state == State.DEAD:
		return
	health -= amount
	_flash_left = flash_time
	if health <= 0.0:
		_die()
		return
	_update_health_bar()
	if takes_knockback and knockback > 0.0:
		var direction := Movement.flat_direction(from_position, global_position)
		_knockback_velocity = direction * (knockback / knockback_time)
		_knockback_left = knockback_time
		# 밀려나면 하던 예비 동작이 끊긴다.
		if state == State.WINDUP:
			_change_state(State.CHASE)


func is_dead() -> bool:
	return state == State.DEAD


## 상태별 행동. 기본은 근거리: 곧장 달려들고, 가까우면 예비 동작 후 공격.
func _update_state(_delta: float) -> void:
	var distance := _distance_to_player()
	match state:
		State.CHASE:
			if distance <= attack_range and _attack_cooldown <= 0.0:
				_start_windup()
			elif distance > attack_range * 0.8:
				_move_toward(_player.global_position, move_speed)
			else:
				velocity = Vector3.ZERO
		State.WINDUP:
			velocity = Vector3.ZERO
			if _state_time >= windup_time:
				_attack()
				_change_state(State.RECOVER)
		State.RECOVER:
			velocity = Vector3.ZERO
			if _state_time >= recover_time:
				_change_state(State.CHASE)


## 예비 동작이 끝나는 순간 호출된다. 범위 밖이면 빗나간다.
func _attack() -> void:
	if _distance_to_player() <= hit_range:
		_player.take_damage(damage, global_position)


## 상태가 바뀔 때 호출된다. 덩치의 경고 원처럼 상태에 붙은 표시를 켜고 끌 때 덮어쓴다.
func _on_state_changed(_old_state: State, _new_state: State) -> void:
	pass


## 미리 그려 둘 때 보여줄 것들. 덮어써서 더 보여줄 수 있다.
func _show_for_prewarm() -> void:
	for bar in [_bar_back, _bar_fill]:
		bar.modulate.a = 0.01
		bar.visible = true


func _start_windup() -> void:
	_attack_cooldown = attack_interval
	_change_state(State.WINDUP)


func _change_state(new_state: State) -> void:
	var old_state := state
	state = new_state
	_state_time = 0.0
	_on_state_changed(old_state, new_state)


func _move_toward(point: Vector3, speed: float) -> void:
	var direction := Movement.flat_direction(global_position, point)
	velocity = direction * speed
	move_and_slide()
	Movement.slide_around_trees(self, direction, speed, stuck_ratio)


func _distance_to_player() -> float:
	var offset := _player.global_position - global_position
	offset.y = 0.0
	return offset.length()


func _get_projectile_parent() -> Node:
	var parent := get_tree().get_first_node_in_group("projectiles")
	return parent if parent else get_parent()


func _update_color() -> void:
	if _flash_left > 0.0:
		_material.albedo_color = flash_color
	elif state == State.WINDUP:
		_material.albedo_color = windup_color
	else:
		_material.albedo_color = body_color


## 머리 위 체력 바: 빌보드 Sprite3D 두 장(배경 + 채움). 첫 피해를 입은 뒤부터 보인다.
func _create_health_bar() -> void:
	if _bar_texture == null:
		var image := Image.create(BAR_PIXELS.x, BAR_PIXELS.y, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_bar_texture = ImageTexture.create_from_image(image)
	_bar_back = _make_bar_sprite(Color(0.1, 0.1, 0.1, 0.85), 0)
	_bar_fill = _make_bar_sprite(Color(0.95, 0.2, 0.2), 1)
	# 채움은 왼쪽 끝을 고정하고 오른쪽을 잘라 줄인다.
	_bar_fill.centered = false
	_bar_fill.offset = -Vector2(BAR_PIXELS) * 0.5
	_bar_fill.region_enabled = true
	_bar_fill.region_rect = Rect2(Vector2.ZERO, BAR_PIXELS)


func _make_bar_sprite(color: Color, priority: int) -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _bar_texture
	sprite.modulate = color
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.render_priority = priority
	sprite.pixel_size = health_bar_width / BAR_PIXELS.x
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = Vector3(0.0, health_bar_height, 0.0)
	sprite.visible = false
	add_child(sprite)
	return sprite


func _update_health_bar() -> void:
	var ratio := clampf(health / max_health, 0.0, 1.0)
	_bar_fill.region_rect = Rect2(0.0, 0.0, BAR_PIXELS.x * ratio, BAR_PIXELS.y)
	_bar_back.visible = true
	_bar_fill.visible = true


func _die() -> void:
	_change_state(State.DEAD)
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0
	_material.albedo_color = flash_color
	_bar_back.visible = false
	_bar_fill.visible = false
	died.emit(self)
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(_body, "scale", Vector3.ONE * 0.01, death_time)
	tween.tween_callback(queue_free)
