import { SensorManager, SensorData } from './SensorManager';
import { TCPClient } from './TCPClient';
import { WifiManagerHelper, WifiDeviceInfo } from './WifiManager';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';

interface ServerCommand {
  type: string;
  action?: string;
  value?: number;
}

@Entry
@Component
struct Index {
  private tcpClient: TCPClient = new TCPClient();

  // WiFi相关
  @State wifiList: WifiDeviceInfo[] = [];
  @State selectedWifi: string = '';
  @State wifiPassword: string = '';
  @State wifiStatus: string = '未连接';
  @State localIP: string = '0.0.0.0';
  @State isScanning: boolean = false;
  @State isConnectingWifi: boolean = false;
  @State showPasswordDialog: boolean = false;
  @State passwordInput: string = '';

  // 服务器连接配置
  @State serverHost: string = 'www.example.com';
  @State serverPort: string = '80';
  @State tcpStatus: string = '未连接';
  @State isConnecting: boolean = false;

  // 传感器数据
  @State temp: string = '--';
  @State humi: string = '--';
  @State smoke: string = '--';
  @State ir: string = '--';
  @State isCollecting: boolean = false;
  @State sensorError: string = '';
  private refreshTimerId: number = -1;

  // 自动上报
  @State autoReport: boolean = false;
  @State reportInterval: number = 3;
  private timerId: number = -1;

  // 报警
  @State alarmMode: string = '--';
  @State alarmLog: string = '--';

  // 日志
  @State logMessages: string[] = [];

  async aboutToAppear(): Promise<void> {
    this.addLog('北向监控启动');
    try {
      await SensorManager.initAlarm();
      this.alarmMode = '正常';
      this.alarmLog = '绿灯已初始化';
      this.addLog('报警初始化：绿灯');
    } catch (e) {
      this.addLog('报警初始化失败: ' + e);
    }
    this.collectAll();
    this.refreshTimerId = setInterval(() => {
      this.collectAll(true);
    }, 1000);
    await this.updateWifiInfo();
  }

  aboutToDisappear(): void {
    if (this.refreshTimerId !== -1) {
      clearInterval(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
    this.stopAutoReport();
    this.tcpClient.release();
  }

  // ---- WiFi管理 ----

  async updateWifiInfo(): Promise<void> {
    if (WifiManagerHelper.isConnected()) {
      this.wifiStatus = '已连接';
      this.selectedWifi = await WifiManagerHelper.getCurrentWifi();
      this.localIP = WifiManagerHelper.getLocalIP();
    } else {
      this.wifiStatus = '未连接';
      this.localIP = '0.0.0.0';
    }
  }

  async scanWifiAction(): Promise<void> {
    this.isScanning = true;
    this.addLog('开始扫描WiFi...');

    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(getContext(this),
        ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']);
    } catch (err) {
      this.addLog('获取位置权限失败，请在设置中授予');
      this.isScanning = false;
      return;
    }

    const result: boolean = await WifiManagerHelper.scanWifi();
    if (result) {
      setTimeout(async () => {
        this.wifiList = await WifiManagerHelper.getWifiList();
        this.isScanning = false;
        this.addLog('扫描完成，找到 ' + this.wifiList.length + ' 个WiFi');
      }, 1500);
    } else {
      this.addLog('扫描失败');
      this.isScanning = false;
    }
  }

  async connectWifi(ssid: string, password: string): Promise<void> {
    this.isConnectingWifi = true;
    this.addLog('正在连接WiFi: ' + ssid);

    const result: boolean = await WifiManagerHelper.connectWifi(ssid, password);
    if (result) {
      this.wifiStatus = '已连接';
      this.selectedWifi = ssid;
      this.localIP = WifiManagerHelper.getLocalIP();
      this.addLog('WiFi连接成功');
      this.addLog('本机IP: ' + this.localIP);
      await WifiManagerHelper.scanWifi();
      setTimeout(async () => {
        this.wifiList = await WifiManagerHelper.getWifiList();
      }, 1500);
    } else {
      this.addLog('WiFi连接失败');
    }

    this.isConnectingWifi = false;
  }

  getSignalIcon(signalLevel: number): string {
    return '📶';
  }

  addLog(msg: string): void {
    const time: string = new Date().toLocaleTimeString();
    this.logMessages.push(`[${time}] ${msg}`);
    if (this.logMessages.length > 100) {
      this.logMessages.shift();
    }
  }

  // ---- TCP连接管理 ----

  async connectServer(): Promise<void> {
    if (this.serverHost.trim() === '') {
      this.addLog('请输入服务器地址');
      return;
    }
    const port: number = parseInt(this.serverPort) || 80;
    this.isConnecting = true;
    this.tcpStatus = '连接中...';
    this.addLog('正在连接 ' + this.serverHost + ':' + port);

    this.tcpClient.onConnectCallback = () => {
      this.tcpStatus = '已连接';
      this.addLog('服务器连接成功');
      this.isConnecting = false;
    };

    this.tcpClient.onCloseCallback = () => {
      this.tcpStatus = '已断开';
      this.addLog('服务器连接已断开');
      this.stopAutoReport();
    };

    this.tcpClient.onErrorCallback = (err: string) => {
      this.addLog('连接错误: ' + err);
      this.tcpStatus = '连接失败';
      this.isConnecting = false;
    };

    this.tcpClient.onMessageCallback = (msg: string) => {
      this.handleServerCommand(msg);
    };

    await this.tcpClient.connectServer(this.serverHost, port);
  }

  disconnectServer(): void {
    this.stopAutoReport();
    this.tcpClient.closeTCPClient();
    this.addLog('已断开服务器');
  }

  // ---- 服务器命令处理 ----

  handleServerCommand(msg: string): void {
    this.addLog('收到命令: ' + msg.substring(0, 80));
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
        this.addLog('采集完成: ' + this.temp + '°C ' + this.humi + '% 烟雾=' + this.smoke + ' 红外=' + this.ir);
      }
    } catch (e) {
      this.sensorError = '采集失败: ' + e;
      if (!silent) {
        this.addLog('采集失败: ' + e);
      }
    }
    this.isCollecting = false;
  }

  // ---- 自动上报 ----

  toggleAutoReport(): void {
    if (this.autoReport) {
      this.stopAutoReport();
    } else {
      this.startAutoReport();
    }
  }

  startAutoReport(): void {
    if (this.tcpStatus !== '已连接') {
      this.addLog('请先连接服务器');
      return;
    }
    this.autoReport = true;
    this.addLog('自动上报已开启，间隔 ' + this.reportInterval + ' 秒');
    this.runReportCycle();
  }

  stopAutoReport(): void {
    this.autoReport = false;
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.addLog('自动上报已停止');
  }

  async runReportCycle(): Promise<void> {
    if (!this.autoReport) return;

    try {
      const data: SensorData = await SensorManager.getAllData();
      this.temp = data.temp.toFixed(1);
      this.humi = data.humi.toFixed(1);
      this.smoke = data.smoke.toFixed(2);

      const payload: string = JSON.stringify({
        type: 'report',
        temp: data.temp.toFixed(1),
        humi: data.humi.toFixed(1),
        smoke: data.smoke,
        ir: data.ir,
        alarm: this.getAlarmValue()
      });
      await this.tcpClient.sendMessage(payload);
      this.addLog('上报: ' + payload);
    } catch (e) {
      this.addLog('上报失败: ' + e);
    }

    if (this.autoReport) {
      this.timerId = setTimeout(() => {
        this.runReportCycle();
      }, this.reportInterval * 1000);
    }
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
      this.addLog('报警状态: ' + this.alarmMode + (reason !== '' ? ' (' + reason + ')' : ''));
    }
  }

  // ---- 报警控制 ----

  async setAlarmMode(mode: number): Promise<void> {
    try {
      await SensorManager.setAlarmMode(mode);
      const labels: string[] = ['正常', '警告', '报警'];
      this.alarmMode = labels[mode] || '未知';
      this.alarmLog = '已设为' + this.alarmMode;
      this.addLog('报警已设为: ' + this.alarmMode);
    } catch (e) {
      this.addLog('报警设置失败: ' + e);
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
            Text(this.localIP !== '0.0.0.0' ? 'IP: ' + this.localIP : '')
              .fontSize(12)
              .fontColor('#007DFF')
          }
          .width('100%')
          .margin({ top: 16, bottom: 4 })

          // ---- WiFi配置 ----
          Column({ space: 8 }) {
            Row() {
              Text('📶 WiFi配置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Button(this.isScanning ? '扫描中...' : '扫描WiFi')
                .height(28)
                .fontSize(12)
                .enabled(!this.isScanning)
                .onClick(() => { this.scanWifiAction(); })
            }

            Row({ space: 10 }) {
              Text('状态:')
                .fontSize(14)
              Text(this.wifiStatus)
                .fontSize(14)
                .fontColor(this.wifiStatus === '已连接' ? '#00AA00' : '#FF6600')
              Text('IP:')
                .fontSize(14)
              Text(this.localIP)
                .fontSize(14)
                .fontColor('#007DFF')
            }

            if (this.selectedWifi !== '') {
              Row() {
                Text('当前: ' + this.selectedWifi)
                  .fontSize(14)
                  .fontColor('#333333')
              }
            }

            if (this.wifiList.length > 0) {
              Column() {
                Text('可用WiFi:')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .align(Alignment.Start)
                  .width('100%')

                List({ space: 5 }) {
                  ForEach(this.wifiList, (item: WifiDeviceInfo) => {
                    ListItem() {
                      Row({ space: 10 }) {
                        Text(this.getSignalIcon(item.signalLevel))
                          .fontSize(16)
                        Text(item.ssid)
                          .fontSize(14)
                          .flexGrow(1)
                        if (item.isConnect) {
                          Text('✓')
                            .fontSize(14)
                            .fontColor('#00AA00')
                        }
                        Button('连接')
                          .height(25)
                          .fontSize(10)
                          .onClick(() => {
                            this.selectedWifi = item.ssid;
                            this.passwordInput = '';
                            if (item.securityType !== 0) {
                              this.showPasswordDialog = true;
                            } else {
                              this.connectWifi(item.ssid, '');
                            }
                          })
                      }
                      .padding({ left: 10, right: 10 })
                    }
                  })
                }
                .height(150)
                .width('100%')
                .backgroundColor('#F5F5F5')
                .borderRadius(8)
              }
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF8E1')
          .borderRadius(10)

          // ---- 服务器连接 ----
          Column({ space: 8 }) {
            Text('📡 服务器连接')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)

            Row({ space: 8 }) {
              TextInput({ text: this.serverHost, placeholder: '服务器地址' })
                .layoutWeight(1)
                .height(36)
                .fontSize(14)
                .onChange((v: string) => { this.serverHost = v; })

              TextInput({ text: this.serverPort, placeholder: '端口' })
                .width(70)
                .height(36)
                .fontSize(14)
                .onChange((v: string) => { this.serverPort = v; })
            }

            Row({ space: 8 }) {
              if (this.tcpStatus === '已连接') {
                Button('断开')
                  .height(32)
                  .fontSize(13)
                  .onClick(() => { this.disconnectServer(); })
              } else {
                Button(this.isConnecting ? '连接中...' : '连接')
                  .height(32)
                  .fontSize(13)
                  .enabled(!this.isConnecting && this.wifiStatus === '已连接')
                  .onClick(() => { this.connectServer(); })
              }

              Text('状态: ')
                .fontSize(14)
              Text(this.tcpStatus)
                .fontSize(14)
                .fontColor(this.tcpStatus === '已连接' ? '#00AA00' :
                  this.tcpStatus === '连接中...' ? '#FF6600' : '#999999')
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5F8FF')
          .borderRadius(10)

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

          // ---- 自动上报 ----
          Column({ space: 8 }) {
            Row() {
              Text('⚙ 自动上报')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Button(this.autoReport ? '停止' : '开始')
                .height(28)
                .fontSize(12)
                .fontColor(this.autoReport ? '#E74C3C' : '#FFFFFF')
                .backgroundColor(this.autoReport ? '#FFE0E0' : '#007DFF')
                .onClick(() => { this.toggleAutoReport(); })
            }
            .width('100%')

            Row({ space: 8 }) {
              Text('间隔:')
                .fontSize(14)
              TextInput({ text: this.reportInterval.toString(), placeholder: '秒' })
                .width(60)
                .height(32)
                .fontSize(14)
                .enabled(!this.autoReport)
                .onChange((v: string) => {
                  const n: number = parseInt(v);
                  if (n > 0) this.reportInterval = n;
                })
              Text('秒')
                .fontSize(14)
              Blank()
              Text(this.autoReport ? '● 运行中' : '○ 已停止')
                .fontSize(13)
                .fontColor(this.autoReport ? '#00AA00' : '#999999')
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFFBF0')
          .borderRadius(10)

          // ---- 报警控制 ----
          Column({ space: 8 }) {
            Text('🚨 报警控制')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)

            Row({ space: 10 }) {
              Button('正常模式')
                .height(36)
                .fontSize(13)
                .backgroundColor('#2ECC71')
                .onClick(() => { this.setAlarmMode(0); })

              Button('警告模式')
                .height(36)
                .fontSize(13)
                .backgroundColor('#F39C12')
                .onClick(() => { this.setAlarmMode(1); })

              Button('报警模式')
                .height(36)
                .fontSize(13)
                .backgroundColor('#E74C3C')
                .onClick(() => { this.setAlarmMode(2); })
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
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#FFF0F0')
          .borderRadius(10)

          // ---- 日志 ----
          Column() {
            Row() {
              Text('📝 日志')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
              Blank()
              Button('清空')
                .height(24)
                .fontSize(11)
                .onClick(() => { this.logMessages = []; })
            }
            .width('100%')

            List({ space: 3 }) {
              ForEach(this.logMessages, (item: string) => {
                ListItem() {
                  Text(item)
                    .fontSize(12)
                    .fontColor('#333333')
                    .align(Alignment.Start)
                    .width('100%')
                    .padding({ left: 6, right: 6 })
                }
              })
            }
            .width('100%')
            .height(140)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .padding(8)
            .border({ width: 1, color: '#DDDDDD' })
          }
          .width('100%')
          .margin({ top: 4, bottom: 20 })
        }
        .width('100%')
        .padding({ left: 12, right: 12 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)

      // WiFi密码输入对话框
      if (this.showPasswordDialog) {
        Column() {
          Column({ space: 15 }) {
            Text('输入WiFi密码')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)

            Text('SSID: ' + this.selectedWifi)
              .fontSize(14)
              .fontColor('#666666')

            TextInput({
              placeholder: '请输入密码',
              text: this.passwordInput
            })
              .width('90%')
              .height(40)
              .fontSize(14)
              .type(InputType.Password)
              .onChange((v: string) => {
                this.passwordInput = v;
              })

            Row({ space: 20 }) {
              Button('取消')
                .width('40%')
                .onClick(() => {
                  this.showPasswordDialog = false;
                  this.passwordInput = '';
                })

              Button('连接')
                .width('40%')
                .onClick(() => {
                  this.showPasswordDialog = false;
                  this.connectWifi(this.selectedWifi, this.passwordInput);
                  this.passwordInput = '';
                })
            }
          }
          .width('80%')
          .padding(20)
          .backgroundColor('#FFFFFF')
          .borderRadius(15)
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#88000000')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.showPasswordDialog = false;
          this.passwordInput = '';
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
