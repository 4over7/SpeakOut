# 蓝牙设备切换导致键盘卡顿修复

**日期**：2026-03-05
**影响版本**：1.4.0 及以前
**Commit**：8c2e902

---

## 问题现象

用户反映：蓝牙耳机连接或断开后，SpeakOut 的快捷键有时会失去响应，持续 1-5 分钟，之后自行恢复。

---

## 根因分析

### 架构背景

CGEventTap（键盘监听）和 Dart 代码共用同一个主线程：

```
主线程 (Main Thread)
├── CFRunLoop
│   └── CGEventTap ← 键盘事件在这里被捕获
└── Dart 事件队列（也运行在主线程）
```

RunLoop 是串行的——Dart 代码占用主线程期间，CGEventTap 的回调无法执行，键盘事件全部堆积在等待队列中。

### 事故链路

```
蓝牙设备连接/断开
    ↓
deviceChangeListenerProc（C 层，AudioHAL 后台线程）
    ↓ NativeCallable.listener 异步投递到 Dart 队列
    ↓
_handleDeviceChange（Dart，主线程执行）
    ↓
refreshDevices()
    ↓ FFI 同步调用 get_audio_input_devices()
    ↓
遍历所有音频设备，对每个设备调用：
  isBluetoothDevice()   → AudioObjectGetPropertyData(TransportType)
  isBuiltInDevice()     → AudioObjectGetPropertyData(...)
  getDeviceSampleRate() → AudioObjectGetPropertyData(NominalSampleRate)
    ↓
⚠️ 蓝牙设备处于协商过渡状态，AudioObject API 等待蓝牙栈响应
   → 主线程阻塞数分钟
    ↓
CGEventTap 无法触发 → 键盘失去响应
```

### 日志证据

从 `~/Downloads/speakout_native.log` 中可以清晰看到：

```
10:46:37  最后一个按键事件
10:47:09  AudioDevice: Default input device changed   ← 蓝牙触发
10:51:54  下一个按键事件（约 4 分 45 秒空窗）
```

---

## 修复方案

### 核心思路

设备变化时，我们实际只关心一件事：**当前正在使用的设备还在不在**。不需要重建整个设备列表。

- 设备列表（`refreshDevices()`）是给用户手动选设备用的，用户打开设置页时再懒加载即可
- 对"当前设备是否可用"的判断，用 `kAudioHardwarePropertyTranslateUIDToDevice` 做 O(1) 直接查询，不枚举、不触碰蓝牙设备属性

### 新增 C 函数

```c
// is_device_available(uid)
// 用 kAudioHardwarePropertyTranslateUIDToDevice 做 O(1) UID 查找
// 不枚举设备列表，不查询设备属性，蓝牙协商期间调用安全
int is_device_available(const char *deviceUID);
```

### 修改后的 Dart 逻辑

```
设备变化事件
    ↓
清空设备列表缓存（不查询）
发出事件通知
    ↓
isDeviceAvailable(preferredDeviceUID)   ← O(1)，不阻塞
    ├── 在 → 什么都不做，继续用当前设备
    └── 不在 → 切回内置麦，通知用户

用户打开设置页
    ↓
懒加载完整设备列表（此时蓝牙早已稳定）
```

### 修改文件

| 文件 | 改动 |
|------|------|
| `native_lib/native_input.m` | 新增 `is_device_available()` |
| `lib/ffi/native_input_base.dart` | 新增 FFI 类型定义和抽象方法 |
| `lib/ffi/native_input_ffi.dart` | 新增 FFI 绑定和实现 |
| `lib/services/audio_device_service.dart` | 重写 `_handleDeviceChange()`，改为惰性刷新 |

---

## 修复前后对比

| 场景 | 修复前 | 修复后 |
|------|--------|--------|
| 蓝牙耳机连接时键盘响应 | 卡顿 1-5 分钟 | 正常，不受影响 |
| 设备变化时主线程 | 被阻塞 | 不阻塞 |
| 设备列表刷新时机 | 每次设备变化立即刷新 | 用户打开设置页时懒加载 |
| 当前设备可用性检查 | 枚举所有设备（慢） | O(1) UID 查找（快） |
| 自动切回内置麦触发时机 | 设备变化时立即 | 当前设备消失时才触发 |

---

## 附：新增卸载脚本

同期新增 `scripts/uninstall.sh`，用于在另一台 Mac 上彻底卸载并重装：

```bash
bash scripts/uninstall.sh
# 完成后双击 DMG 重装
```

清理范围：`.app`、`Preferences`、`Application Support`（含模型）、`Caches`、Keychain 条目。
