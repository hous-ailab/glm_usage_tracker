# Z.ai GLM智谱用量监控

**两个核心工具，覆盖全场景监控需求**

---

## 🔥 核心亮点

| 工具 | 适用场景 | 特性 |
|------|----------|------|
| **CLI 命令行工具** | Skill/Agent 调用、脚本集成 | 可编程、输出结构化、适合自动化 |
| **macOS 菜单栏小组件** | 实时监控、日常使用 | 百分比直观显示、开机自启 |

---

## 🚀 快速开始

### 1. 克隆项目后, 先配置 apikey
(推荐)打开文件：`.zai_apikey.json` 文件手动输入

或者，运行以下命令配置:
```bash
node zai-cli-js.js config your-api-key-here
```
运行后会生成在`.zai_apikey.json` 文件中添加。

---

## 2. CLI 命令行工具
**完美适配 Skill/Agent 调用**

```bash
node zai-cli-js.js check
```

---

## 3. macOS 菜单栏小组件

```bash
bash install_launchd.sh
```

✅ **自动复制 API key 到 build 目录，即使移动项目也能正常工作**

效果：
<img width="702" height="944" alt="c1533e3efa81e8bf5ef20d693405a020" src="https://github.com/user-attachments/assets/9511c7cb-1bda-4c79-9c61-f0c9c030f383" />

---

## 项目结构

```
zai-usage-tracker/
├── setup.sh                   # 项目配置脚本
├── install_launchd.sh         # 开机自启安装脚本
├── build_and_run.sh           # Swift 编译运行脚本
├── zai-cli-js.js              # CLI 用量查询工具
├── ZaiMenuBarApp.swift        # macOS 菜单栏应用
├── com.zai.usage-tracker.plist # LaunchAgent 配置模板
├── .zai_apikey.json           # API Key 配置
└── READEME.md                 # 本文档
```

---

## 技术栈

- **Node.js** - CLI 工具
- **Swift/SwiftUI** - macOS 菜单栏应用

---

## 许可证

MIT License
