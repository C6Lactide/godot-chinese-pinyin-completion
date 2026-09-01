# Chinese Pinyin Completion

Godot 4 编辑器插件：输入拼音首字母/全拼，自动补全项目中的中文命名。

> 兼容 Godot 4.x（在 Godot 4.7 上开发与测试；所用 API 均为 Godot 4.0 起提供）。

## 覆盖范围

| 类别 | 来源 | 示例（输入 → 补全） |
|---|---|---|
| 标识符 | `.gd` 中 var/const/func/signal/class/enum 声明 | `ks` → `开始`，`ksan` → `_on_开始按钮_pressed` |
| 枚举中文成员 | `enum 状态 { 待机, 移动 }` | `dj` → `待机`，`yd` → `移动` |
| 节点名 | `.tscn` 中 `[node name="..."]`（含唯一名 `%`） | `sm` → `生命显示`，`smx2` → `生命显示2` |
| 输入映射名 | `project.godot` 的 `[input]` 节 | `yy` → `右移` |
| 动画名 | SpriteFrames 动画、Animation 资源 | `zou` → `走`，`sw` → `死亡动画` |
| 组名 | `.tscn` 中 `groups=[...]` | `drz` → `敌人组` |
| 资源文件名 | `res://` 下含中文的资源文件 | `wj` → `玩家.tscn` |
| autoload 单例名 | `project.godot` 的 `[autoload]` 节 | 中文单例名 |
| 中文字符串字面量 | 代码中出现过的中文字符串（兜底） | `js` → `加速` |

## 安装

1. 将 `addons/chinese_pinyin_completion` 目录复制到项目 `addons/` 下（或解压发布 zip）。
2. 项目设置 → 插件 → 启用 `Chinese Pinyin Completion`。
3. 重启编辑器（首次启用后）。

## 使用

1. 项目设置 → 插件 → 启用 `Chinese Pinyin Completion`。
2. **代码位置**输入拼音：补全标识符、节点名（`$`/`%` 后）、单例名。
3. **引号内**输入拼音：补全输入映射名、动画名、组名、资源路径、字符串（自动带引号）。
4. 也可按 `Ctrl+Space` 手动触发。
5. 保存 `.gd` / `.tscn` / `.tres` / `project.godot` 后自动重建索引（延迟 1 秒）。

## 外观

补全项颜色跟随编辑器主题（浅色主题自动深色、深色主题自动亮色）；
**字符串类补全（输入映射/动画/组/资源/字符串）用青绿色**，标识符/节点/单例用主题强调色。

## 文件

- `pinyin_completion_plugin.gd`：编辑器插件入口（挂接补全信号、上下文过滤、着色）
- `pinyin_indexer.gd`：项目扫描与拼音索引
- `data/pinyin_dict.json`：汉字 → 拼音字典（约 2.6 万常用字，随插件发布）

## 说明

- 纯 GDScript 实现，不调用外部进程。
- 扫描跳过 `addons`、`.godot`、`assets`、`test`、`libs` 等目录及 `_debug` 前缀文件。
- 字典未覆盖的生僻字不会生成拼音补全（中文输入本身由 Godot 内置补全支持）。
