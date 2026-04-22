# Aegis Privileged Smoke Checklist

本清单用于 phase-7 的受控 macOS 14 及以上特权 smoke。执行人需要在 release workflow 完成后，在 self-hosted `aegis-privileged` runner 上手动完成以下检查。

## 环境确认

- [ ] 当前机器是受控 macOS 14 及以上版本。
- [ ] 当前 workflow 为 `.github/workflows/privileged-smoke.yml`。
- [ ] 已下载待验证的 `AegisApp.dmg`。
- [ ] 已准备 workflow 生成的 `build/release/privileged-smoke-record.md` 或回退模板用于留痕。

## 安装与签名验证

- [ ] `./scripts/validate-release.sh` 对下载得到的 `.app` 或 `.dmg` 通过。
- [ ] `spctl -a -vv -t open` 验证 DMG 通过。
- [ ] `xcrun stapler validate` 验证 DMG 通过。
- [ ] 将 `AegisApp.app` 从 DMG 拖入 `/Applications`。

## Onboarding 与系统授权

- [ ] 首次启动显示 onboarding，而不是直接进入 dashboard。
- [ ] onboarding 文案与步骤完整可读。
- [ ] 宿主 App 能触发 `System Extension` 安装流程。
- [ ] 在系统设置中完成 `System Extension` 用户批准。
- [ ] App 对 `Full Disk Access` 只做引导，不尝试静默授权。
- [ ] 按引导完成 `Full Disk Access` 配置。

## Agent 与提示链路

- [ ] Login Item 注册成功。
- [ ] Agent 可在登录会话中启动。
- [ ] 受保护目录触发访问时，Agent 能弹出原生确认。
- [ ] 5 秒内 Allow / Deny 都能形成正确结果。
- [ ] 勾选 remember choice 后，后续同类请求命中 remembered rule。

## 状态与回退

- [ ] Dashboard 能显示 `System Extension`、`Login Item`、`Policy`、`Protection Readiness` 状态。
- [ ] 设置页中的受保护目录与默认行为能正常显示。
- [ ] 默认超时决策在无响应时生效。
- [ ] 清理 remembered decisions 后，命中缓存的请求重新回到提示链路。

## 结果归档

- [ ] 将结果写入具体 smoke 记录文件。
- [ ] 若前置条件失败或无法进入人工 smoke，写入 blocker 记录文件并标记 `No-Go`。
- [ ] 将截图、日志和异常说明附到 workflow run 或关联 issue。
- [ ] 在最终发布前检查清单中同步本次结论。
