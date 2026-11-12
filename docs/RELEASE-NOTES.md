AI 潮汐 / AI Tide 0.1.0 — macOS 预览版

原生 SwiftUI 应用，将已核验 AI 客户端进程的真实收发字节变成玉绿与暖铜流光。含一分钟曲线、来源检查、暂停、菜单栏和完整 Dock/Finder 图标。

下载 Universal DMG，拖到 Applications。macOS 14+；包含 Apple Silicon 与 Intel 架构，Intel 实机未验收。无需安装额外运行时，不改代理、不解密 HTTPS、不要求 root。

**本预览采用 ad-hoc 签名，未经过 Apple 公证。** 首次浏览器下载可能需要在系统设置中为本应用单独授权。先核对来源和 SHA256，不要关闭全局 Gatekeeper。

已验证：9 组核心回归；2 MiB 真实受控 TCP 传输与系统读数一致；Claude Code / Codex CLI 真实请求、签名及字节观测；Codex GUI 辅助进程；通用二进制、搬移后素材与图标；DMG 容器校验。

范围：轮询取得的同一用户原生进程 TCP/UDP 字节，含本地与后台流量。短命进程与结束的连接可能漏计；首样本和计数器回退重新建立基线。字节不是 token、费用、请求次数、思考或完整审计。TUI 支持同一 CLI 二进制身份，本轮交互式请求的流量关联未单独通过；独立 ChatGPT 聊天客户端、浏览器标签页、远程 SSH 内部任务和 Intel 实机仍未验收。

官网：https://harnessloom.com/ai-tide/
源码与安装说明：https://github.com/jokeuncle/ai-tide
