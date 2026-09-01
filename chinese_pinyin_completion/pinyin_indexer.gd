# pinyin_indexer.gd
# 纯 GDScript 的中文补全索引器：
#   - 标识符：.gd 中的 var/const/func/signal/class/enum 声明 + enum 中文成员
#   - 输入映射名：project.godot [input] 节
#   - 动画名：.tscn/.tres 中 SpriteFrames 动画名与 Animation 资源名
#   - 节点名：.tscn [node name="..."]
#   - 组名：.tscn groups=[...]
#   - 资源文件名：res:// 下含中文的 Godot 资源文件
#   - autoload 单例名：project.godot [autoload] 节
#   - 字符串字面量：.gd 中出现的含中文的字符串
# 每个词带 kind 集合（identifier / input_action / animation / node /
# group / resource / singleton / string），由插件按编辑上下文决定是否显示。
@tool
extends RefCounted

const DICT_PATH := "res://addons/chinese_pinyin_completion/data/pinyin_dict.json"
const MAX_RESULTS := 80
const SKIP_DIRS := ["addons", ".godot", ".git", "assets", "test", "libs", "import"]
const RESOURCE_EXTS := [
	"tscn", "tres", "gd", "png", "jpg", "jpeg", "webp", "svg",
	"wav", "ogg", "mp3", "ttf", "otf", "glb", "obj", "fbx",
	"hdr", "exr", "gdshader", "shader", "json", "res",
]

var _dict := {}
var _entries: Array = []  # [{ "name": String, "display": String, "kinds": Dictionary }]
var _scanned := false

var _ident_re := RegEx.new()
var _enum_re := RegEx.new()
var _member_re := RegEx.new()
var _input_action_re := RegEx.new()
var _singleton_re := RegEx.new()
var _animation_re := RegEx.new()
var _animation_resource_re := RegEx.new()
var _node_re := RegEx.new()
var _group_re := RegEx.new()
var _string_re := RegEx.new()
var _string_single_re := RegEx.new()


func _init() -> void:
	# 声明关键字（class_name 必须在 class 之前匹配），捕获随后的标识符
	_ident_re.compile(
		"(?m)(?<![#\\w])(?:static\\s+)?(?:class_name|var|const|func|signal|class|enum)\\s+([A-Za-z0-9_\\x{4e00}-\\x{9fa5}]+)"
	)
	# enum 块（含匿名 enum），用于提取中文成员
	_enum_re.compile(
		"(?m)(?<![#\\w])enum\\s+[A-Za-z0-9_\\x{4e00}-\\x{9fa5}]*\\s*\\{([^}]*)\\}"
	)
	_member_re.compile("([A-Za-z0-9_\\x{4e00}-\\x{9fa5}]+)")
	# project.godot [input] 节中的输入映射名
	_input_action_re.compile('(?m)^"([^"]+)"\\s*=\\s*\\{')
	# project.godot [autoload] 节中的单例名
	_singleton_re.compile("(?m)^([A-Za-z0-9_\\x{4e00}-\\x{9fa5}]+)\\s*=\\s*\"?\\*?(?:res|uid)://")
	# SpriteFrames 动画名：{"name": &"走", ...} 或 {"name": "走", ...}
	_animation_re.compile('(?m)"name":\\s*&?"([^"]*[\\x{4e00}-\\x{9fa5}][^"]*)"')
	# Animation 等子资源的 resource_name（AnimationPlayer 动画名）
	_animation_resource_re.compile('(?m)resource_name = "([^"]*[\\x{4e00}-\\x{9fa5}][^"]*)"')
	# 节点名
	_node_re.compile('(?m)\\[node name="([^"]*[\\x{4e00}-\\x{9fa5}][^"]*)"')
	# 组名（groups=[...]）
	_group_re.compile('(?m)groups=\\[[^\\]]*"([^"]*[\\x{4e00}-\\x{9fa5}][^"]*)"')
	# 代码中的字符串字面量（含中文）
	_string_re.compile('(?m)(?<![\\w])"([^"\\n]*[\\x{4e00}-\\x{9fa5}][^"\\n]*)"')
	_string_single_re.compile("(?m)(?<![\\w])'([^'\\n]*[\\x{4e00}-\\x{9fa5}][^'\\n]*)'")


# ------------------- 字典 -------------------

func load_dictionary() -> void:
	_dict = _load_json(DICT_PATH)


func get_dict_size() -> int:
	return _dict.size()


func is_dictionary_loaded() -> bool:
	return not _dict.is_empty()


# ------------------- 扫描项目 -------------------

func scan_project() -> void:
	var kinds := {}  # name -> { kind: true }
	_scan_dir("res://", kinds)
	_scan_project_settings(kinds)
	_rebuild_entries(kinds)
	_scanned = true


func is_scanned() -> bool:
	return _scanned


func get_entries() -> Array:
	return _entries


func _rebuild_entries(kinds: Dictionary) -> void:
	_entries.clear()
	var seen := {}  # name -> true（已生成 display）
	for name in kinds:
		if seen.has(name):
			continue
		seen[name] = true
		var hints := _build_hints(name)
		if hints.is_empty():
			continue
		_entries.append({
			"name": name,
			"display": "%s [%s/%s]" % [name, hints.full, hints.initials],
			"kinds": kinds[name],
		})

	_entries.sort_custom(func(a, b): return a.name < b.name)


func _scan_dir(path: String, kinds: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if dir.current_is_dir():
			if not fname.begins_with(".") and not SKIP_DIRS.has(fname):
				_scan_dir(path.path_join(fname), kinds)
		else:
			if fname.begins_with("_debug"):
				fname = dir.get_next()
				continue
			var full := path.path_join(fname)
			if fname.ends_with(".gd"):
				_scan_gd_file(full, kinds)
			elif fname.ends_with(".tscn") or fname.ends_with(".tres"):
				_scan_scene_file(full, kinds)
			if _contains_han(fname) and _is_resource_file(fname):
				_add_kind(kinds, fname, "resource")
		fname = dir.get_next()
	dir.list_dir_end()


func _is_resource_file(fname: String) -> bool:
	if fname.ends_with(".import") or fname.ends_with(".uid"):
		return false
	var dot := fname.rfind(".")
	if dot == -1:
		return false
	var ext := fname.substr(dot + 1).to_lower()
	return RESOURCE_EXTS.has(ext)


func _scan_gd_file(path: String, kinds: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()

	for m in _ident_re.search_all(content):
		var name := m.get_string(1)
		if _contains_han(name):
			_add_kind(kinds, name, "identifier")

	# enum 中文成员（如 enum 状态 { 待机, 移动 }）
	for m in _enum_re.search_all(content):
		var body := m.get_string(1)
		for seg in body.split(","):
			var tm := _member_re.search(seg)
			if tm == null:
				continue
			var member := tm.get_string(1)
			if _contains_han(member):
				_add_kind(kinds, member, "identifier")

	for m in _string_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "string")
	for m in _string_single_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "string")


func _scan_scene_file(path: String, kinds: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var content := f.get_as_text()
	f.close()

	for m in _animation_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "animation")
	for m in _animation_resource_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "animation")
	for m in _node_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "node")
	for m in _group_re.search_all(content):
		_add_kind(kinds, m.get_string(1), "group")


func _scan_project_settings(kinds: Dictionary) -> void:
	var f := FileAccess.open("res://project.godot", FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	_scan_section(text, "[input]", _input_action_re, "input_action", kinds)
	_scan_section(text, "[autoload]", _singleton_re, "singleton", kinds)


func _scan_section(text: String, section_name: String, re: RegEx, kind: String, kinds: Dictionary) -> void:
	var start := text.find(section_name)
	if start == -1:
		return
	start = text.find("\n", start)
	if start == -1:
		return
	var end := text.find("\n[", start + 1)
	if end == -1:
		end = text.length()
	var section := text.substr(start, end - start)
	for m in re.search_all(section):
		_add_kind(kinds, m.get_string(1), kind)


func _add_kind(kinds: Dictionary, name: String, kind: String) -> void:
	if name.is_empty():
		return
	if not kinds.has(name):
		kinds[name] = {}
	kinds[name][kind] = true


# ------------------- 拼音提示 -------------------

# 返回 {"full": 全拼(含ASCII字母数字), "initials": 首字母}；不含中文或拼音缺失时返回空字典
func _build_hints(identifier: String) -> Dictionary:
	var full := ""
	var initials := ""
	var han_count := 0
	for i in identifier.length():
		var ch := identifier[i]
		if _is_han(ch):
			var py: String = _dict.get(ch, "")
			if py.is_empty():
				return {}
			han_count += 1
			full += py
			initials += py.left(1)
		else:
			var low := ch.to_lower()
			if (low >= "a" and low <= "z") or (low >= "0" and low <= "9"):
				full += low
				initials += low
	if han_count == 0:
		return {}
	return {"full": full, "initials": initials}


# ------------------- 匹配 -------------------

func matches_for(query: String) -> Array:
	query = query.to_lower()
	if query.is_empty():
		return []
	var out := []
	for e in _entries:
		if _is_subsequence(query, e.display):
			out.append(e)
			if out.size() >= MAX_RESULTS:
				break
	return out


func _is_subsequence(query: String, text: String) -> bool:
	var qi := 0
	var qlen := query.length()
	var text_lower := text.to_lower()
	for i in text_lower.length():
		if qi < qlen and text_lower[i] == query[qi]:
			qi += 1
			if qi == qlen:
				return true
	return qi == qlen


# ------------------- 工具 -------------------

func _is_han(ch: String) -> bool:
	var code := ch.unicode_at(0)
	return code >= 0x4e00 and code <= 0x9fa5


func _contains_han(text: String) -> bool:
	for i in text.length():
		if _is_han(text[i]):
			return true
	return false


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("拼音补全：解析 JSON 失败: %s" % path)
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data
