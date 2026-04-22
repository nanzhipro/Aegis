# Phase 6: 签名、公证、CI 与发布链路

## 阶段定位

这个阶段不再扩展产品能力，而是把已有成果接到可复用、可审计、可自动化的构建、签名、公证和发布流程上。

## 必带上下文

- `plan/common.md`
- Phase 5 已完成

## 阶段目标

- 实现脚本
- 实现 GitHub Actions
- 完成发布验证

## 实施范围

- 落地 `scripts/bootstrap.sh`、`scripts/test.sh`、`scripts/archive.sh`、`scripts/sign.sh`、`scripts/notarize.sh`、`scripts/package-dmg.sh`、`scripts/validate-release.sh`
- 落地 `ci.yml`、`release.yml`
- 固化签名、公证、DMG 打包和发布验证入口

## 本阶段产出

- 本地与 CI 复用的发布脚本集合
- GitHub Actions 工作流
- 产物校验和发布前置检查
- 可审计的 secrets 使用约束

## 明确不做

- 不在此阶段执行真实特权 smoke 测试
- 不在 workflow 里复制脚本逻辑

## 完成判定

- 自动化测试、归档、签名、公证和打包路径已固化
- CI 工作流调用仓库脚本而不是内联复杂逻辑
- 发布校验命令与流程符合通用规划约束

## 依赖关系

- 依赖 Phase 5
