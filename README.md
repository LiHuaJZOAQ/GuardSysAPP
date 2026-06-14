# GuardSysAPP — OpenHarmony 北向监控系统

基于 OpenHarmony 4.0（九联开发板）的物联网北向监控系统，通过 NAPI 采集传感器数据，经 TCP 上报云服务器，支持 Web 端实时查看与控制。


## 功能

### 传感器采集
- **SHT30** — 温度 + 湿度（I2C GPIO 5, 0x44）
- **MQ-2** — 烟雾浓度（GPIO 1）
- **HC-SR501** — 红外人体检测（GPIO 9），支持布防/撤防模式
- 三传感器通过 `Promise.all` 并行读取，互不干扰
- 点击传感器卡片单独刷新对应传感器数据
- 采集失败时仪表板显示红色错误横幅

### 网络通信
- **WiFi 管理** — 扫描可用 WiFi、连接/断开、显示信号强度与 IP（API 10 适配：`addCandidateConfig` / `connectToCandidateConfig`）
- **TCP 客户端** — 连接云服务器（支持域名），30s 心跳保活，断线 5s 自动重连
- **协议** — JSON + `\n` 分隔，服务器 ACK `{"success":true}`

### 自动报警
- 四级传感器联动检测：**烟雾(ppm)**、**温度(°C)**、**湿度(%)**、**红外(有人/无人)**
- 驱动蜂鸣器 + RGB LED（三级：正常=绿 / 警告=黄 / 报警=红+蜂鸣）
- 支持手动设置报警模式（设置页调试区）
- 仪表板实时显示"撤销警报"按钮（仅报警/警告时出现）
- 报警日志携带原因标记：烟雾过高 / 温度过高 / 湿度过高过低 / 烟雾突增 / 布防入侵 / 人员未撤离

### 红外布防/撤防
- **撤防（默认）**：红外仅记录"有人活动"日志，不触发报警
- **布防**：红外检测到有人立即触发 **mode 2 报警**（蜂鸣器+红灯），发出入侵警报
- 布防状态在红外卡片和报警状态栏均有显示
- **火险+人员未撤离**：无论布防/撤防，只要烟雾/温度超标且检测到有人，自动升级为报警

### 自动上报
- 定时循环上报传感器数据（`temp`/`humi`/`smoke`/`ir`/`alarm`）
- 上报间隔可配（设置页，默认 1s）
- 通过 `SharedConfig` 全局配置单例管理

### 实时刷新
- 每秒自动刷新传感器数据
- 返回仪表板时自动重启定时器并读取最新配置（`onPageShow`）

### 日志系统
- **LogStore 单例**：全局共享日志消息
- **三级分色**：error（红）、warn（黄）、info（黑）
- **独立日志页**：500ms 自动刷新，按等级着色渲染
- 报警原因标记 + 错误标 error 等级

### 命令控制
- 服务器通过 JSON 指令触发：
  - `setAlarm` — 设置报警模式（0=正常, 1=警告, 2=报警）
  - `collect` — 立即采集一次传感器数据

### 设备初始化
- 启动时自动点亮绿灯（`SensorManager.initAlarm()`），指示系统正常运行

## 项目结构

```
entry/src/main/ets/
├── pages/
│   ├── Index.ets              # 仪表板：传感器卡片/报警状态/网络状态/导航
│   ├── SettingsPage.ets        # 设置页：WiFi/TCP/自动上报/刷新间隔/调试
│   ├── LogPage.ets             # 日志查看页（三级分色）
│   ├── SensorManager.ets       # NAPI 传感器接口封装
│   ├── TCPClient.ets           # TCP Socket 客户端（心跳+重连）
│   ├── WifiManager.ets         # WiFi 扫描/连接（API 10）
│   ├── SharedConfig.ets        # 全局配置单例（refreshInterval）
│   ├── LogStore.ets            # 日志单例（LogItem 三级分色）
│   ├── PriSensorData.ets       # NAPI 原始测试页（保留）
│   └── PriTCPTestIndex.ets     # TCP 原始测试页（保留）
└── resources/base/profile/
    └── main_pages.json         # 页面路由注册
```

### 模块职责

| 文件 | 职责 |
|------|------|
| `Index.ets` | 仪表板：4 传感器卡片（点击单独刷新，红外含布防/撤防切换）、报警状态（含撤销按钮+红外布防显示）、网络状态指示器、导航到设置/日志 |
| `SettingsPage.ets` | WiFi 扫描/连接、TCP 服务器配置/连接/断开、自动上报开关与间隔、传感器刷新间隔、调试报警按钮 |
| `LogPage.ets` | 从 LogStore 读取日志，按 level 着色渲染，500ms 轮询 |
| `SensorManager.ets` | NAPI 封装 + `currentAlarmMode` 静态属性 + `setAlarmMode()` 自动更新 |
| `TCPClient.ets` | `defaultTcpClient` 单例，30s 心跳，5s 重连，域名支持 |
| `WifiManager.ets` | API 10 WiFi 适配 |
| `SharedConfig.ets` | `refreshInterval` 全局配置 |
| `LogStore.ets` | `LogItem`（text + level）+ `addLog` / `getLogs` |

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

## 自动报警逻辑

每次数据采集后按优先级检测以下条件，仅输出最高模式：

### 优先级 2 — 报警（红色 + 蜂鸣器）

| 条件 | 触发原因 |
|------|----------|
| **烟雾 >= 200ppm** | 烟雾浓度过高，火险 |
| **红外布防 + IR=有人** | 入侵检测：有人闯入 |
| **红外(任意) + 烟雾>=100 / 温度>=40** | 危险区域有人未撤离 |

### 优先级 1 — 警告（黄色）

| 条件 | 触发原因 |
|------|----------|
| **烟雾 >= 100ppm** | 烟雾偏高 |
| **温度 >= 40°C** | 温度过高 |
| **湿度 >= 80%** | 湿度过高，防霉 |
| **湿度 <= 20%** | 湿度过低，防火 |
| **烟雾单次突增 >= 50ppm** | 烟雾突增，疑似火源 |

### 优先级 0 — 正常（绿色，日志记录）

| 条件 | 说明 |
|------|------|
| **烟雾 >= 50ppm / 温度 >= 35°C** | 数值偏高，提示关注 |
| **湿度 >= 70% 或 <= 30%** | 湿度异常提示 |
| **红外有人（撤防状态）** | 有人活动记录 |
| 全部正常 | 绿灯常亮 |

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

### 心跳

```json
{"type":"ping"}
```

- 开发板每 30s 发送一次，服务器无需回复

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

## 配置指南

### 传感器引脚 / I2C 地址

所有引脚和地址在 `SensorManager.ets` 中的 NAPI 调用处定义：

```typescript
// 文件: entry/src/main/ets/pages/SensorManager.ets

// SHT30 — GPIO 5, I2C 地址 0x44
const res: Sht30Data = await guardsys_napi.getSht30Data(5, 0x44);

// MQ-2 — GPIO 1
const res: Mq2Data = await guardsys_napi.getMq2Data(1);

// HC-SR501 红外 — GPIO 9
const res: IrData = await guardsys_napi.getIrStatus(9);

// 报警输出 — 蜂鸣器 GPIO 384, RGB R=381, G=382, B=383
await guardsys_napi.setAlarmStatus(mode, {
  buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383
});
```

如需更换接线引脚，修改上述对应数字即可。**注意：NAPI 函数签名（参数个数与顺序）不可变更，只能改引脚数值。**

### 服务器地址和端口

默认值定义在 `SettingsPage.ets` 顶部：

```typescript
// 文件: entry/src/main/ets/pages/SettingsPage.ets
@State serverHost: string = 'guardsysserver.up.railway.app';
@State serverPort: string = '3001';
```

修改方式有两种：

1. **直接修改代码**：改上述默认值，重新编译安装 HAP
2. **运行时修改**：打开 App → 右下角"设置" → "📡 服务器连接" → 修改地址和端口 → 点击"连接"

服务器要求运行 TCP 服务（默认端口 3001），协议详见上方"服务器协议"章节。

### 传感器刷新频率

位置：**设置 → 📟 传感器设置 → 刷新间隔**（单位：秒，默认 1s）

持久化存储在 `SharedConfig.ets` 中，重启后恢复为默认值。

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
