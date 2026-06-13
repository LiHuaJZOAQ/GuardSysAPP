import { SensorManager, SensorData } from './SensorManager';
import { defaultTcpClient } from './TCPClient';
import { WifiManagerHelper } from './WifiManager';
import { LogStore } from './LogStore';
import router from '@ohos.router';

interface ServerCommand {
  type: string;
  action?: string;
  value?: number;
}

@Entry
@Component
struct Index {
  // WiFi状态（仅显示）
  @State wifiStatus: string = '未连接';
  @State localIP: string = '0.0.0.0';

  // TCP状态（仅显示）
  @State tcpStatus: string = '未连接';

  // 传感器数据
  @State temp: string = '--';
  @State humi: string = '--';
  @State smoke: string = '--';
  @State ir: string = '--';
  @State isCollecting: boolean = false;
  @State sensorError: string = '';
  private refreshTimerId: number = -1;

  // 报警
  @State alarmMode: string = '--';
  @State alarmLog: string = '--';

  async aboutToAppear(): Promise<void> {
    LogStore.add('北向监控启动');
    try {
      await SensorManager.initAlarm();
      this.alarmMode = '正常';
      this.alarmLog = '绿灯已初始化';
      LogStore.add('报警初始化：绿灯');
    } catch (e) {
      LogStore.add('报警初始化失败: ' + e);
    }

    // 监听 TCP 状态变化
    defaultTcpClient.onConnectCallback = () => {
      this.tcpStatus = '已连接';
      LogStore.add('服务器连接成功');
    };
    defaultTcpClient.onCloseCallback = () => {
      this.tcpStatus = '已断开';
      LogStore.add('服务器连接已断开');
    };
    defaultTcpClient.onErrorCallback = (err: string) => {
      LogStore.add('连接错误: ' + err);
      this.tcpStatus = '连接失败';
    };
    defaultTcpClient.onMessageCallback = (msg: string) => {
      this.handleServerCommand(msg);
    };

    this.collectAll();
    this.refreshTimerId = setInterval(() => {
      this.collectAll(true);
    }, 1000);
    await this.updateStatus();
  }

  aboutToDisappear(): void {
    if (this.refreshTimerId !== -1) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
    defaultTcpClient.release();
  }

  // ---- 状态更新 ----

  async updateStatus(): Promise<void> {
    if (WifiManagerHelper.isConnected()) {
      this.wifiStatus = '已连接';
      this.localIP = WifiManagerHelper.getLocalIP();
    } else {
      this.wifiStatus = '未连接';
      this.localIP = '0.0.0.0';
    }
    this.tcpStatus = defaultTcpClient.isConnected() ? '已连接' : '未连接';
  }

  openSettings(): void {
    router.pushUrl({ url: 'pages/SettingsPage' });
  }

  openLog(): void {
    router.pushUrl({ url: 'pages/LogPage' });
  }

  // ---- 服务器命令处理 ----

  handleServerCommand(msg: string): void {
    LogStore.add('收到命令: ' + msg.substring(0, 80));
    try {
      const cmd: ServerCommand = JSON.parse(msg) as ServerCommand;
      if (cmd.type === 'cmd') {
        if (cmd.action === 'setAlarm') {
          this.setAlarmMode(cmd.value as number);
        } else if (cmd.action === 'collect') {
          this.collectAll();
        }
      }
    } catch (e) {
      // 非JSON格式，忽略
    }
  }

  // ---- 传感器数据采集 ----

  async collectAll(silent: boolean = false): Promise<void> {
    if (this.isCollecting) return;
    this.isCollecting = true;
    try {
      const data: SensorData = await SensorManager.getAllData();
      this.temp = data.temp.toFixed(1);
      this.humi = data.humi.toFixed(1);
      this.smoke = data.smoke.toFixed(2);
      this.ir = data.ir ? '有人' : '无人';
      this.sensorError = '';
      this.checkAlarmThreshold(data);
      if (!silent) {
        LogStore.add('采集完成: ' + this.temp + '°C ' + this.humi + '% 烟雾=' + this.smoke + ' 红外=' + this.ir);
      }
    } catch (e) {
      this.sensorError = '采集失败: ' + e;
      if (!silent) {
        LogStore.add('采集失败: ' + e);
      }
    }
    this.isCollecting = false;
  }

  getAlarmValue(): number {
    if (this.alarmMode === '正常') return 0;
    if (this.alarmMode === '警告') return 1;
    if (this.alarmMode === '报警') return 2;
    return 0;
  }

  checkAlarmThreshold(data: SensorData): void {
    let targetMode: number = 0;
    let reason: string = '';

    if (data.smoke >= 200) {
      targetMode = 2;
      reason = '烟雾值过高(' + data.smoke.toFixed(1) + ')';
    } else if (data.smoke >= 100 || data.temp >= 40) {
      targetMode = 1;
      reason = data.smoke >= 100 ? '烟雾偏高(' + data.smoke.toFixed(1) + ')' : '温度过高(' + data.temp.toFixed(1) + '°C)';
    } else if (data.smoke >= 50 || data.temp >= 35) {
      targetMode = 0;
      reason = '数值偏高，请关注';
    }

    const labels: string[] = ['正常', '警告', '报警'];
    if (targetMode !== this.getAlarmValue() || this.alarmLog === '--') {
      this.alarmMode = labels[targetMode] || '正常';
      this.alarmLog = reason !== '' ? reason : '正常';
      SensorManager.setAlarmMode(targetMode);
      LogStore.add('报警状态: ' + this.alarmMode + (reason !== '' ? ' (' + reason + ')' : ''));
    }
  }

  // ---- 报警控制 ----

  async setAlarmMode(mode: number): Promise<void> {
    try {
      await SensorManager.setAlarmMode(mode);
      const labels: string[] = ['正常', '警告', '报警'];
      this.alarmMode = labels[mode] || '未知';
      this.alarmLog = '已设为' + this.alarmMode;
      LogStore.add('报警已设为: ' + this.alarmMode);
    } catch (e) {
      LogStore.add('报警设置失败: ' + e);
    }
  }

  // ---- 构建UI ----

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          // 标题栏
          Row() {
            Text('🌐 北向监控')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
            Blank()
            if (this.localIP !== '0.0.0.0') {
              Text('IP: ' + this.localIP)
                .fontSize(12)
                .fontColor('#007DFF')
            }
            Button('日志')
              .height(30)
              .fontSize(13)
              .backgroundColor('#8E44AD')
              .margin({ right: 6 })
              .onClick(() => { this.openLog(); })
            Button('设置')
              .height(30)
              .fontSize(13)
              .backgroundColor('#007DFF')
              .onClick(() => { this.openSettings(); })
          }
          .width('100%')
          .margin({ top: 16, bottom: 4 })

          // ---- 网络状态一览 ----
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text('WiFi')
                .fontSize(12)
                .fontColor('#888888')
              Text(this.wifiStatus)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.wifiStatus === '已连接' ? '#00AA00' : '#FF6600')
            }
            .layoutWeight(1)
            .padding(8)
            .backgroundColor('#FFF8E1')
            .borderRadius(8)
            .alignItems(HorizontalAlign.Center)

            Column({ space: 4 }) {
              Text('服务器')
                .fontSize(12)
                .fontColor('#888888')
              Text(this.tcpStatus)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.tcpStatus === '已连接' ? '#00AA00' :
                  this.tcpStatus === '连接中...' ? '#FF6600' : '#999999')
            }
            .layoutWeight(1)
            .padding(8)
            .backgroundColor('#F5F8FF')
            .borderRadius(8)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')

          // ---- 实时传感器数据 ----
          Column({ space: 8 }) {
            Row() {
              Text('📊 实时传感器数据')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Button('手动采集')
                .height(28)
                .fontSize(12)
                .enabled(!this.isCollecting)
                .onClick(() => { this.collectAll(); })
            }
            .width('100%')

            if (this.sensorError !== '') {
              Text(this.sensorError)
                .width('100%')
                .fontSize(13)
                .fontColor('#FFFFFF')
                .backgroundColor('#E74C3C')
                .borderRadius(6)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .align(Alignment.Start)
            }

            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text('🌡️')
                  .fontSize(28)
                Text(this.temp + '°C')
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#E74C3C')
                Text('温度')
                  .fontSize(13)
                  .fontColor('#888888')
              }
              .layoutWeight(1)
              .padding(12)
              .backgroundColor('#FFF5F5')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 4 }) {
                Text('💧')
                  .fontSize(28)
                Text(this.humi + '%')
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#3498DB')
                Text('湿度')
                  .fontSize(13)
                  .fontColor('#888888')
              }
              .layoutWeight(1)
              .padding(12)
              .backgroundColor('#F0F8FF')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')

            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text('💨')
                  .fontSize(28)
                Text(this.smoke)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.smoke !== '--' && parseInt(this.smoke) > 100 ? '#E74C3C' : '#2ECC71')
                Text('烟雾值')
                  .fontSize(13)
                  .fontColor('#888888')
              }
              .layoutWeight(1)
              .padding(12)
              .backgroundColor('#F0FFF0')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)

              Column({ space: 4 }) {
                Text('🚶')
                  .fontSize(28)
                Text(this.ir)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.ir === '有人' ? '#E67E22' : '#95A5A6')
                Text('红外')
                  .fontSize(13)
                  .fontColor('#888888')
              }
              .layoutWeight(1)
              .padding(12)
              .backgroundColor('#FFF8E7')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(10)

          // ---- 报警状态（仅显示） ----
          Column({ space: 8 }) {
            Row() {
              Text('🚨 报警状态')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Text(this.alarmMode)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.alarmMode === '正常' ? '#2ECC71' :
                  this.alarmMode === '警告' ? '#F39C12' : '#E74C3C')
            }
            .width('100%')

            Row({ space: 16 }) {
              Text('当前: ')
                .fontSize(14)
              Text(this.alarmMode)
                .fontSize(14)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.alarmMode === '正常' ? '#2ECC71' :
                  this.alarmMode === '警告' ? '#F39C12' : '#E74C3C')
              Text(this.alarmLog)
                .fontSize(12)
                .fontColor('#888888')
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF0F0')
          .borderRadius(10)
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
