import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';

// Socket信息接口
export interface SocketInfo {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

export class TCPClient {
  private tcpClient: socket.TCPSocket | undefined = undefined;
  private isConnect: boolean = false;

  // 回调函数
  public onConnectCallback?: () => void;
  public onMessageCallback?: (message: string) => void;
  public onCloseCallback?: () => void;
  public onErrorCallback?: (error: string) => void;

  constructor() {
    if (this.tcpClient === undefined) {
      this.tcpClient = socket.constructTCPSocketInstance();
    }
  }

  // 连接服务器（支持域名或IP）
  async connectServer(remoteHost: string, remotePort: number): Promise<void> {
    if (this.tcpClient === undefined) {
      const err: string = 'tcpClient is undefined';
      console.error(err);
      if (this.onErrorCallback) {
        this.onErrorCallback(err);
      }
      return;
    }

    if (this.isConnect) {
      this.closeTCPClient();
    }

    // 获取本机IP地址
    let ipAddress: number = wifiManager.getIpInfo().ipAddress;
    let localIPAddress: string =
      (ipAddress >>> 24) + "." +
        ((ipAddress >> 16) & 0xFF) + "." +
        ((ipAddress >> 8) & 0xFF) + "." +
        (ipAddress & 0xFF);

    console.info('Local IP: ' + localIPAddress);

    // 绑定本地IP地址和端口
    let netAddress: socket.NetAddress = {
      address: localIPAddress,
      port: 0,
      family: 1
    } as socket.NetAddress;

    try {
      // 绑定本机IP地址
      await this.tcpClient.bind(netAddress);
      console.info('bind success');

      // 先注册事件回调，再发起连接（避免错过连接成功事件）
      this.tcpClient.on('message', (value: SocketInfo) => {
        let buffer: ArrayBuffer = value.message;
        let dataView: DataView = new DataView(buffer);
        let str: string = "";
        for (let i: number = 0; i < dataView.byteLength; ++i) {
          str += String.fromCharCode(dataView.getUint8(i));
        }
        console.info('received message: ' + str);
        if (this.onMessageCallback) {
          this.onMessageCallback(str);
        }
      });

      this.tcpClient.on('connect', () => {
        console.info('on connect');
        this.isConnect = true;
        if (this.onConnectCallback) {
          this.onConnectCallback();
        }
      });

      this.tcpClient.on('close', () => {
        console.info('on close');
        this.isConnect = false;
        if (this.onCloseCallback) {
          this.onCloseCallback();
        }
      });

      this.tcpClient.on('error', (err: Error) => {
        console.error('socket error: ' + JSON.stringify(err));
        if (this.onErrorCallback) {
          this.onErrorCallback(JSON.stringify(err));
        }
      });

      // 发起连接
      let connectAddress: socket.NetAddress = {
        address: remoteHost,
        port: remotePort
      } as socket.NetAddress;

      let tcpConnect: socket.TCPConnectOptions = {
        address: connectAddress,
        timeout: 10000
      } as socket.TCPConnectOptions;

      console.info('Connecting to ' + remoteHost + ':' + remotePort);
      await this.tcpClient.connect(tcpConnect);
      console.info('connect success to ' + remoteHost + ':' + remotePort);

    } catch (e) {
      console.error('connect failed: ' + JSON.stringify(e));
      if (this.onErrorCallback) {
        this.onErrorCallback(JSON.stringify(e));
      }
    }
  }

  // 发送消息
  async sendMessage(message: string | ArrayBuffer): Promise<void> {
    if (this.tcpClient === undefined || !this.isConnect) {
      const err: string = 'tcpClient is undefined or not connected';
      console.error(err);
      return;
    }

    let opt: socket.TCPSendOptions = {
      data: message
    } as socket.TCPSendOptions;

    try {
      await this.tcpClient.send(opt);
      console.info('send success: ' + message);
    } catch (err) {
      console.error('send failed: ' + JSON.stringify(err));
    }
  }

  // 断开连接
  closeTCPClient(): void {
    if (this.tcpClient === undefined || !this.isConnect) {
      return;
    }

    this.tcpClient.close().then(() => {
      console.info('close success');
    }).catch((err: Error) => {
      console.error('close failed: ' + JSON.stringify(err));
    });

    this.tcpClient.off('message');
    this.tcpClient.off('close');
    this.tcpClient.off('connect');
    this.tcpClient.off('error');
    this.isConnect = false;
  }

  // 释放资源
  release(): void {
    this.closeTCPClient();
    this.tcpClient = undefined;
    console.info('TCP Client released');
  }

  // 获取连接状态
  isConnected(): boolean {
    return this.isConnect;
  }
}