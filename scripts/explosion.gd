class_name Explosion
extends Node3D
## Neon burst: particle sphere + expanding wireframe flash.

var color := Color.WHITE
var scale_mult := 1.0

var _t := 0.0
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _explosion_snd: AudioStreamPlayer = null


func _ready() -> void:
	_build_particles()
	_build_flash()
	_build_audio()


func _build_particles() -> void:
	var p := GPUParticles3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.rings = 3
	sphere.radial_segments = 4
	sphere.material = G.unshaded(color, 2.6)
	p.draw_pass_1 = sphere
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, 0.0)
	proc.spread = 180.0
	proc.initial_velocity_min = 55.0
	proc.initial_velocity_max = 140.0
	proc.gravity = Vector3.ZERO
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 1.2
	proc.scale_min = 0.8
	proc.scale_max = 1.8
	p.process_material = proc
	p.amount = 26
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.preprocess = 0.12
	p.scale = Vector3.ONE * scale_mult
	add_child(p)


func _build_flash() -> void:
	_flash = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.1
	m.height = 2.2
	m.radial_segments = 6
	m.rings = 4
	_flash.mesh = m
	_flash_mat = G.unshaded(Color.WHITE, 3.0)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	_flash.material_override = _flash_mat
	add_child(_flash)

func _build_audio() -> void:
	_explosion_snd = AudioStreamPlayer.new()
	_explosion_snd.stream = AudioStreamWAV.load_from_file("res://sounds/explosion1.wav")
	_explosion_snd.autoplay = true
	_explosion_snd.volume_linear = 0.3
	_explosion_snd.pitch_scale = randf_range(0.9, 1.1)
	add_child(_explosion_snd)

func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / 0.3, 0.0, 1.0)
	if _flash:
		_flash.scale = Vector3.ONE * (0.4 + 2.4 * k) * maxf(scale_mult, 0.6)
		_flash_mat.albedo_color.a = 0.5 * (1.0 - k)
		if k >= 1.0:
			_flash.visible = false
	if _t > 1.0:
		queue_free()
