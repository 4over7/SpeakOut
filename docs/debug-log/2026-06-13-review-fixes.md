# Review 修复执行日志（fix_tracking_2026_06_13.md）

目标：消灭 `docs/review/fix_tracking_2026_06_13.md` 里的所有问题。
原则（用户明确）：客观评价 + 把事做对，不为字面"清零"强行改；提错/不存在的问题明确不改并写明理由。

---

## 第 1 轮 — 自更新安全加固（F 组）

### 现象
self_update_review 报告 F1（先删旧 app 再复制，复制失败丢 app）、F2（无签名/TeamID/BundleID 校验 + `hdiutil -noverify`）、F4（下载无超时）、F5（About 页无安装完成态）、F6（main.dart 缺空路径守卫）、F7（app 名错配 relaunch 失败）等。已逐条核实属实（F7 为当前不触发的脆弱性）。

### 假设 / 判断原因
helper 脚本是 best-effort 替换：`rm -rf 旧 app` → `cp 新 app`，无任何身份校验、无回滚。改成"复制到 staging → 校验 → 原子 swap → 失败回滚"可同时根治 F1/F2/F7。

### 措施
- `lib/services/update_service.dart` `_writeHelperScript` 重写：
  - F2：挂载去掉 `-noverify`；新增 `verify_app()` 校验 `codesign --verify --deep --strict` + `TeamIdentifier==UB9D55S724` + `CFBundleIdentifier==com.speakout.speakout`；对 DMG 内 app 和复制后 staging 双重校验。
  - F1：`cp -R` 到 `$APP_NAME.new`（不动旧 app）→ 校验 → 旧 app `mv` 到 `.backup` → staging `mv` 成正式名 → relaunch；promote 失败回滚 backup。
  - F7：staging 最终 `mv` 成当前 `appName`，DMG 内 app 叫什么都归一，relaunch 永远一致。
  - F3（脚本侧）：开头 `[ ! -w "$INSTALL_DIR" ]` 不可写直接 open DMG。
  - F4：`client.send().timeout(30s)`。
- `lib/main.dart` `_handleInstallAndRestart`：加 `if (scriptPath.isEmpty) return;`（F6）。
- `lib/ui/settings/tabs/about_tab.dart`：监听 `UpdateService.stateChanges`，更新按钮状态化（readyToInstall→"安装并重启"，经 `AppService().engine.nativeInput` 安装），下载完闭环（F5）。
- `test/services/update_service_test.dart`：新增 helper 脚本安全保护断言（签名校验/原子安装/不先删旧 app）（F9）。

### 验证结果
- `flutter analyze` 改动 3 文件：No issues found。
- `flutter test test/services/update_service_test.dart`：10/10 通过（含新增 1 条）。
- 一次失败修正：脚本注释里写了"去掉 -noverify"字面，导致 `isNot(contains('-noverify'))` 断言失败 → 改注释措辞。

### 复盘
- F1/F2/F4/F5/F6/F7/F9 已落地并验证。
- F3 文案：脚本侧已加可写兜底（失败自动 open DMG，体验闭环），故 UI 文案"安装并重启"维持不改——过度悲观文案反而吓用户。
- F8（canAutoUpdate 改名 canDownloadInApp）：纯 cosmetic，会牵动多处调用点，价值低，不强行改。
- 未触及 native dylib（仅改 Dart 生成的脚本字符串），无需重编译 libnative_input.dylib。

---

## 第 2 轮 — Dart quick wins（C3 / D3 / D4 / D5）

### 现象
- C3：关闭 verbose 时 `applyVerboseLogging` 不调 dispose，sink+500ms timer 泄漏到退出。
- D3：`_ensureAllProvidersExist` 同步函数里裸调 `addAccount`（Future），持久化 fire-and-forget。
- D4：`resolveLlmApiKey` 硬编码 `credentials['api_key']`，讯飞（api_password）被误判未配置（仅 superpower_tab 一处 UI 提示）。
- D5：developer_page 导入/导出 await 后用 context，analyzer 报 2 个 info（unrelated mounted check）。

### 措施
- `app_service.dart`：`enabled==false` 时 `await AppLog.dispose()`。
- `cloud_accounts_page.dart`：`_refreshAccounts`/`_ensureAllProvidersExist` 改 `Future<void>` 并 await，加 `if(!mounted)return`。
- `settings_shared.dart`：`resolveLlmApiKey` 改用 `CloudProviders.getById(account.providerId)?.llmApiKeyField`（import cloud_providers）。
- `developer_page.dart`：导入/导出 onPressed 在 await 前 `final messenger = ScaffoldMessenger.of(context)`，去掉 `context.mounted` 包裹，setState 前 `if(!mounted)return`。

### 验证结果
- `flutter analyze`：No issues found（D5 两个 info 消除）。
- `flutter test test/services/`：350/350 通过，无回归。

### 复盘
- 都是确定性小修，无意外。D4 真实影响本就小（只一处 UI 提示），但修了消除不一致。

