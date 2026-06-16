import { SensorManager, SensorData, Sht30Data, Mq2Data, IrData } from './SensorManager';
import { defaultTcpClient } from './TCPClient';
import { WifiManagerHelper } from './WifiManager';
import { LogStore } from './LogStore';
import { SharedConfig } from './SharedConfig';
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
  @State sensorError: string = '';
  @State currentTime: string = '';
  private refreshTimerId: number = -1;
  private clockTimerId: number = -1;

  // 报警
  @State alarmMode: string = '--';
  @State alarmLog: string = '--';
  @State isArmed: boolean = false;
  private irAlarmLatched: boolean = false;
  private prevSmoke: number = 0;

  async aboutToAppear(): Promise<void> {
    LogStore.add('北向监控启动');
    try {
      await SensorManager.initAlarm();
      this.alarmMode = '正常';
      this.alarmLog = '绿灯已初始化';
      LogStore.add('报警初始化：绿灯');
    } catch (e) {
      LogStore.add('报警初始化失败: ' + e, 'warn');
    }

    // 监听 TCP 状态变化
    defaultTcpClient.onConnectCallback = () => {
      this.tcpStatus = '已连接';
      LogStore.add('服务器连接成功');
    };
    defaultTcpClient.onCloseCallback = () => {
      this.tcpStatus = '已断开';
      LogStore.add('服务器连接已断开', 'warn');
    };
    defaultTcpClient.onErrorCallback = (err: string) => {
      LogStore.add('连接错误: ' + err, 'error');
      this.tcpStatus = '连接失败';
    };
    defaultTcpClient.onMessageCallback = (msg: string) => {
      this.handleServerCommand(msg);
    };

    this.collectAll();
    this.startAutoRefresh();
    await this.updateStatus();
    this.startClock();
  }

  onPageShow(): void {
    this.updateStatus();
    this.startAutoRefresh();
    this.startClock();
  }

  aboutToDisappear(): void {
    if (this.clockTimerId !== -1) {
      clearInterval(this.clockTimerId);
      this.clockTimerId = -1;
    }
    if (this.refreshTimerId !== -1) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
    defaultTcpClient.release();
  }

  startAutoRefresh(): void {
    if (this.refreshTimerId !== -1) {
      clearInterval(this.refreshTimerId);
    }
    this.refreshTimerId = setInterval(() => {
      this.collectAll(true);
    }, SharedConfig.refreshInterval);
  }

  startClock(): void {
    if (this.clockTimerId !== -1) {
      clearInterval(this.clockTimerId);
    }
    const now: Date = new Date();
    const h: string = now.getHours().toString().padStart(2, '0');
    const m: string = now.getMinutes().toString().padStart(2, '0');
    const s: string = now.getSeconds().toString().padStart(2, '0');
    this.currentTime = h + ':' + m + ':' + s;
    this.clockTimerId = setInterval(() => {
      const d: Date = new Date();
      const hh: string = d.getHours().toString().padStart(2, '0');
      const mm: string = d.getMinutes().toString().padStart(2, '0');
      const ss: string = d.getSeconds().toString().padStart(2, '0');
      this.currentTime = hh + ':' + mm + ':' + ss;
    }, 1000);
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
          this.setAlarmMode(cmd.value as number, '远程');
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
    let errMsg: string = '';
    let curTemp: number = 0;
    let curHumi: number = 0;
    let curSmoke: number = 0;
    let curIr: boolean = false;
    try {
      const sht30: Sht30Data = await SensorManager.getSht30Data();
      curTemp = sht30.temp;
      curHumi = sht30.humi;
      this.temp = curTemp.toFixed(1);
      this.humi = curHumi.toFixed(1);
    } catch (e) {
      errMsg = '温湿度采集失败';
    }
    try {
      const mq2: Mq2Data = await SensorManager.getMq2Data();
      curSmoke = mq2.smoke;
      this.smoke = curSmoke.toFixed(2);
    } catch (e) {
      errMsg = (errMsg ? errMsg + '; ' : '') + '烟雾采集失败';
    }
    try {
      const irData: IrData = await SensorManager.getIrData();
      curIr = irData.ir;
      this.ir = curIr ? '有人' : '无人';
    } catch (e) {
      errMsg = (errMsg ? errMsg + '; ' : '') + '红外采集失败';
    }
    if (errMsg) {
      this.sensorError = errMsg;
      if (!silent) {
        LogStore.add(errMsg, 'error');
      }
    } else {
      this.sensorError = '';
      if (!silent) {
        LogStore.add('采集完成: ' + this.temp + '°C ' + this.humi + '% 烟雾=' + this.smoke + ' 红外=' + this.ir);
      }
    }
    const alarmData: SensorData = { temp: curTemp, humi: curHumi, smoke: curSmoke, ir: curIr };
    this.checkAlarmThreshold(alarmData);
  }

  async refreshSht30(): Promise<void> {
    try {
      const data: Sht30Data = await SensorManager.getSht30Data();
      this.temp = data.temp.toFixed(1);
      this.humi = data.humi.toFixed(1);
      this.sensorError = '';
      this.checkAlarmThresholdFromState();
      LogStore.add('温湿度已刷新: ' + this.temp + '°C ' + this.humi + '%');
    } catch (e) {
      this.sensorError = '温湿度刷新失败: ' + e;
      LogStore.add('温湿度刷新失败: ' + e, 'error');
    }
  }

  async refreshSmoke(): Promise<void> {
    try {
      const data: Mq2Data = await SensorManager.getMq2Data();
      this.smoke = data.smoke.toFixed(2);
      this.sensorError = '';
      this.checkAlarmThresholdFromState();
      LogStore.add('烟雾已刷新: ' + this.smoke);
    } catch (e) {
      this.sensorError = '烟雾刷新失败: ' + e;
      LogStore.add('烟雾刷新失败: ' + e, 'error');
    }
  }

  async refreshIr(): Promise<void> {
    try {
      const data: IrData = await SensorManager.getIrData();
      this.ir = data.ir ? '有人' : '无人';
      this.sensorError = '';
      LogStore.add('红外已刷新: ' + this.ir);
    } catch (e) {
      this.sensorError = '红外刷新失败: ' + e;
      LogStore.add('红外刷新失败: ' + e, 'error');
    }
  }

  checkAlarmThresholdFromState(): void {
    const tempVal: number = parseFloat(this.temp);
    const humiVal: number = parseFloat(this.humi);
    const smokeVal: number = parseFloat(this.smoke);
    const data: SensorData = {
      temp: isNaN(tempVal) ? 0 : tempVal,
      humi: isNaN(humiVal) ? 0 : humiVal,
      smoke: isNaN(smokeVal) ? 0 : smokeVal,
      ir: this.ir === '有人'
    };
    this.checkAlarmThreshold(data);
  }

  getAlarmValue(): number {
    if (this.alarmMode === '正常') return 0;
    if (this.alarmMode === '警告') return 1;
    if (this.alarmMode === '报警') return 2;
    return 0;
  }

  checkAlarmThreshold(data: SensorData): void {
    let targetMode: number = 0;
    const parts: string[] = [];

    // 布防：红外有人直接触发报警（锁定，需手动撤销）
    if (this.isArmed && data.ir) {
      if (targetMode < 2) targetMode = 2;
      this.irAlarmLatched = true;
      parts.push('布防报警: 有人入侵');
    }
    // 红外布防报警锁定：阻止自动降级
    if (this.irAlarmLatched && targetMode < 2) {
      targetMode = 2;
    }

    if (data.smoke >= 200) {
      if (targetMode < 2) targetMode = 2;
      parts.push('烟雾过高(' + data.smoke.toFixed(1) + ')');
    }

    // 火险+人员未撤离（布防/撤防均生效）
    if (data.ir && (data.smoke >= 100 || data.temp >= 40) && targetMode < 2) {
      targetMode = 2;
      parts.push('危险区域有人未撤离');
    }

    if ((data.smoke >= 100 || data.temp >= 40) && targetMode < 2) {
      if (targetMode < 1) targetMode = 1;
    }
    if (data.smoke >= 100) {
      parts.push('烟雾偏高(' + data.smoke.toFixed(1) + ')');
    } else if (data.temp >= 40) {
      parts.push('温度过高(' + data.temp.toFixed(1) + '°C)');
    }

    if (data.humi >= 80 && targetMode < 2) {
      if (targetMode < 1) targetMode = 1;
      parts.push('湿度过高(' + data.humi.toFixed(1) + '%)');
    }
    if (data.humi <= 20 && targetMode < 2) {
      if (targetMode < 1) targetMode = 1;
      parts.push('湿度过低(' + data.humi.toFixed(1) + '%)');
    }

    const smokeDelta: number = data.smoke - this.prevSmoke;
    if (smokeDelta >= 50 && targetMode < 2) {
      if (targetMode < 1) targetMode = 1;
      parts.push('烟雾突增(+' + smokeDelta.toFixed(1) + ')');
    }

    if (data.smoke >= 50 || data.temp >= 35) {
      parts.push('数值偏高');
    }
    if (data.humi >= 70 || data.humi <= 30) {
      parts.push('湿度异常(' + data.humi.toFixed(1) + '%)');
    }
    // 撤防时红外仅记录，布防时已上报入侵
    if (!this.isArmed && data.ir) {
      parts.push('有人活动');
    }

    this.prevSmoke = data.smoke;

    const reason: string = parts.length > 0 ? parts.join(' | ') : '正常';
    const labels: string[] = ['正常', '警告', '报警'];
    if (targetMode !== this.getAlarmValue() || this.alarmLog === '--') {
      this.alarmMode = labels[targetMode] || '正常';
      this.alarmLog = reason;
      SensorManager.setAlarmMode(targetMode);
      const logLevel: string = targetMode >= 2 ? 'error' : (targetMode >= 1 ? 'warn' : 'info');
      LogStore.add('报警状态: ' + this.alarmMode + ' (' + reason + ')', logLevel);
    }
  }

  // ---- 报警控制 ----

  async setAlarmMode(mode: number, source: string = ''): Promise<void> {
    try {
      await SensorManager.setAlarmMode(mode);
      const labels: string[] = ['正常', '警告', '报警'];
      this.alarmMode = labels[mode] || '未知';
      this.alarmLog = '已设为' + this.alarmMode;
      const src: string = source !== '' ? ' (' + source + ')' : '';
      const logLevel: string = mode >= 2 ? 'error' : (mode >= 1 ? 'warn' : 'info');
      LogStore.add('报警已设为: ' + this.alarmMode + src, logLevel);
    } catch (e) {
      LogStore.add('报警设置失败: ' + e, 'error');
    }
  }

  dismissAlarm(): void {
    this.irAlarmLatched = false;
    this.setAlarmMode(0, '手动');
    LogStore.add('警报已手动撤销');
  }

  toggleArm(): void {
    this.isArmed = !this.isArmed;
    if (!this.isArmed) {
      this.irAlarmLatched = false;
    }
    LogStore.add(this.isArmed ? '红外布防已开启' : '红外布防已关闭', this.isArmed ? 'warn' : 'info');
  }

  // ---- 构建UI ----

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          // 标题栏
          Row() {
            Text('智家安防')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
            Text(this.currentTime)
              .fontSize(19)
              .fontColor('#000000')
              .fontWeight(FontWeight.Bold)
              .margin({ left: 10 })
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
            .onClick(() => { this.openSettings(); })
          }
          .width('100%')

          // ---- 实时传感器数据 ----
          Column({ space: 8 }) {
            Row() {
              Text('📊 实时传感器数据')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
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
              .onClick(() => { this.refreshSht30(); })

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
              .onClick(() => { this.refreshSht30(); })
            }
            .width('100%')

            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text('💨')
                  .fontSize(28)
                Text(this.smoke + 'ppm')
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
              .onClick(() => { this.refreshSmoke(); })

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
                Text(this.isArmed ? '🔒 已布防' : '🔓 已撤防')
                  .fontSize(11)
                  .fontColor(this.isArmed ? '#E74C3C' : '#95A5A6')
                  .onClick(() => { this.toggleArm(); })
              }
              .layoutWeight(1)
              .padding(12)
              .backgroundColor(this.isArmed ? '#FFE0E0' : '#FFF8E7')
              .borderRadius(10)
              .alignItems(HorizontalAlign.Center)
              .onClick(() => { this.refreshIr(); })
            }
            .width('100%')
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FAFAFA')
          .borderRadius(10)

          // ---- 报警状态 ----
          Column({ space: 8 }) {
            Row() {
              Text('🚨 报警状态')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              if (this.alarmMode !== '正常' && this.alarmMode !== '--') {
                Button('撤销警报')
                  .height(28)
                  .fontSize(12)
                  .backgroundColor('#2ECC71')
                  .fontColor('#FFFFFF')
                  .onClick(() => { this.dismissAlarm(); })
              }
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

            Row() {
              Text(this.isArmed ? '🔒 红外已布防' : '🔓 红外已撤防')
                .fontSize(12)
                .fontColor(this.isArmed ? '#E74C3C' : '#95A5A6')
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
