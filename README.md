<div align="center">

<img src="Assets/FileRingIcon.png" alt="FileRing Icon" width="200"/>

<br/>

# FileRing

Quick access to your files and folders with a simple swipe.

![Platform](https://img.shields.io/badge/platform-macOS%2013.0+-lightgrey)
![Swift](https://img.shields.io/badge/swift-5.0+-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

English | [简体中文](README_CN.md)

</div>

## Overview

FileRing provides a keyboard-driven circular launcher that displays your recently and frequently used files and folders. Press and hold a customizable hotkey to bring up the radial panel centered at your cursor, move your mouse to select an item, and release the hotkey to open it. The interface organizes items into six distinct sections based on usage patterns.

**Basic workflow:**
1. Press and hold the trigger hotkey (default: `⌃ Control + X`)
2. A circular panel appears with six sections showing your files and folders
3. Move your mouse over the desired section and item
4. Release the hotkey to perform the action (open file/folder, copy file, or copy path)
5. Move cursor to blank area to cancel

![OverView Example](Assets/OverView.gif)

## Features

### 1. File Categorizes

FileRing categorizes your files and folders into six sections using macOS Spotlight:

- **Files - Recently Opened** 🕐
- **Files - Recently Saved** 💾
- **Files - Frequently Used (in 3 days)** ⭐
- **Folders - Recently Opened** 🕐
- **Folders - Recently Saved** 💾
- **Folders - Frequently Used (in 3 days)** ⭐

Each section displays 4-10 items (configurable, default: 6) based on your actual usage patterns, with no manual bookmarking required.

<div><video src="https://github.com/user-attachments/assets/3e1b0f8e-92a8-483e-a4a1-0ba2f3b20bcc" controls></video></div>

### 2. Actions

Hover over any item to reveal quick actions:

### Open
Launch files in their default application or open folders in Finder

<div><video src="https://github.com/user-attachments/assets/054b5c50-542b-401d-8793-0bae187ab55e" controls></video></div>


<div><video src="https://github.com/user-attachments/assets/c7a1d5e8-56d5-4cb1-9ae0-1c0feb6209ef" controls></video></div>


### Copy File
Copy the entire file to clipboard for pasting elsewhere (files only)

<div><video src="https://github.com/user-attachments/assets/56ea54bd-bc22-45a0-a41f-9b537adabfed" controls></video></div>

### Copy Path
Copy the absolute file/folder path as text

<div><video src="https://github.com/user-attachments/assets/84b4d13c-e214-4dca-b814-6c9b1461ac24" controls></video></div>

### 3. Folder Authorization

FileRing only accesses folders you explicitly authorize. The app has read-only access to your selected directories and uses macOS security-scoped bookmarks for safe file access.

### 4. Menu Bar App

FileRing runs as a lightweight menu bar application. Both the dock icon and status bar icon can be customized in Settings. Click the dock icon (when visible) to quickly open Settings.
<div align="center">
<img src="Assets/MenuBar.png" alt="MenuBar Example" width="50%"/>
</div>

## Installation

### Requirements

- macOS 13.0 or later
- Apple Silicon or Intel processor

### Option 1: Download Pre-built Release (Not Recommended)

1. Download the latest release from the Releases page
2. Extract and move `FileRing.app` to Applications folder
3. Right-click and select "Open" on first launch (unsigned application)
4. Grant necessary permissions when prompted


### Option 1: Download Pre-built Release (Not Recommended)

**⚠️ Important:**

Due to the lack of an Apple Developer account, the pre-built app is **not notarized or signed**. macOS will show security warnings. **Building from source (Option 2) is strongly recommended.**

**If you still want to use the pre-built version:**

1. Download the latest release from the [Releases](https://github.com/Cosmostima/FileRing/releases) page
2. Extract and move `FileRing.app` to Applications folder
3. Remove quarantine attribute:
```bash
   xattr -cr /Applications/FileRing.app
```
4. **Alternative**: Right-click → "Open" → Click "Open" in the dialog
5. **If still blocked**: System Settings → Privacy & Security → "Open Anyway"
6. Grant necessary permissions when prompted

### Option 2: Build from Source (Recommended)

Building from source allows you to sign the app with your own Apple ID, avoiding system security warnings.


#### GUI Method (Xcode)

```bash
# Clone the repository
git clone https://github.com/Cosmostima/FileRing.git
cd FileRing

# Open in Xcode
open FileRing.xcodeproj
```

**In Xcode:**
1. Select the FileRing project in the navigator
2. Choose the FileRing target under TARGETS
3. Go to "Signing & Capabilities" tab
4. Enable "Automatically manage signing"
5. Select your Apple ID in the Team dropdown (add account if needed)
6. Click Run (⌘R) to build and launch

**To export a standalone app:**
1. Product → Archive
2. Click "Distribute App"
3. Choose "Copy App" (maybe in custom options)
4. Save to desired location

#### Command Line Method

```bash
# Clone the repository
git clone https://github.com/Cosmostima/FileRing.git
cd FileRing

# Build the application
xcodebuild -project FileRing.xcodeproj -scheme FileRing -configuration Release -derivedDataPath build clean build

# The FileRing.app will be located in the build/Build/Products/Release/ directory.
# You can then copy it to your /Applications folder.
cp -r build/Build/Products/Release/FileRing.app /Applications/
open /Applications/FileRing.app
```

**Note:** Command line builds require code signing to be configured in Xcode at least once. Open the project in Xcode and set up your Apple ID under "Signing & Capabilities" before using `xcodebuild`.

## Usage

### Initial Setup

When you first open the app, an onboarding guide will help you get started.

You can:
1. **Authorize Folders**
   - Select common folders or add custom directories
   - Grant access when system prompts appear
2. **Test the Trigger** - Press and hold `⌃ Control + X` to open the panel

### Customizing the Hotkey

**Hotkey Requirements**

You must combine one or more modifier keys with a regular key:
- **Modifiers**: ⌘ Command, ⌃ Control, ⌥ Option, ⇧ Shift (can use multiple)
- **Regular Keys**: A-Z, 0-9, Space, or other standard keys
- **Examples**: `⌃X`, `⌥Space`, `⌘⇧D`

**Note**: Modifier-only shortcuts (like just ⌥ Option alone) are not supported.

**To change the hotkey:**
1. Open Settings from the menubar
2. Click the hotkey field under "Hotkey Settings"
3. Press your desired key combination (modifier + key)
4. The hotkey updates immediately

### Managing Folder Access

**Settings → Folder Permissions**

**To authorize a folder:**
1. Quickly authorize common folders
2. Click "Add" to select custom directories
3. Grant access in the system dialog

**To revoke access:**
1. Find the folder in the authorized list
2. Click the "X" button next to the folder name
3. The folder and its files will no longer appear in FileRing

**Note**: FileRing only queries files within authorized folders.

### Preferences

**Settings → Display**

- **Items per Section**: Adjust from 4 to 10 items (default: 6)

**Settings → Filter Settings**

- **Excluded Folders**: Manage folders to exclude from search results (e.g., `node_modules`, `__pycache__`)
- **Excluded Extensions**: Manage file extensions to exclude (e.g., `.tmp`, `.log`, `.cache`)

Click "Manage" to add or remove items. Changes take effect immediately.

- **Include Applications in Search**: Display your app as a file in the "Recently Used" and "Most Used" sections. Files will always make up at least 50% of the results, and app usage counts are weighted at 0.5× to keep files prioritized.



**Settings → App Behavior**

- **Launch at Startup**: Automatically start FileRing when you log in to your Mac
- **Hide Dock Icon**: Make FileRing menubar-only (requires restart)
- **Hide Status Bar Icon**: Hide the status bar icon (takes effect immediately). App remains accessible via hotkey or dock icon

**Settings → Reset**

- **Reset**: Delete all folder authorizations and show the onboarding screen again

## Inspiration

FileRing's interaction model is inspired by [Loop](https://github.com/MrKai77/Loop), an elegant window management tool for macOS.

## License

MIT License - See [LICENSE](LICENSE) for details

---

**Made with Swift and SwiftUI for macOS**
