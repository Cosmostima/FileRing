<div align="center">

<img src="Assets/FileRingIcon.png" alt="FileRing 图标" width="200"/>

<br/>

# FileRing

轻扫即可快速访问您的文件和文件夹

![Platform](https://img.shields.io/badge/platform-macOS%2013.0+-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.0+-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

[English](README.md) | 简体中文

</div>

## 概述

FileRing 提供一个圆形启动器，显示您最近和最常使用的文件和文件夹。按住可自定义的快捷键即可在光标处打开圆形面板，移动鼠标选择项目，松开快捷键即可打开。界面根据使用模式将项目组织成六个不同的部分。

**基本工作流程：**
1. 按住触发快捷键（默认：`⌃ Control + X`）
2. 出现一个圆形面板，显示六个部分的文件和文件夹
3. 将鼠标移到所需的部分和项目上
4. 松开快捷键执行操作（打开文件/文件夹、复制文件或复制路径）
5. 将光标移到空白区域取消操作

![概览示例](Assets/OverView.gif)

## 支持者

感谢每一位支持这个项目的人！

<a href="https://github.com/jilinju0715-pixel"><img src="Assets/supporters.svg" alt="jilinju0715-pixel" height="66"/></a>

## 功能特性

### 1. 文件分类

FileRing 使用 macOS Spotlight 将您的文件和文件夹分为六个部分：

- **文件 - 最近打开** 🕐
- **文件 - 最近保存** 💾
- **文件 - 常用（3天内）** ⭐
- **文件夹 - 最近打开** 🕐
- **文件夹 - 最近保存** 💾
- **文件夹 - 常用（3天内）** ⭐

每个部分根据您的实际使用情况显示 4-10 个项目（可配置，默认：6），无需手动添加书签。

<div><video src="https://github.com/user-attachments/assets/3e1b0f8e-92a8-483e-a4a1-0ba2f3b20bcc" controls></video></div>

### 2. 快捷操作

将鼠标悬停在任何项目上以显示快速操作：

### 打开
在默认应用程序中启动文件或在访达中打开文件夹

<div><video src="https://github.com/user-attachments/assets/054b5c50-542b-401d-8793-0bae187ab55e" controls></video></div>


<div><video src="https://github.com/user-attachments/assets/c7a1d5e8-56d5-4cb1-9ae0-1c0feb6209ef" controls></video></div>


### 复制文件
将整个文件复制到剪贴板以便粘贴到其他位置（仅限文件）

<div><video src="https://github.com/user-attachments/assets/56ea54bd-bc22-45a0-a41f-9b537adabfed" controls></video></div>

### 复制路径
将绝对文件/文件夹路径复制为文本

<div><video src="https://github.com/user-attachments/assets/84b4d13c-e214-4dca-b814-6c9b1461ac24" controls></video></div>

### 3. 文件夹授权

FileRing 仅访问您明确授权的文件夹。该应用程序对您选择的目录具有只读访问权限，并使用 macOS 安全范围书签来安全访问文件。

### 4. 菜单栏应用

FileRing 是一个轻量级的菜单栏应用程序。Dock 图标和状态栏图标都可以在设置中自定义。点击 Dock 图标（可见时）可快速打开设置。
<div align="center">
<img src="Assets/MenuBar.png" alt="MenuBar Example" width="50%"/>
</div>

## 安装

**系统要求：** macOS 13.0 或更高版本 · Apple Silicon 或 Intel

### 直接下载（推荐）

1. 前往 [Releases](https://github.com/Cosmostima/FileRing/releases) 页面，下载最新的 `FileRing.dmg`
2. 打开 DMG，将 `FileRing.app` 拖入应用程序文件夹
3. 启动 FileRing，按提示授予所需权限

> 应用已通过 Apple 签名与公证，无需处理任何安全警告。

### 从源代码构建

适合希望修改或参与贡献的开发者：

```bash
git clone https://github.com/Cosmostima/FileRing.git
cd FileRing
open FileRing.xcodeproj
```

在 Xcode 的 **Signing & Capabilities** 中选择你的 Team，然后按 **⌘R** 构建运行。

## 使用方法

### 初次引导

当您第一次打开此软件时，会有一个引导页面帮助您进行初始化。

您可以：
1. **授权文件夹**
   - 选择常用的文件夹或添加自定义目录
   - 在系统提示时授予访问权限
2. **测试触发器** - 按住 `⌃ Control + X` 打开面板

### 自定义快捷键

**快捷键要求**

您必须将一个或多个修饰键与一个常规按键组合：
- **修饰键**：⌘ Command、⌃ Control、⌥ Option、⇧ Shift（可组合使用）
- **常规按键**：A-Z、0-9、空格或其他标准按键
- **示例**：`⌃X`、`⌥Space`、`⌘⇧D`

**注意**：不支持仅使用修饰键的快捷方式（例如单独按 ⌥ Option）。

**更改快捷键：**
1. 从菜单栏打开“设置”
2. 点击“快捷键设置”下的快捷键输入框
3. 按下您期望的组合键（修饰键 + 按键）
4. 快捷键将立即更新

### 管理文件夹访问

**设置 → 文件夹权限**

**授权文件夹：**
1. 快速授权常用文件夹
2. 点击“添加”以选择自定义目录
3. 在系统对话框中授予访问权限

**撤销访问：**
1. 在已授权列表中找到该文件夹
2. 点击文件夹名称旁边的“X”按钮
3. 该文件夹及其中的文件将不再出现在 FileRing 中

**注意**：FileRing 仅查询已授权文件夹内的文件。

### 偏好设置

**设置 → 显示**

- **每个部分的项目数**：可从 4 调整到 10 个项目（默认：6）

**设置 → 过滤设置**

- **排除的文件夹**：管理要从搜索结果中排除的文件夹（例如 `node_modules`、`__pycache__`）
- **排除的扩展名**：管理要排除的文件扩展名（例如 `.tmp`、`.log`、`.cache`）

点击“管理”可添加或删除项目。更改会立即生效。

- **在搜索中包含应用程序**：将您的应用程序视作作为文件显示在“最近使用”和“最常使用”部分。文件将始终至少占结果的 50%，且应用的权重为 0.5 倍，以确保文件优先。

**设置 → 应用行为**

- **开机启动**：登录 Mac 时自动启动 FileRing
- **隐藏程序坞图标**：使 FileRing 仅在菜单栏显示（需要重启）
- **隐藏状态栏图标**：隐藏状态栏图标（立即生效）。应用仍可通过快捷键或程序坞图标访问

**设置 → 重置**

- **重置**：删除所有文件夹授权并重新显示引导屏幕

## 灵感来源

FileRing 的交互模型受到 [Loop](https://github.com/MrKai77/Loop) 的启发，这是一个优雅的 macOS 窗口管理工具。



## 许可证

MIT License - 详见 [LICENSE](LICENSE)

---

**使用 Swift 和 SwiftUI 为 macOS 打造**
