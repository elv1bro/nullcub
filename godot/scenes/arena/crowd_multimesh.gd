## Зрители одним MultiMesh: меш (квад-спрайт толпы или меш зрителя), позиции, цвета и custom data экземпляров — данные сцены.
## Спрайты: квад + ShaderMaterial crowd_sprite.gdshader (атлас модульных существ, tools/blender/crowd_sprites.py), в custom —
## вариант, фаза, яркость.
## Почему не готовый MultiMesh в .tscn: builder работает headless, там RenderingServer — заглушка, и буфер экземпляров
## MultiMesh не сохраняется (instance_count есть, позиций нет). Поэтому builder пишет xforms/colors, а MultiMesh
## заполняется здесь при загрузке — это заливка данных, не сборка сцены.
class_name CrowdMultiMesh
extends MultiMeshInstance3D

@export var mesh: Mesh
## по 12 чисел на экземпляр: столбцы базиса x, y, z, затем origin
@export var xforms := PackedFloat32Array()
@export var colors := PackedColorArray()
## custom data экземпляров (пусто — без custom): для спрайтов x — вариант, y — фаза, z — яркость
@export var customs := PackedColorArray()


func _ready() -> void:
	build()


func build() -> void:
	var n := colors.size()
	if mesh == null or xforms.size() != n * 12:
		push_warning("CrowdMultiMesh %s: нет меша или данные не сходятся (%d / %d)" % [name, xforms.size(), n])
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = customs.size() == n
	mm.mesh = mesh
	mm.instance_count = n
	for i in range(n):
		var k := i * 12
		var b := Basis(Vector3(xforms[k], xforms[k + 1], xforms[k + 2]), Vector3(xforms[k + 3], xforms[k + 4], xforms[k + 5]),
			Vector3(xforms[k + 6], xforms[k + 7], xforms[k + 8]))
		mm.set_instance_transform(i, Transform3D(b, Vector3(xforms[k + 9], xforms[k + 10], xforms[k + 11])))
		mm.set_instance_color(i, colors[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, customs[i])
	multimesh = mm


func count() -> int:
	return colors.size()
