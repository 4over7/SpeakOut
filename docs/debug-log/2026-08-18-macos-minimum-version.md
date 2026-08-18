# macOS 最低版本一致性（2026-08-18）

## 第 1 轮：App 声明的最低版本低于随包依赖

### 现象

Debug 构建成功，但链接器警告工程为 macOS 11.0、`libonnxruntime.1.23.2.dylib` 为 macOS 13.4。旧产物的 `LSMinimumSystemVersion` 确实是 11.0，`otool -l` 显示 ONNX Runtime 的 `minos` 是 13.4；README 又只写 macOS 13+。

### 假设·判断原因

App 的真实下限由所有随包 Mach-O 中要求最高的那个决定。继续声明 11.0 不会让依赖兼容旧系统，只会把加载失败推迟到用户机器；README 的 13+ 还会误导 13.0–13.3 用户。为三个小版本自行维护第三方运行库构建会扩大供应链和发布验证面，当前最小修法是如实统一到 13.4。

### 措施

把 Runner 三种配置、Podfile 与 Pods post-install target 统一为 13.4；README 中英文和平台徽章同步为 macOS 13.4+。在 `macos/Runner/AGENTS.md` 只记录“最低版本由最严格随包依赖决定”的主干不变量。

### 验证结果

Debug 与 Release 均构建成功，原链接警告消失。两个产物的 Info.plist 都是 `LSMinimumSystemVersion=13.4`；主可执行文件和 ONNX Runtime 的 x86_64/arm64 load command 均为 `minos 13.4`。

### 复盘

“构建成功”不能证明旧系统可运行，链接警告已经给出相反证据。最低版本必须从最终产物反查，不能只看 Xcode 输入配置或 README。

## 第 2 轮：修复后检查是否还有漂移真源

### 现象

全文搜索仍命中 CHANGELOG 的 macOS 11.0 和一篇 Rejected ADR 原始提案中的 macOS 13+。

### 假设·判断原因

两处分别是历史版本记录和明确保留的已否决方案，不参与当前构建或用户安装判断。改写它们反而会篡改当时事实；需要清零的是当前生效配置和当前用户文档，而不是所有历史字符串。

### 措施

保留历史文档原文，只核对 Podfile、Xcode project、Info.plist 展开值、README 和 L2 Agent 文档。没有新增重复真源或额外兼容分支。

### 验证结果

当前生效位置全部一致为 13.4；`flutter analyze` 无问题，完整非下载测试 852 通过、10 个大模型下载用例按环境门槛跳过。修复后复审未发现 P2+。

### 复盘

同源残留清零要区分“当前真源”和“历史证据”。机械替换所有版本文本既不能提高兼容性，还会损坏项目决策史。
