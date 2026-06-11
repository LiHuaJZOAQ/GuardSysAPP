import { TCPClient } from './TCPClient';
import { WifiManagerHelper, WifiDeviceInfo } from './WifiManager';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';

@Entry
@Component
struct Index {
  private tcpClient: TCPClient = new TCPClient();

  // WiFi相关状态
  @State wifiList: WifiDeviceInfo[] = [];
  @State selectedWifi: string = '';
  @State wifiPassword: string = '';
  @State wifiStatus: string = '未连接';
  @State localIP: string = '0.0.0.0';
  @State isScanning: boolean = false;
  @State isConnectingWifi: boolean = false;

  // TCP相关状态
  @State remoteHost: string = 'www.example.com';
  @State remotePort: string = '80';
  @State tcpStatus: string = '未连接';
  @State sendMsg: string = 'GET / HTTP/1.1\r\nHost: www.example.com\r\nConnection: close\r\n\r\n';
  @State logMessages: string[] = [];
  @State isConnectingTcp: boolean = false;
  @State showPasswordDialog: boolean = false;
  @State passwordInput: string = '';

  async aboutToAppear(): Promise<void> {
    this.addLog('应用启动');

    this.tcpClient.onConnectCallback = () => {
      this.tcpStatus = '已连接';
      this.addLog('[TCP] 连接成功');
      this.isConnectingTcp = false;
    };

    this.tcpClient.onMessageCallback = (msg: string) => {
      this.addLog('[TCP] 收到: ' + msg);
    };

    this.tcpClient.onCloseCallback = () => {
      this.tcpStatus = '已断开';
      this.addLog('[TCP] 连接已断开');
    };

    this.tcpClient.onErrorCallback = (err: string) => {
      this.addLog('[TCP] 错误: ' + err);
      this.isConnectingTcp = false;
    };

    await this.updateWifiStatus();
  }

  aboutToDisappear(): void {
    this.tcpClient.release();
  }

  async updateWifiStatus(): Promise<void> {
    if (WifiManagerHelper.isConnected()) {
      this.wifiStatus = '已连接';
      this.selectedWifi = await WifiManagerHelper.getCurrentWifi();
      this.localIP = WifiManagerHelper.getLocalIP();
      this.addLog('WiFi已连接: ' + this.selectedWifi);
      this.addLog('本机IP: ' + this.localIP);
    } else {
      this.wifiStatus = '未连接';
      this.localIP = '0.0.0.0';
    }
  }

  addLog(msg: string): void {
    const time: string = new Date().toLocaleTimeString();
    this.logMessages.push(`[${time}] ${msg}`);
    if (this.logMessages.length > 100) {
      this.logMessages.shift();
    }
  }

  getSignalIcon(signalLevel: number): string {
    if (signalLevel >= 75) return '📶';
    if (signalLevel >= 50) return '📶';
    if (signalLevel >= 25) return '📶';
    return '📶';
  }

  build() {
    Stack() {
      Scroll() {
        Column({ space: 10 }) {
        // 标题
        Text('TCP通信测试 - 域名连接')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20, bottom: 10 })

        // WiFi配置区域
        Column({ space: 10 }) {
          Row() {
            Text('=== WiFi配置 ===')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
            Blank()
            Button(this.isScanning ? '扫描中...' : '扫描WiFi')
              .height(30)
              .fontSize(12)
              .enabled(!this.isScanning)
              .onClick(async () => {
                this.isScanning = true;
                this.addLog('开始扫描WiFi...');

                // 请求位置权限（user_grant权限需要运行时申请）
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
              })
          }

          // WiFi状态显示
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

          // 当前连接
          if (this.selectedWifi !== '') {
            Row() {
              Text('当前: ' + this.selectedWifi)
                .fontSize(14)
                .fontColor('#333333')
            }
          }

          // WiFi列表
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
        .width('95%')
        .padding(15)
        .backgroundColor('#FFF8E1')
        .borderRadius(10)

        // TCP配置区域
        Column({ space: 10 }) {
          Text('=== TCP客户端 ===')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)

          // 域名/IP输入
          Row({ space: 10 }) {
            Text('域名/IP:')
              .fontSize(14)
              .width(60)
            TextInput({ text: this.remoteHost, placeholder: '输入域名或IP' })
              .flexGrow(1)
              .height(35)
              .fontSize(14)
              .onChange((value: string) => {
                this.remoteHost = value;
              })
          }

          // 端口输入
          Row({ space: 10 }) {
            Text('端口:')
              .fontSize(14)
              .width(60)
            TextInput({ text: this.remotePort, placeholder: '端口号' })
              .width(80)
              .height(35)
              .fontSize(14)
              .onChange((value: string) => {
                this.remotePort = value;
              })
            Blank()
            Text('状态: ' + this.tcpStatus)
              .fontSize(14)
              .fontColor(this.tcpStatus === '已连接' ? '#00AA00' : '#999999')
          }

          // 连接按钮
          Row({ space: 10 }) {
            Button(this.isConnectingTcp ? '连接中...' : 'ConnectServer')
              .width('48%')
              .height(40)
              .enabled(!this.isConnectingTcp && this.wifiStatus === '已连接')
              .onClick(async () => {
                if (this.remoteHost.trim() === '') {
                  this.addLog('请输入域名或IP');
                  return;
                }
                const port: number = parseInt(this.remotePort) || 80;
                this.isConnectingTcp = true;
                this.tcpStatus = '连接中...';
                this.addLog('正在连接 ' + this.remoteHost + ':' + port);
                await this.tcpClient.connectServer(this.remoteHost, port);
              })

            Button('Disconnect')
              .width('48%')
              .height(40)
              .onClick(() => {
                this.tcpClient.closeTCPClient();
                this.addLog('已断开连接');
              })
          }
        }
        .width('95%')
        .padding(15)
        .backgroundColor('#E3F2FD')
        .borderRadius(10)

        // 发送消息区域
        Column({ space: 10 }) {
          TextInput({ text: this.sendMsg, placeholder: '输入消息' })
            .width('100%')
            .height(60)
            .fontSize(14)
            .onChange((value: string) => {
              this.sendMsg = value;
            })

          Row({ space: 10 }) {
            Button('SendMessage')
              .width('100%')
              .height(40)
              .enabled(this.tcpStatus === '已连接')
              .onClick(async () => {
                if (this.sendMsg.trim() === '') {
                  this.addLog('消息不能为空');
                  return;
                }
                await this.tcpClient.sendMessage(this.sendMsg);
                this.addLog('[发送] ' + this.sendMsg.substring(0, 50) + '...');
              })
          }
        }
        .width('95%')

        // 日志区域
        Column() {
          Row() {
            Text('日志输出')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
            Blank()
            Button('清空')
              .height(25)
              .fontSize(10)
              .onClick(() => {
                this.logMessages = [];
              })
          }
          .width('100%')

          List({ space: 5 }) {
            ForEach(this.logMessages, (item: string) => {
              ListItem() {
                Text(item)
                  .fontSize(12)
                  .fontColor('#333333')
                  .align(Alignment.Start)
                  .width('100%')
                  .padding({ left: 5, right: 5 })
              }
            })
          }
          .width('95%')
          .height(150)
          .backgroundColor('#FFFFFF')
          .borderRadius(8)
          .padding(10)
          .border({ width: 1, color: '#CCCCCC' })
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .padding(10)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')

      // WiFi密码输入对话框 - 覆盖层
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
              .onChange((value: string) => {
                this.passwordInput = value;
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
  }

  // 连接WiFi
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
      // 刷新WiFi列表
      await WifiManagerHelper.scanWifi();
      setTimeout(async () => {
        this.wifiList = await WifiManagerHelper.getWifiList();
      }, 1500);
    } else {
      this.addLog('WiFi连接失败');
    }

    this.isConnectingWifi = false;
  }
}
