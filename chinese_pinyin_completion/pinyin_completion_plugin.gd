# pinyin_completion_plugin.gd
#
# 中文拼音补全编辑器插件：
#   - 自动扫描项目中的中文标识符 (var/const/func/signal/class/enum)
#   - 输入拼音首字母或全拼时，把匹配的中文标识符追加进代码补全列表
#   - 与 Godot 内置 GDScript 补全共存（挂接 code_completion_requested，
#     在内置选项生成之后追加我们的选项，再统一刷新）
@tool
extends EditorPlugin

const INDEXER_PATH := "res://addons/chinese_pinyin_completion/pinyin_indexer.gd"
const RESCAN_DELAY := 1.0

var _indexer = null
var _scan_timer: Timer = null
var _injected := {}  # instance_id -> Callable(绑定到对应 CodeEdit)


func _enter_tree() -> void:
	var indexer_script = load(INDEXER_PATH)
	if indexer_script == null:
		push_error("拼音补全：找不到索引器脚本 ", INDEXER_PATH)
		return
	_indexer = indexer_script.new()
	_indexer.load_dictionary()
	call_deferred("_deferred_start")


func _deferred_start() -> void:
	if _indexer == null:
		return
	_indexer.scan_project()
	print("拼音补全：已索引 ", _indexer.get_entries().size(), " 个中文标识符（字典 ", _indexer.get_dict_size(), " 字）")

	var fs := get_editor_interface().get_resource_filesystem()
	if not fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.connect(_on_filesystem_changed)

	var script_editor := get_editor_interface().get_script_editor()
	if not script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.connect(_on_editor_script_changed)

	_scan_timer = Timer.new()
	_scan_timer.one_shot = true
	_scan_timer.wait_time = RESCAN_DELAY
	_scan_timer.timeout.connect(_on_scan_timeout)
	add_child(_scan_timer)

	_inject_to_all_editors()


func _exit_tree() -> void:
	_remove_from_all_editors()

	var script_editor := get_editor_interface().get_script_editor()
	if script_editor != null and script_editor.editor_script_changed.is_connected(_on_editor_script_changed):
		script_editor.editor_script_changed.disconnect(_on_editor_script_changed)

	var fs := get_editor_interface().get_resource_filesystem()
	if fs != null and fs.filesystem_changed.is_connected(_on_filesystem_changed):
		fs.filesystem_changed.disconnect(_on_filesystem_changed)

	if _scan_timer != null:
		_scan_timer.queue_free()
		_scan_timer = null

	_indexer = null


# ------------------- 自动重建索引 -------------------

func _on_filesystem_changed() -> void:
	if _scan_timer == null:
		return
	if not _scan_timer.is_stopped():
		_scan_timer.stop()
	_scan_timer.start()


func _on_scan_timeout() -> void:
	if _indexer == null:
		return
	_indexer.scan_project()


# ------------------- 注入 / 移除 -------------------

func _on_editor_script_changed(_script) -> void:
	call_deferred("_inject_to_all_editors")


func _inject_to_all_editors() -> void:
	var script_editor := get_editor_interface().get_script_editor()
	if script_editor == null:
		return
	for editor in script_editor.get_open_script_editors():
		var code_edit := _find_code_edit(editor)
		if code_edit != null:
			_inject(code_edit)


func _remove_from_all_editors() -> void:
	for id in _injected.keys():
		var code_edit: Object = instance_from_id(id)
		if code_edit is CodeEdit:
			_remove(code_edit)
	_injected.clear()


func _find_code_edit(node: Node) -> CodeEdit:
	if node is CodeEdit:
		return node
	for child in node.get_children():
		var result := _find_code_edit(child)
		if result != null:
			return result
	return null


func _inject(code_edit: CodeEdit) -> void:
	var id := code_edit.get_instance_id()
	if _injected.has(id):
		return
	var callback := Callable(self, "_on_completion_requested").bind(code_edit)
	if not code_edit.code_completion_requested.is_connected(callback):
		code_edit.code_completion_requested.connect(callback)
	_injected[id] = callback


func _remove(code_edit: CodeEdit) -> void:
	var id := code_edit.get_instance_id()
	if not _injected.has(id):
		return
	var callback: Callable = _injected[id]
	if code_edit.code_completion_requested.is_connected(callback):
		code_edit.code_completion_requested.disconnect(callback)
	_injected.erase(id)


# ------------------- 核心补全 -------------------

func _on_completion_requested(code_edit: CodeEdit) -> void:
	if _indexer == null or not is_instance_valid(code_edit):
		return

	# 取出光标前正在输入的英文（拼音）前缀
	var query := _trailing_letters(code_edit)
	if query.is_empty():
		return

	# 是否处于字符串字面量内（输入映射名 / 动画名 / 字符串使用处）
	var caret_line := code_edit.get_caret_line()
	var caret_col := code_edit.get_caret_column()
	var in_string := (
		code_edit.is_in_string(caret_line, caret_col - 1) != -1
		or code_edit.is_in_string(caret_line, caret_col) != -1
	)

	var matches: Array = _indexer.matches_for(query)
	if matches.is_empty():
		return

	# 上下文过滤：
	#   - 字符串内：显示所有类别（输入映射/动画/节点/组/资源路径/字符串…）
	#   - 代码位置：只显示标识符、节点名（$节点）、单例名
	var allowed := []
	for m in matches:
		if not in_string:
			var kinds: Dictionary = m.kinds
			if not (kinds.has("identifier") or kinds.has("node") or kinds.has("singleton")):
				continue
		allowed.append(m)
	if allowed.is_empty():
		return

	# 保留编辑器已生成的内置补全选项（此时内置 handler 已先执行）
	var builtin: Array = code_edit.get_code_completion_options()
	for opt in builtin:
		code_edit.add_code_completion_option(
			int(opt.get("kind", CodeEdit.KIND_PLAIN_TEXT)),
			str(opt.get("display_text", "")),
			str(opt.get("insert_text", "")),
			opt.get("font_color", Color.WHITE),
			opt.get("icon", null),
			opt.get("default_value", null)
		)

	# 追加拼音命中的中文词；display 里带全拼/首字母，
	# 这样 CodeEdit 默认的子序列过滤器能把它们筛出来。
	# 字符串类（输入映射/动画/字符串）与标识符用不同颜色区分。
	for m in allowed:
		var kinds: Dictionary = m.kinds
		var is_string_kind: bool = (
			kinds.has("input_action")
			or kinds.has("animation")
			or kinds.has("group")
			or kinds.has("resource")
			or kinds.has("string")
		)
		code_edit.add_code_completion_option(
			CodeEdit.KIND_PLAIN_TEXT,
			str(m.display),
			str(m.name),
			_option_color(is_string_kind)
		)

	code_edit.update_code_completion_options(true)


# 取光标左侧连续的 ASCII 字母（即用户正在输入的拼音）
func _trailing_letters(code_edit: CodeEdit) -> String:
	var line := code_edit.get_line(code_edit.get_caret_line())
	var col := code_edit.get_caret_column()
	var result := ""
	for i in range(col - 1, -1, -1):
		var ch := line[i]
		var code := ch.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 65 and code <= 90):
			result = ch + result
		else:
			break
	return result.to_lower()


# 补全项颜色：跟随编辑器主题（浅色/深色主题都清晰），字符串类用青绿区分
func _option_color(is_string_kind: bool) -> Color:
	var base := get_editor_interface().get_base_control()
	if base != null and base.has_theme_color("accent_color", "Editor"):
		var accent: Color = base.get_theme_color("accent_color", "Editor")
		if not is_string_kind:
			return accent
	if is_string_kind:
		return Color(0.08, 0.6, 0.45)
	return Color(0.2, 0.55, 0.9)
