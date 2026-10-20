# System Monitor · CPU 监控中台

一个面向 Windows 的**科技风可视化 CPU 监控与进程控制系统**。不依赖浏览器、不需要安装 Git/Python，单个 `.hta` 文件双击即用，自带完整的进程知识库与风险标注。

---

## 这个项目是干什么的

当你打开任务管理器看到 CPU 飙到 100%，面对一长串进程名却不知道：

- 这个进程**是干什么的**？
- 它**为什么**占用这么多 CPU？
- 我能不能**优化**它？优化了有什么**风险**？

System Monitor 就是为解决这个问题而生的。它把上面三个问题的答案直接摆在你面前：

| 能力 | 说明 |
|------|------|
| **实时监控** | CPU / 内存 / 进程数 / 线程数仪表盘，CPU 历史曲线（60 个数据点） |
| **进程知识库** | 内置 20+ 常见进程的说明：Trae CN、svchost、RuntimeBroker、Defender…… |
| **占用原因分析** | 每个进程标注"为什么占用高"（AI 补全、索引、扫描、死循环等） |
| **风险等级标注** | 四色风险体系：低 / 中 / 高 / 禁止操作，系统关键进程按钮自动锁定 |
| **右键菜单** | 降优先级 / 恢复优先级 / 打开文件位置 / 复制 PID / 结束进程 |
| **一键优化** | 批量将高 CPU 进程降为"低于正常"优先级，只调优先级、不结束任何进程 |

---

## 用了什么技术

| 层面 | 技术 | 说明 |
|------|------|------|
| **运行时** | HTA (HTML Application) | Windows 原生桌面应用格式，`mshta.exe` 宿主，双击即运行，拥有完整系统权限 |
| **界面** | HTML5 + CSS3 + Canvas | 深色科技风 HUD 界面：霓虹青色主题、网格背景、扫描线动画、发光仪表盘、CPU 曲线辉光描边 |
| **数据采集** | WMI (Windows Management Instrumentation) | 通过 `WbemScripting.SWbemLocator` 查询 `Win32_PerfFormattedData_PerfOS_Processor`、`PerfProc_Process` 等性能计数器 |
| **进程控制** | WMI `Win32_Process` 方法 | `SetPriority()` 调优先级、`Terminate()` 结束进程 —— **毫秒级原生调用，不启动 PowerShell/外部进程** |
| **脚本语言** | JScript (ECMAScript 3) | HTA 内使用，兼容 IE11 引擎，无外部依赖 |

### 为什么选 HTA

- **零依赖**：不需要安装 Git、Python、Node、浏览器扩展
- **系统权限**：可直接读写 WMI、调用 Win32_Process，无需管理员提权（部分操作需要）
- **单文件交付**：整个程序就是一个 `.hta` 文件，约 47 KB

---

## 快速开始

1. 下载 `SystemMonitor.hta`
2. 双击运行（Windows 会用 `mshta.exe` 打开）
3. 界面出现后，右键任意进程行打开操作菜单

> 要求：Windows 7 及以上，无需安装任何运行时。

### 附加脚本

| 文件 | 用途 |
|------|------|
| `SystemMonitor.ps1` | PowerShell 版监控脚本（适合命令行环境） |
| `cpu_optimizer.ps1` | 一键优化：停止后台服务 + 降低进程优先级 |
| `cpu_optimizer_advanced.ps1` | 守护进程模式：持续监控并自动优化 |
| `process_monitor.ps1` | 进程列表实时刷新（终端版） |
| `cpu_dashboard.html` | 早期 HTML 仪表盘（需本地服务器） |

---

## 项目结构

```
system-monitor-hta/
├── SystemMonitor.hta            # 主程序（推荐，双击即用）
├── SystemMonitor.ps1            # PowerShell 版监控
├── cpu_optimizer.ps1            # CPU 优化脚本
├── cpu_optimizer_advanced.ps1   # 进阶优化（守护进程）
├── process_monitor.ps1          # 进程监控脚本
├── cpu_dashboard.html           # HTML 仪表盘（早期版本）
└── README.md
```

---

## 风险等级说明

| 等级 | 颜色 | 含义 | 示例 |
|------|------|------|------|
| 低风险 | 🟢 绿色 | 可放心优化，不影响系统 | 浏览器标签页、网盘客户端 |
| 中风险 | 🟡 黄色 | 会丢失该程序未保存内容 | Trae CN、编译器 |
| 高风险 | 🟠 橙色 | 影响系统功能，需谨慎 | explorer（结束会黑屏） |
| 禁止操作 | 🔴 红色 | 系统关键进程，禁止结束 | svchost、dwm、lsass |

系统关键进程的"结束"和"降优先级"按钮会**自动置灰不可点**。

---

## 远景规划 (Roadmap)

### 短期 (v3.x)
- [ ] 进程 CPU 占用趋势迷你图（每行内嵌 sparkline）
- [ ] 进程树视图（父子进程层级展开）
- [ ] 网络连接监控（每个进程的端口/连接数）
- [ ] 磁盘 I/O 监控（读写字节/秒）
- [ ] 自定义知识库（用户可编辑进程说明）

### 中期 (v4)
- [ ] 进程历史快照（记录 CPU 尖峰并标注触发程序）
- [ ] 自动优化策略引擎（基于规则自动降优先级/结束）
- [ ] 多机器聚合监控（局域网内多台机器汇总）
- [ ] 导出报告（PDF/HTML 性能分析报告）

### 长期
- [ ] 跨平台支持（macOS / Linux 版本，基于 Node.js + Electron 重写核心）
- [ ] AI 驱动的异常检测（基于历史数据识别异常进程行为）
- [ ] 插件系统（支持第三方扩展进程分析规则）
- [ ] 移动端远程查看（手机端查看电脑 CPU 状态）

---

## License

MIT License — 自由使用、修改、分发。

---

> 本项目源于一次"为什么我的电脑这么卡"的排查经历。希望它能帮你在下次 CPU 飙红时，不再对着任务管理器发呆。
