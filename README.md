# GuardSysAPP — OpenHarmony 北向监控系统

基于 OpenHarmony 4.0（九联开发板）的物联网北向监控系统，通过 NAPI 采集传感器数据，经 TCP 上报云服务器，支持 Web 端实时查看与控制。

> [!WARNING]
> 项目持续开发中

## 功能

- **WiFi 管理** — 扫描可用 WiFi、连接/断开、显示信号强度与 IP
- **传感器采集** — 通过 `@ohos.guardsys_napi` 并行读取 SHT30（温湿度）、MQ-2（烟雾）、HC-SR501（红外）
- **自动报警** — 烟雾/温度超阈值自动触发报警模式（正常/警告/报警），驱动蜂鸣器+RGB LED
- **TCP 通信** — 连接云服务器，上报数据，接收服务器下发的控制指令
- **自动上报** — 定时循环上报传感器数据到服务器（间隔可配）
- **实时刷新** — 每秒自动刷新传感器数据，采集失败时前端红色错误提示
- **绿灯初始化** — 启动时自动点亮绿灯，指示系统正常运行
- **命令控制** — 服务器可通过 JSON 指令触发采集和报警设置

## 项目结构

```
entry/src/main/ets/pages/
├── Index.ets              # 北向监控主页面（程序入口）
├── SensorManager.ets      # NAPI 传感器接口封装（温湿度/烟雾/红外/报警）
├── TCPClient.ets          # TCP Socket 客户端封装
├── WifiManager.ets        # WiFi 扫描/连接管理（API 10）
├── PriSensorData.ets      # NAPI 原始测试页（保留）
└── PriTCPTestIndex.ets    # TCP 通信原始测试页（保留）
```

### 模块说明

| 文件 | 职责 |
|------|------|
| `Index.ets` | 主界面：WiFi 配置、服务器连接、4 传感器卡片、自动上报、报警控制、日志 |
| `SensorManager.ets` | 封装 `guardsys_napi` 的 `getSht30Data` / `getMq2Data` / `getIrStatus` / `setAlarmStatus`；提供 `Promise.all` 并行读取 |
| `TCPClient.ets` | 基于 `@ohos.net.socket` 的 TCP 客户端，支持域名连接与事件回调 |
| `WifiManager.ets` | 基于 `@ohos.wifiManager`（API 10）的 WiFi 扫描、连接、信息获取 |
| `PriSensorData.ets` | 逐项调用 NAPI 接口的原始测试页 |
| `PriTCPTestIndex.ets` | 原始 TCP 通信测试页（Index.ets 重命名保留） |

## 硬件依赖

- 九联开发板（OpenHarmony 4.0）
- SHT30 温湿度传感器（I2C 5, 0x44）
- MQ-2 烟雾传感器（GPIO 1）
- HC-SR501 红外人体感应模块（GPIO 9）
- 蜂鸣器（GPIO 384）+ RGB LED（R=381, G=382, B=383）

## 开发环境

- DevEco Studio 4.0+
- OpenHarmony SDK API 10
- Node.js / npm（构建工具链）

## 构建与运行

1. 用 DevEco Studio 打开项目根目录
2. 连接开发板或使用模拟器
3. `Build → Build Hap(s)/APP(s)`
4. 安装 HAP 到开发板

## 传感器并行读取

三个传感器通过 `Promise.all` 并行读取，互不干扰：

```typescript
const [sht30, mq2, ir] = await Promise.all([
  SensorManager.getSht30Data(),
  SensorManager.getMq2Data(),
  SensorManager.getIrData()
]);
```

## 自动报警逻辑

每次数据采集后自动检测阈值，驱动蜂鸣器+RGB LED：

| 条件 | 报警模式 | LED |
|------|----------|-----|
| 烟雾 >= 200 | 报警 (2) | 红色+蜂鸣器 |
| 烟雾 >= 100 或 温度 >= 40 | 警告 (1) | 黄色 |
| 烟雾 >= 50 或 温度 >= 35 | 正常 (0) | 绿色（提示关注） |
| 正常范围 | 正常 (0) | 绿色 |

## 服务器协议

### 上报数据格式（开发板 → 服务器）

```json
{
  "type": "report",
  "temp": "25.3",
  "humi": "60.1",
  "smoke": 12.34,
  "ir": true,
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
| SHT30 I2C | GPIO 5, 地址 0x44 |
| MQ-2 | GPIO 1 |
| HC-SR501 红外 | GPIO 9 |
| 蜂鸣器 | GPIO 384 |
| 红灯 (R) | GPIO 381 |
| 绿灯 (G) | GPIO 382 |
| 蓝灯 (B) | GPIO 383 |
