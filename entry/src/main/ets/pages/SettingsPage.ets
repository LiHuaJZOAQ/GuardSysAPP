import { SensorManager, SensorData } from './SensorManager';
import { defaultTcpClient } from './TCPClient';
import { WifiManagerHelper, WifiDeviceInfo } from './WifiManager';
import { LogStore } from './LogStore';
import { SharedConfig } from './SharedConfig';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import router from '@ohos.router';

@Entry
@Component
struct SettingsPage {
  @State serverHost: string = 'guardsysserver.up.railway.app';
  @State serverPort: string = '3001';
  @State tcpStatus: string = '未连接';
  @State isConnecting: boolean = false;

  @State wifiList: WifiDeviceInfo[] = [];
  @State selectedWifi: string = '';
  @State wifiStatus: string = '未连接';
  @State localIP: string = '0.0.0.0';
  @State isScanning: boolean = false;
  @State isConnectingWifi: boolean = false;
  @State showPasswordDialog: boolean = false;
  @State passwordInput: string = '';

  // 自动上报
  @State autoReport: boolean = true;
  @State reportInterval: number = 1;
  private timerId: number = -1;

  // 传感器刷新频率
  @State refreshIntervalSec: string = (SharedConfig.refreshInterval / 1000).toString();

  aboutToAppear(): void {
    this.updateStatus();
    this.updateWifiInfo();
    if (this.tcpStatus === '已连接') {
      this.startAutoReport();
    }
  }

  aboutToDisappear(): void {
    this.stopAutoReport();
  }

  updateStatus(): void {
    if (defaultTcpClient.isConnected()) {
      this.tcpStatus = '已连接';
    } else {
      this.tcpStatus = '未连接';
    }
  }

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

  goBack(): void {
    router.back();
  }

  // ---- TCP ----

  async connectServer(): Promise<void> {
    if (this.serverHost.trim() === '') {
      return;
    }
    const port: number = parseInt(this.serverPort) || 3001;
    this.isConnecting = true;
    this.tcpStatus = '连接中...';

    defaultTcpClient.onConnectCallback = () => {
      this.tcpStatus = '已连接';
      this.isConnecting = false;
      LogStore.add('服务器连接成功');
      if (this.autoReport) {
        this.startAutoReport();
      }
    };

    defaultTcpClient.onCloseCallback = () => {
      this.tcpStatus = '已断开';
      this.isConnecting = false;
      this.stopAutoReport();
      LogStore.add('服务器连接已断开', 'warn');
    };

    defaultTcpClient.onErrorCallback = (err: string) => {
      this.tcpStatus = '连接失败';
      this.isConnecting = false;
      LogStore.add('连接错误: ' + err, 'error');
    };

    await defaultTcpClient.connectServer(this.serverHost, port);
    this.updateStatus();
    this.isConnecting = false;
  }

  disconnectServer(): void {
    this.stopAutoReport();
    defaultTcpClient.closeTCPClient();
    this.tcpStatus = '未连接';
    LogStore.add('已断开服务器');
  }

  // ---- WiFi ----

  async scanWifiAction(): Promise<void> {
    this.isScanning = true;
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      await atManager.requestPermissionsFromUser(getContext(this),
        ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']);
    } catch (err) {
      this.isScanning = false;
      return;
    }

    const result: boolean = await WifiManagerHelper.scanWifi();
    if (result) {
      setTimeout(async () => {
        this.wifiList = await WifiManagerHelper.getWifiList();
        this.isScanning = false;
      }, 1500);
    } else {
      this.isScanning = false;
    }
  }

  async connectWifi(ssid: string, password: string): Promise<void> {
    this.isConnectingWifi = true;
    const result: boolean = await WifiManagerHelper.connectWifi(ssid, password);
    if (result) {
      this.wifiStatus = '已连接';
      this.selectedWifi = ssid;
      this.localIP = WifiManagerHelper.getLocalIP();
      await WifiManagerHelper.scanWifi();
      setTimeout(async () => {
        this.wifiList = await WifiManagerHelper.getWifiList();
      }, 1500);
    }
    this.isConnectingWifi = false;
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
    if (this.autoReport) return;
    if (this.tcpStatus !== '已连接') {
      LogStore.add('自动上报：服务器未连接', 'warn');
      return;
    }
    this.autoReport = true;
    LogStore.add('自动上报已开启，间隔 ' + this.reportInterval + ' 秒');
    this.runReportCycle();
  }

  stopAutoReport(): void {
    this.autoReport = false;
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    LogStore.add('自动上报已停止');
  }

  async runReportCycle(): Promise<void> {
    if (!this.autoReport) return;

    try {
      const data: SensorData = await SensorManager.getAllData();
      const payload: string = JSON.stringify({
        type: 'report',
        temp: data.temp.toFixed(1),
        humi: data.humi.toFixed(1),
        smoke: data.smoke,
        ir: data.ir,
        alarm: SensorManager.currentAlarmMode
      });
      await defaultTcpClient.sendMessage(payload);
    } catch (e) {
      LogStore.add('上报失败: ' + e, 'error');
    }

    if (this.autoReport) {
      this.timerId = setTimeout(() => {
        this.runReportCycle();
      }, this.reportInterval * 1000);
    }
  }

  // ---- 调试 ----

  async setAlarmMode(mode: number): Promise<void> {
    try {
      await SensorManager.setAlarmMode(mode);
      const labels: string[] = ['正常', '警告', '报警'];
      const logLevel: string = mode >= 2 ? 'error' : (mode >= 1 ? 'warn' : 'info');
      LogStore.add('报警手动设为: ' + (labels[mode] || '未知') + ' (调试)', logLevel);
    } catch (e) {
      LogStore.add('报警设置失败: ' + e, 'error');
    }
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 12 }) {
          // 标题栏
          Row() {
            Button('← 返回')
              .height(32)
              .fontSize(14)
              .onClick(() => { this.goBack(); })
            Blank()
            Text('设置')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
            Blank()
          }
          .width('100%')
          .margin({ top: 12, bottom: 4 })

          // ---- TCP服务器 ----
          Column({ space: 8 }) {
            Text('📡 服务器连接')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)

            Row({ space: 8 }) {
              TextInput({ text: this.serverHost, placeholder: '服务器地址' })
                .layoutWeight(1)
                .height(36)
                .fontSize(14)
                .enabled(!defaultTcpClient.isConnected())
                .onChange((v: string) => { this.serverHost = v; })

              TextInput({ text: this.serverPort, placeholder: '端口' })
                .width(70)
                .height(36)
                .fontSize(14)
                .enabled(!defaultTcpClient.isConnected())
                .onChange((v: string) => { this.serverPort = v; })
            }

            Row({ space: 8 }) {
              if (defaultTcpClient.isConnected()) {
                Button('断开')
                  .height(32)
                  .fontSize(13)
                  .onClick(() => { this.disconnectServer(); })
              } else {
                Button(this.isConnecting ? '连接中...' : '连接')
                  .height(32)
                  .fontSize(13)
                  .enabled(!this.isConnecting)
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
                        Text('📶')
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

          // ---- 传感器设置 ----
          Column({ space: 8 }) {
            Row() {
              Text('📟 传感器设置')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')

            Row({ space: 8 }) {
              Text('刷新间隔:')
                .fontSize(14)
              TextInput({ text: this.refreshIntervalSec, placeholder: '秒' })
                .width(60)
                .height(32)
                .fontSize(14)
                .onChange((v: string) => {
                  const n: number = parseInt(v);
                  if (n > 0) {
                    this.refreshIntervalSec = n.toString();
                    SharedConfig.refreshInterval = n * 1000;
                    LogStore.add('传感器刷新间隔设为 ' + n + ' 秒');
                  }
                })
              Text('秒')
                .fontSize(14)
              Blank()
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F5FFF5')
          .borderRadius(10)

          // ---- 调试 ----
          Column({ space: 8 }) {
            Row() {
              Text('🔧 调试')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
            }
            .width('100%')

            Text('报警控制')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#555555')

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
          }
          .width('100%')
          .padding(12)
          .backgroundColor('#F0F0FF')
          .borderRadius(10)
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
