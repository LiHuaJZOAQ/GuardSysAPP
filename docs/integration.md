# GuardSysAPP 鸿蒙端对接服务器说明

## 服务器信息

| 项目 | 值 |
|------|-----|
| 协议 | TCP |
| 宿主 | `your-server.railway.app` (部署后获取) |
| 端口 | 3001 |

测试部署：`guardsysserver.up.railway.app`

## 通信协议

### 上报数据 (设备 -> 服务器)

每条 JSON 以换行符 `\n` 结尾。服务器逐行解析多份数据。

```json
{"type":"report","temp":"25.3","humi":"60.1","smoke":12.34,"ir":true,"alarm":0}
```

| 字段 | 类型 | 说明 |
|------|------|------|
| type | string | 固定 `"report"` |
| temp | string | 温度字符串，如 `"25.3"` |
| humi | string | 湿度字符串，如 `"60.1"` |
| smoke | number | 烟雾浓度数值 |
| ir | bool | 红外人体检测 `true/false` |
| alarm | number | 报警模式 0=正常 1=警告 2=报警 |

### 服务器应答

```json
{"success":true}
```

### 控制指令 (服务器 -> 设备)

```json
{"type":"cmd","action":"setAlarm","value":1}
```

| action | value | 说明 |
|--------|-------|------|
| setAlarm | 0/1/2 | 设置报警模式 |
| collect | (无) | 立即采集传感器数据 |

## TCPClient.ets 修改要点

### 1. 替换服务器地址

```typescript
// 修改前
private serverHost: string = '原地址'
private serverPort: number = 原端口

// 修改后
private serverHost: string = 'your-server.railway.app'
private serverPort: number = 3001
```

### 2. 上报数据格式

确保 `sendReport()` 方法发送的 JSON 与下方一致，每个对象末尾带 `\n`：

```typescript
sendReport(temp: string, humi: string, smoke: number, ir: boolean, alarm: number) {
  const data = JSON.stringify({
    type: 'report',
    temp: temp,
    humi: humi,
    smoke: smoke,
    ir: ir,
    alarm: alarm
  }) + '\n'
  this.tcpSocket?.send(data)
}
```

### 3. 接收服务器指令

在 `onMessage` 回调中解析服务器下发的控制指令：

```typescript
onMessage(data: string) {
  const cmd = JSON.parse(data)
  if (cmd.type === 'cmd') {
    if (cmd.action === 'setAlarm') {
      SensorManager.setAlarmStatus(cmd.value)
    } else if (cmd.action === 'collect') {
      this.triggerCollect()
    }
  }
}
```

### 4. 心跳与重连

建议每 30 秒发送一次心跳包保持连接，断开时 5 秒自动重连：

```typescript
// 心跳
setInterval(() => {
  if (this.connected) {
    this.tcpSocket?.send(JSON.stringify({type:'ping'})+'\n')
  }
}, 30000)
```

## Index.ets 修改要点

### 1. 服务器配置输入

在界面中提供服务器地址和端口的配置入口，保存到本地存储：

```typescript
@State serverHost: string = 'your-server.railway.app'
@State serverPort: number = 3001
```

### 2. 连接/断开按钮

```typescript
Button('连接服务器')
  .onClick(() => {
    tcpClient.connect(this.serverHost, this.serverPort)
  })
```

### 3. 状态显示

界面上显示连接状态（已连接/未连接），便于调试。

## 调试建议

1. 先用 `nc` 命令模拟设备发送数据验证服务器通路：
```bash
echo '{"type":"report","temp":"25.3","humi":"60.1","smoke":12.34,"ir":true,"alarm":0}' | nc your-server.railway.app 3001
```

2. 确认能收到 `{"success":true}` 后，再在开发板上联调。

3. 如果 JSON 中有中文或特殊字符，确保 TCP 发送时编码为 UTF-8。
