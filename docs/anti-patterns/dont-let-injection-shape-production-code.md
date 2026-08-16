# 别让测试注入的需求渗进生产逻辑

## 真实事件

**2026-08-15，`CloudAccountService._saveCredentials`。** 为了构造「凭证写到一半失败」的孤儿场景，我在生产循环里塞了一个 `first` 标志和一个额外分支：

```dart
// ❌ 曾经的写法
final prefs = _prefs ??= await SharedPreferences.getInstance();
var first = true;
for (final entry in account.credentials.entries) {
  if (!first) await _requirePrefs(credentials: true); // 只为造失败点
  first = false;
  await prefs.setString('cloud_cred_${account.id}_${entry.key}', entry.value);
}
```

`first` 在生产上毫无意义 —— 它唯一的作用是让测试能在「写了第一个字段之后」抛错。同一批还把 `_requirePrefs` 加了个 `credentials` 参数，也只为分流注入。

改成外部 hook 后，生产代码回到本来的样子，注入能力一点没少（逐字摘自
`lib/services/cloud_account_service.dart` 的 `_saveCredentials`，
逐 key 聚合错误是这个方法本来就有的语义，不是为注入加的）：

```dart
// ✅ 现在
final prefs = await _requirePrefs();
final failed = <String>[];
Object? firstError;
for (final entry in account.credentials.entries) {
  try {
    await _beforeCredentialWrite?.call(); // 生产恒为 null，一次判空
    await prefs.setString(
        'cloud_cred_${account.id}_${entry.key}', entry.value);
  } catch (e) {
    failed.add(entry.key);
    firstError ??= e;
  }
}
if (failed.isNotEmpty) {
  throw StateError('凭证写入失败: ${failed.join(", ")} (首个错误: $firstError)');
}
```

注意 hook 抛出后**不会中断循环** —— 后面的 key 照写，失败最后聚合抛出。
写注入测试时时序模型要按这个来，按「抛了就退出」设计补偿断言会验错东西。

## 为什么会发生

需要构造的失败场景越刁钻（「第 2 个 key 失败、前 1 个已落盘」），越容易顺手在实现里加分支 —— 那是当下最短的路径。代价要等很久才显现：后来的人读到 `first` 这个变量，会花时间琢磨它防的是什么业务问题，而它根本不防任何业务问题。

## 如何避免

**注入点做成「默认无副作用的外部钩子」，而不是实现里的条件分支。**

- `static Future<void> Function()? debugBeforeCredentialWrite;` —— 生产恒为 `null`，代价是一次判空
- 钩子放在**循环内**才能表达「第 N 次失败」，放在方法开头只能表达「整个方法失败」，那是两种不同的故障，结论会相反（见 [[dont-trust-green-tests-without-probing]]）
- 用 `@visibleForTesting` 标注；analyzer 会对生产误用给出提示

判断标准很简单：**把所有测试删掉，这段代码还需要存在吗？** 不需要，就说明它不该在实现里。

## 相关

- [[dont-trust-green-tests-without-probing]] —— 注入形态失真会让断言验错东西
