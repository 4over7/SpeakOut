# SpeakOut 音频输入设备管理重构分析 (2026-03-13)

## 问题清单

### P0 - 必须修复

1. **`set_input_device()` 修改了 macOS 全局系统默认设备** — 影响所有应用。应该只设 `preferredDeviceUID`，由 AudioQueue 使用
2. **`get_preferred_device_uid()` 永远不返回空字符串** — fallback 到 builtInDeviceUID，导致 `isUsingSystemDefault` 失效
3. **设备 UID 三份存储互相冲突** — C 层 preferredDeviceUID / SharedPreferences / AudioDeviceService 内存

### P1 - 重要

4. **选"系统默认"后没恢复被改过的系统默认设备**
5. **蓝牙自动切换覆盖用户手动选择**
6. **`start_audio_recording()` 设备失败清 C 层但 SharedPreferences 没同步**
7. **`autoManageEnabled` 不持久化**

### P2 - 改善

8. **热插拔只监听默认设备变化** — 应增加 `kAudioHardwarePropertyDevices` 监听
9. **AudioQueue 每次录音都重建** — 设备状态不保证连续
10. **`_handleBluetoothMicDetected` 命名和逻辑不匹配** — 非蓝牙设备拔掉也走这个方法

## 重构方案

### 原则：ConfigService 为单一真实来源

```
ConfigService (SharedPreferences)
  └── audioInputDeviceId: String? (null = 系统默认)
       │
       ├── init() 时 → 设 C 层 preferredDeviceUID
       ├── UI 切换时 → 设 C 层 preferredDeviceUID
       └── start_audio_recording() → 用 preferredDeviceUID 设 AudioQueue
```

### C 层改动
- `set_input_device()`: 删除 AudioObjectSetPropertyData（不改系统默认），只设 preferredDeviceUID
- `get_preferred_device_uid()`: preferred 为空就返回空字符串，不 fallback
- `start_audio_recording()`: 已有 kAudioQueueProperty_CurrentDevice 逻辑，保持
- 新增: 监听 kAudioHardwarePropertyDevices（设备列表变化）

### Dart 层改动
- `AudioDeviceService.isUsingSystemDefault`: 改为查 ConfigService，不依赖 C 层
- `CoreEngine.init()`: 蓝牙检测逻辑调整 — 如果用户手动选了蓝牙设备，不自动切换
- `ConfigService`: 新增 autoManageEnabled 持久化
- `start_audio_recording()` 失败时: 通知 Dart 层清除 ConfigService 中的设备偏好
