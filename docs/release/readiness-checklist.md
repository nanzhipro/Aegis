# Aegis Release Readiness Checklist

本清单用于最终发布前收口。只有当全部项目都完成，才允许对外宣布 release ready。

## 自动化门禁

- [ ] `./scripts/test.sh` 在目标提交上通过。
- [ ] `.github/workflows/ci.yml` 最近一次主分支运行通过。
- [ ] `.github/workflows/release.yml` 最近一次目标 tag 运行通过。
- [ ] release artifact 已生成并可下载。

## 签名与公证

- [ ] 导出的 `.app` 已使用 `Developer ID Application` 签名。
- [ ] hardened runtime 已启用。
- [ ] entitlements 已嵌入且可审计。
- [ ] `.dmg` 已完成 notarization。
- [ ] `.dmg` 已 stapled。
- [ ] `./scripts/validate-release.sh` 对最终分发产物通过。

## 特权 smoke

- [ ] 在本地 macOS 14 及以上完整测试环境执行了 privileged smoke。
- [ ] 已填写具体 smoke 记录文件。
- [ ] System Extension 安装和批准链路通过。
- [ ] Full Disk Access 引导链路通过。
- [ ] Agent 原生提示链路通过。
- [ ] remembered rule 与默认回退行为通过。

## 文档与留痕

- [ ] 本次 release 对应的 runbook 步骤可复现。
- [ ] smoke 结果、截图和异常说明已留痕。
- [ ] 若存在 caveat，已记录风险和补救动作。
- [ ] 对外发布说明已准备完成。

## 结论

- [ ] 本次发布结论为 `Go`。

若任一项未完成，则本次 release 仍处于未准备状态。
