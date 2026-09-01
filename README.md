# Chinese Pinyin Completion

Godot 4 编辑器插件：输入拼音首字母/全拼，自动补全项目中的中文命名。

<img width="1004" height="406" alt="动画" src="https://github.com/user-attachments/assets/efc6c9d9-a5f2-4edb-aafa-ec707973d7a6" />

1. 在脚本中新增一个中文变量（`var 启动`），保存后插件自动重建索引；
2. 输入拼音缩写（如 `qd`），补全候选**即时弹出并保持显示**；
3. 清除后重新输入缩写，候选**实时更新**；
4. 按 **Tab** 键确认，中文标识符完整插入代码

## 功能

- 中文标识符、枚举成员、节点名（含 % 唯一名）、autoload 单例名
- 输入映射名、动画名、组名、资源路径、中文字符串字面量
- 与 Godot 内置补全共存，自动跟随编辑器主题配色
- 纯 GDScript，无外部依赖，保存文件后自动重建索引

## 安装

1. 在 [Releases](https://github.com/C6Lactide/godot-chinese-pinyin-completion/releases) 下载最新 zip
2. 解压后把 `addons/chinese_pinyin_completion` 放进项目 `addons/` 目录
3. 项目设置 → 插件 → 启用 Chinese Pinyin Completion

## 兼容性

Godot 4.x（在 4.7 上开发与测试）

## AI 贡献声明

本插件的**代码 100% 由 AI 生成**，
作者负责需求定义、逐行代码审查、测试验证与发布。

## 许可证

MIT
