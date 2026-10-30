extends CanvasLayer

## 체력 바, 스킬 칸 3개, 웨이브 표시, 웨이브 안내, 피격 비네트, 결과 화면을 코드로 만든다.
## 플레이어와 WaveManager의 신호만 듣는다. R 키 재시작도 여기서 처리한다.

@export var player: Player
@export var wave_manager: WaveManager
## 웨이브 시작 안내가 보이는 시간 (초)
@export var announce_time := 1.5
## 피격 비네트가 보이는 시간 (초)
@export var vignette_time := 0.2
## 쓰러진 뒤 결과 화면까지 (초)
@export var defeat_delay := 1.0
## 마지막 적을 잡은 뒤 승리 화면까지 (초)
@export var victory_delay := 0.6

const SKILL_KEYS := ["우클릭", "Q", "Space"]
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.9, 0.05, 0.05, 0.85);
void fragment() {
	float edge = smoothstep(0.3, 0.75, length(UV - vec2(0.5)) * 1.3);
	COLOR = vec4(tint.rgb, tint.a * edge * intensity);
}
"""

var _health_fill: ColorRect
var _health_label: Label
var _skill_keys: Array[Label] = []
var _skill_shades: Array[ColorRect] = []
var _skill_timers: Array[Label] = []
var _skill_left: Array[float] = [0.0, 0.0, 0.0]
var _wave_label: Label
var _announce_label: Label
var _vignette: ColorRect
var _result: Control
var _result_title: Label
var _result_stats: Label
var _wave_number := 0
var _wave_count := 0
var _last_health := 0.0
var _result_shown := false
var _announce_tween: Tween
var _vignette_tween: Tween


func _ready() -> void:
	_build()
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	player.skill_used.connect(_on_skill_used)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.remaining_changed.connect(_on_remaining_changed)
	wave_manager.all_waves_cleared.connect(_on_all_waves_cleared)
	_last_health = player.max_health
	_on_health_changed(player.max_health, player.max_health)


func _process(delta: float) -> void:
	for i in _skill_left.size():
		_skill_left[i] = maxf(_skill_left[i] - delta, 0.0)
		var cooling := _skill_left[i] > 0.0
		_skill_keys[i].visible = not cooling
		_skill_shades[i].visible = cooling
		_skill_timers[i].visible = cooling
		if cooling:
			_skill_timers[i].text = "%.1f" % _skill_left[i]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()


func _on_health_changed(current: float, maximum: float) -> void:
	_health_fill.anchor_right = clampf(current / maximum, 0.0, 1.0)
	_health_label.text = "%d / %d" % [ceili(current), int(maximum)]
	if current < _last_health:
		_flash_vignette()
	_last_health = current


func _on_skill_used(slot: int, cooldown: float) -> void:
	_skill_left[slot] = cooldown


func _on_wave_started(wave_number: int, wave_count: int) -> void:
	_wave_number = wave_number
	_wave_count = wave_count
	_announce("웨이브 %d" % wave_number)


func _on_remaining_changed(remaining: int) -> void:
	_wave_label.text = "웨이브 %d / %d · 남은 적 %d" % [_wave_number, _wave_count, remaining]


func _on_player_died() -> void:
	await get_tree().create_timer(defeat_delay).timeout
	_show_result("쓰러졌다…")


func _on_all_waves_cleared() -> void:
	await get_tree().create_timer(victory_delay).timeout
	_show_result("승리!")


func _show_result(title: String) -> void:
	if _result_shown:
		return
	_result_shown = true
	var seconds := int(wave_manager.elapsed)
	_result_title.text = title
	_result_stats.text = "처치 %d · 시간 %d:%02d" % [wave_manager.kills, seconds / 60, seconds % 60]
	_result.visible = true


func _announce(text: String) -> void:
	if _announce_tween:
		_announce_tween.kill()
	_announce_label.text = text
	_announce_label.modulate.a = 1.0
	_announce_label.visible = true
	_announce_tween = create_tween()
	_announce_tween.tween_interval(announce_time * 0.7)
	_announce_tween.tween_property(_announce_label, "modulate:a", 0.0, announce_time * 0.3)
	_announce_tween.tween_callback(_announce_label.hide)


func _flash_vignette() -> void:
	if _vignette_tween:
		_vignette_tween.kill()
	var material := _vignette.material as ShaderMaterial
	material.set_shader_parameter("intensity", 1.0)
	_vignette_tween = create_tween()
	_vignette_tween.tween_method(
		func(value: float) -> void: material.set_shader_parameter("intensity", value),
		1.0, 0.0, vignette_time)


# ---- 화면 구성 -------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	# 비네트는 맨 아래에 깔고, 처음부터 그려 두어 셰이더 컴파일을 미리 끝낸다.
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	_vignette.material = material
	root.add_child(_vignette)

	_build_health_bar(root)
	_build_skill_slots(root)

	_wave_label = _make_label(26, HORIZONTAL_ALIGNMENT_CENTER)
	_wave_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_wave_label.offset_left = -300.0
	_wave_label.offset_right = 300.0
	_wave_label.offset_top = 16.0
	_wave_label.offset_bottom = 56.0
	root.add_child(_wave_label)

	_announce_label = _make_label(64, HORIZONTAL_ALIGNMENT_CENTER)
	_announce_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_announce_label.offset_bottom = -160.0
	_announce_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_announce_label.visible = false
	root.add_child(_announce_label)

	_build_result(root)


func _build_health_bar(root: Control) -> void:
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 24.0
	box.offset_right = 304.0
	box.offset_top = -56.0
	box.offset_bottom = -26.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	box.add_child(_make_rect(Color(0.08, 0.08, 0.08, 0.8)))
	_health_fill = _make_rect(Color(0.85, 0.12, 0.12))
	box.add_child(_health_fill)
	_health_label = _make_label(20, HORIZONTAL_ALIGNMENT_CENTER)
	_health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_health_label)


func _build_skill_slots(root: Control) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -118.0
	row.offset_right = 118.0
	row.offset_top = -90.0
	row.offset_bottom = -18.0
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(row)

	for key in SKILL_KEYS:
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(70.0, 70.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(slot)
		slot.add_child(_make_rect(Color(0.15, 0.2, 0.35, 0.9)))
		var key_label := _make_label(18, HORIZONTAL_ALIGNMENT_CENTER)
		key_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		key_label.text = key
		slot.add_child(key_label)
		# 쿨다운 중엔 어둡게 덮고 키 이름 대신 남은 초를 보여준다.
		var shade := _make_rect(Color(0.0, 0.0, 0.0, 0.6))
		shade.visible = false
		slot.add_child(shade)
		var timer := _make_label(24, HORIZONTAL_ALIGNMENT_CENTER)
		timer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		timer.visible = false
		slot.add_child(timer)
		_skill_keys.append(key_label)
		_skill_shades.append(shade)
		_skill_timers.append(timer)


func _build_result(root: Control) -> void:
	_result = _make_rect(Color(0.0, 0.0, 0.0, 0.55))
	_result.visible = false
	root.add_child(_result)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(column)

	_result_title = _make_label(64, HORIZONTAL_ALIGNMENT_CENTER)
	_result_stats = _make_label(28, HORIZONTAL_ALIGNMENT_CENTER)
	var hint := _make_label(22, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "R 키로 다시 시작"
	for label in [_result_title, _result_stats, hint]:
		column.add_child(label)


func _make_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _make_label(font_size: int, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 한글은 시스템 폰트로 표시한다.
func _make_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray([
		"Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.set_constant("outline_size", "Label", 6)
	theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.8))
	return theme
