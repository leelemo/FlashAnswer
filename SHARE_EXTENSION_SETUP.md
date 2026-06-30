# Share Extension 配置指南

## 已创建的文件

```
FlashAnswer-v1.5/
├── FlashAnswer/
│   ├── Services/
│   │   └── SharedStorage.swift          ← 新增：App Group 路径
├── ShareExtension/                       ← 新增目录
│   ├── ShareViewController.swift         ← 截图→OCR→匹配→通知
│   ├── QuestionBank.swift                ← Extension 专用匹配引擎（自包含）
│   ├── Info.plist                        ← Extension 配置
│   └── ShareExtension.entitlements       ← App Group 权限
├── FlashAnswer/
│   ├── FlashAnswer.entitlements          ← 新增：主 App App Group 权限
│   └── Models/
│       └── QuestionBank.swift            ← 已修改：保存路径改为 App Group
```

---

## Xcode 操作步骤

### 第一步：打开项目
用 Xcode 打开 `FlashAnswer.xcodeproj`

### 第二步：注册 App Group（开发者网站）
1. 登录 https://developer.apple.com
2. Certificates, Identifiers & Profiles → Identifiers
3. 找到你的 App ID → Edit → App Groups → 勾选并注册
   - Description: `FlashAnswer Shared`
   - Identifier: `group.com.leelemo.flashanswer`（与 `SharedStorage.swift` 一致）
4. 重新下载/更新 Provisioning Profile

### 第三步：添加 Share Extension Target
1. **File → New → Target**
2. 搜索 `Share` → 选择 **Share Extension**
3. 配置：
   - Product Name: `ShareExtension`
   - Bundle Identifier: `com.leelemo.FlashAnswer.ShareExtension`（主 App Bundle ID + .ShareExtension）
   - Language: **Swift**
   - Project: `FlashAnswer`
   - ❌ 取消勾选 "Include UI Tests"
4. 点击 **Finish**
5. Xcode 会创建一个默认的 `ShareViewController.swift`，**删除它**（用你的版本替换）

### 第四步：添加源文件到 Share Extension Target
在 Xcode 项目导航器中：

1. 右键 `ShareExtension` 组 → **Add Files to "FlashAnswer"...**
2. 添加以下文件，并在弹窗中勾选 **ShareExtension** target：
   - `ShareExtension/ShareViewController.swift`
   - `ShareExtension/QuestionBank.swift`
   - `FlashAnswer/Services/SharedStorage.swift`（同时勾选 FlashAnswer 和 ShareExtension 两个 target）

3. 确认 `ShareExtension/Info.plist` 已被加入 ShareExtension target

### 第五步：配置 Share Extension Info.plist
1. 点击 ShareExtension target → **Info**
2. 确认 `NSExtension` 配置与 `ShareExtension/Info.plist` 内容一致
   - 或直接把 `ShareExtension/Info.plist` 的内容粘贴进去

### 第六步：配置 App Group 权限
**主 App：**
1. 选择 FlashAnswer target → **Signing & Capabilities**
2. 点击 **+ Capability** → 搜索 **App Groups** → 添加
3. 勾选 `group.com.leelemo.flashanswer`
4. 设置 **Code Signing Entitlements** 为 `FlashAnswer/FlashAnswer.entitlements`

**Share Extension：**
1. 选择 ShareExtension target → **Signing & Capabilities**
2. 点击 **+ Capability** → 搜索 **App Groups** → 添加
3. 勾选 `group.com.leelemo.flashanswer`
4. 设置 **Code Signing Entitlements** 为 `ShareExtension/ShareExtension.entitlements`

### 第七步：Bundle ID 确认
确认以下 Bundle ID 正确（在 Target → General 中查看）：
- 主 App: `com.leelemo.FlashAnswer`
- Share Extension: `com.leelemo.FlashAnswer.ShareExtension`

如果不同，修改 `SharedStorage.swift` 中的 `appGroupIdentifier` 为实际注册的 ID。

---

## 测试流程

1. **Build & Run 主 App** → 导入题库（Excel）
2. **退出到主屏幕** → 打开任意 APP（或截一张有文字的图）
3. **截图**（电源键 + 音量+）
4. 点击左下角截图缩略图 → 点击 **分享** 按钮
5. 在分享列表中找到 **FlashAnswer**
6. 等待 1-2 秒 → 收到通知显示匹配结果

---

## 常见问题

**Q: 分享列表里找不到 FlashAnswer**
→ 确认 Share Extension target 已正确添加，Bundle ID 格式正确，且已运行过主 App

**Q: Extension 提示"未能匹配到题目"**
→ 确认主 App 已导入题库，且 App Group 配置正确（两个 target 勾选了同一个 Group）

**Q: OCR 识别不准**
→ Vision 框架对清晰截图效果较好，模糊或反光会降低准确率。可在 `ShareViewController.swift` 中将 `recognitionLevel` 改为 `.accurate`

**Q: 通知没有弹出**
→ 确认主 App 已授权通知权限（Share Extension 会自行请求授权）
