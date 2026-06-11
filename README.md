# TCPTest — OpenHarmony 北向监控系统

基于 OpenHarmony 4.0（九联开发板）的物联网北向监控系统，通过 NAPI 采集传感器数据，经 TCP 上报云服务器，支持 Web 端实时查看与控制。

> [!WARNING]
> 项目持续开发中

## 功能

- **WiFi 管理** — 扫描可用 WiFi、连接/断开、显示信号强度与 IP
- **传感器采集** — 通过 `@ohos.guardsys_napi` 读取 SHT30（温湿度）和 MQ-2（烟雾）传感器
- **TCP 通信** — 连接云服务器，上报数据，接收服务器下发的控制指令
- **自动上报** — 定时循环上报传感器数据到服务器（间隔可配）
- **报警控制** — 远程/本地设置蜂鸣器+LED 报警模式（正常/警告/报警）
- **实时刷新** — 每秒自动刷新传感器数据，采集失败时前端红色错误提示
- **命令控制** — 服务器可通过 JSON 指令触发采集和报警设置

## 项目结构

```
entry/src/main/ets/pages/
├── Index.ets            # 原始 TCP 通信测试页（兼容保留）
├── MonitorPage.ets       # 北向监控主页面（新入口）
├── SensorManager.ets     # NAPI 传感器接口封装
├── TCPClient.ets         # TCP Socket 客户端封装
├── WifiManager.ets       # WiFi 扫描/连接管理
└── SensorData.ets        # NAPI 原始测试页（保留）
```

### 模块说明

| 文件 | 职责 |
|------|------|
| `MonitorPage.ets` | 主界面：WiFi 配置、服务器连接、传感器卡片、自动上报、报警控制、日志 |
| `SensorManager.ets` | 封装 `guardsys_napi` 的 `getSht30Data` / `getMq2Data` / `setAlarmStatus` |
| `TCPClient.ets` | 基于 `@ohos.net.socket` 的 TCP 客户端，支持域名连接与事件回调 |
| `WifiManager.ets` | 基于 `@ohos.wifiManager`（API 10）的 WiFi 扫描、连接、信息获取 |

## 硬件依赖

- 九联开发板（OpenHarmony 4.0）
- SHT30 温湿度传感器（I2C 地址 0x44）
- MQ-2 烟雾传感器
- 蜂鸣器 + RGB LED（报警输出）

## 开发环境

- DevEco Studio 4.0+
- OpenHarmony SDK API 10
- Node.js / npm（构建工具链）

## 构建与运行

1. 用 DevEco Studio 打开项目根目录
2. 连接开发板或使用模拟器
3. `Build → Build Hap(s)/APP(s)`
4. 安装 HAP 到开发板

## 服务器协议

### 上报数据格式（开发板 → 服务器）

```json
{
  "type": "report",
  "temp": "25.3",
  "humi": "60.1",
  "smoke": 12.34,
  "alarm": 0
}
```

### 控制指令格式（服务器 → 开发板）

```json
{
  "type": "cmd",
  "action": "setAlarm",
  "value": 1
}
```

| action | 说明 |
|--------|------|
| `setAlarm` | 设置报警模式：0=正常，1=警告，2=报警 |
| `collect` | 立即采集一次传感器数据 |

## API 10 适配说明

本项目适配 OpenHarmony API 10 的 WiFi API 变更：

- `addDeviceConfig` → `addCandidateConfig`
- `connectToDevice` → `connectToCandidateConfig`
- `signalLevel` 改为基于 `rssi` 手动计算
- 连接状态通过 `getLinkedInfo().ssid` 对比判断

## 权限说明

在 `module.json5` 中声明以下权限：

| 权限 | 类型 | 用途 |
|------|------|------|
| `ohos.permission.INTERNET` | system_grant | TCP 网络通信 |
| `ohos.permission.GET_WIFI_INFO` | system_grant | 获取 WiFi 信息 |
| `ohos.permission.SET_WIFI_INFO` | system_grant | 配置 WiFi 连接 |
| `ohos.permission.LOCATION` | user_grant | WiFi 扫描 |
| `ohos.permission.APPROXIMATELY_LOCATION` | user_grant | WiFi 扫描 |

`LOCATION` 和 `APPROXIMATELY_LOCATION` 为 user_grant 权限，需在扫描 WiFi 时调用 `requestPermissionsFromUser()` 运行时弹窗申请。

## 引脚定义

| 功能 | 引脚 |
|------|------|
| SHT30 I2C | 5, 0x44 |
| MQ-2 | GPIO 1 |
| 蜂鸣器 | 384 |
| 红灯 | 381 |
| 绿灯 | 382 |
| 蓝灯 | 383 |
