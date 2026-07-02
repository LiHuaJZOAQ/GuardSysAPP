# Changelog

## [1.0.0] — 2026-06-11

### Added
- 项目初始化，基于 OpenHarmony 4.0（九联开发板）的北向监控系统
- WiFi 扫描/连接管理（API 10 适配：`addCandidateConfig` + `connectToCandidateConfig`）
- TCP Socket 客户端封装，支持域名连接与事件回调
- NAPI 传感器采集：SHT30 温湿度、MQ-2 烟雾
- 手动采集与每秒自动刷新传感器数据
- 传感器采集失败时前端红色错误横幅提示
- 自动上报（定时 TCP 上报传感器数据到云服务器）
- 远程控制命令处理（setAlarm / collect）
- 三档报警控制（正常/警告/报警），驱动蜂鸣器+RGB LED
- 报警自动触发逻辑（烟雾/温度超阈值切换报警模式）
- 启动时绿灯初始化，指示系统正常运行
- 红外人体感应（HC-SR501）数据采集与显示
- 三传感器并行读取（`Promise.all`），互不干扰
- 密码输入对话框覆盖层（WiFi 加密连接）
- 运行时权限申请（LOCATION + APPROXIMATELY_LOCATION）
- 日志输出与清空功能

### Changed
- `Index.ets` → `PriTCPTestIndex.ets`（原始 TCP 测试页保留）
- `SensorData.ets` → `PriSensorData.ets`（NAPI 原始测试页保留）
- 项目入口从原测试页改为北向监控主页面 `Index.ets`
- 软件包名称：`tcptest` → `guardsysapp`
- 应用包名：`com.example.tcptest` → `com.example.guardsysapp`
- 传感器数据卡片布局：单行 3 卡 → 双行 2×2（温/湿 + 烟/红外）
- 烟雾值显示精度：整数 → 2 位小数

### Fixed
- TCP 连接状态更新 Bug：事件订阅移到 `connect()` 之前
- ArkTS 编译错误：对象字面量替换为显式接口、catch 类型注解移除、standalone `this` 修复
