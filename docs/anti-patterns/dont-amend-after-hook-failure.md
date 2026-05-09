# 不要在 pre-commit hook 失败后用 `--amend` 修

## 真实事件

**Claude Code 全局规则**，本项目同样适用。

场景：`git commit -m "..."` 触发 pre-commit hook（如 lint / format / typecheck）。Hook 失败 → commit **没创建**。

第一直觉是修问题然后 `git commit --amend` 修——**错的**。因为「commit 没创建」意味着：
- `--amend` 修的是**前一个 commit**（之前已经存在的某次提交）
- 不是修这次失败的提交（它根本不存在）

后果：把无关的修复混进了上一个历史 commit，破坏了之前 commit 的语义内聚性，最坏情况覆盖了别人的代码。

## 为什么会发生

pre-commit hook 失败的现象（`commit aborted`）和 commit 成功后被发现有问题（编辑后 amend）非常像。如果 agent 没有精确区分这两种状态，会下意识 `--amend`。

特别危险的场景：
- pre-commit hook 自动 fix 了部分文件（如 prettier 自动改格式），停下让你 review/stage
- 这时如果 `git status` 看到"已修改但 unstaged"的文件，**仍然是 hook 在中间状态**
- 这种状态下 `--amend` 100% 修错对象

## 如何避免

铁律：**hook 失败 = 没 commit。修问题 → 重新 stage → 创建新 commit（`git commit`，不是 `--amend`）**。

判断当前是哪种状态：

```bash
git log -1   # 看最近一次 commit
git status   # 看 staged / unstaged
```

- 如果 `git log -1` 显示的是**预期之外的旧 commit** → 你的 commit 还没创建 → 用 `git commit`，不是 amend
- 如果 `git log -1` 显示的是**刚刚的修改** → commit 已创建 → 这时才能用 amend（如果用户授权）

## 修复模式

如果已经误用 `--amend` 把无关修改混进历史 commit：

1. **没 push**：`git reset --soft HEAD^` 回到混乱前的状态，重新拆 commit
2. **已 push 到自己分支**：仅在自己分支安全的前提下 `git push --force-with-lease`，且必须告知用户
3. **已 push 到 main / 多人协作分支**：**不要 force push**——和用户沟通后选择「revert + 新 commit 重建」

## 相关

- Claude Code Bash tool 文档「CRITICAL: Always create NEW commits rather than amending」
- 全局 CLAUDE.md / system prompt 已经把这条钉死
