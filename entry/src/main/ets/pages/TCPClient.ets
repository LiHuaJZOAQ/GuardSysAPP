import socket from '@ohos.net.socket';
import wifiManager from '@ohos.wifiManager';

export interface SocketInfo {
  message: ArrayBuffer;
  remoteInfo: socket.SocketRemoteInfo;
}

export class TCPClient {
  private tcpClient: socket.TCPSocket | undefined = undefined;
  private isConnect: boolean = false;
  private shouldReconnect: boolean = false;
  private remoteHost: string = '';
  private remotePort: number = 0;
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;

  public onConnectCallback?: () => void;
  public onMessageCallback?: (message: string) => void;
  public onCloseCallback?: () => void;
  public onErrorCallback?: (error: string) => void;

  constructor() {
    if (this.tcpClient === undefined) {
      this.tcpClient = socket.constructTCPSocketInstance();
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnect) {
        const ping: string = JSON.stringify({ type: 'ping' }) + '\n';
        let opt: socket.TCPSendOptions = { data: ping } as socket.TCPSendOptions;
        this.tcpClient?.send(opt);
        console.info('heartbeat sent');
      }
    }, 30000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  private stopReconnect(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  private scheduleReconnect(): void {
    this.stopReconnect();
    this.reconnectTimer = setTimeout(() => {
      console.info('auto reconnect to ' + this.remoteHost + ':' + this.remotePort);
      this.connectServer(this.remoteHost, this.remotePort);
    }, 5000);
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

    this.remoteHost = remoteHost;
    this.remotePort = remotePort;
    this.shouldReconnect = true;

    if (this.isConnect) {
      this.closeTCPClient();
    }

    let ipAddress: number = wifiManager.getIpInfo().ipAddress;
    let localIPAddress: string =
      (ipAddress >>> 24) + "." +
        ((ipAddress >> 16) & 0xFF) + "." +
        ((ipAddress >> 8) & 0xFF) + "." +
        (ipAddress & 0xFF);

    console.info('Local IP: ' + localIPAddress);

    let netAddress: socket.NetAddress = {
      address: localIPAddress,
      port: 0,
      family: 1
    } as socket.NetAddress;

    try {
      await this.tcpClient.bind(netAddress);
      console.info('bind success');

      this.tcpClient.on('message', (value: SocketInfo) => {
        let buffer: ArrayBuffer = value.message;
        let dataView: DataView = new DataView(buffer);
        let str: string = "";
        for (let i: number = 0; i < dataView.byteLength; ++i) {
          str += String.fromCharCode(dataView.getUint8(i));
        }
        if (str.endsWith('\n')) {
          str = str.slice(0, -1);
        }
        console.info('received message: ' + str);
        if (this.onMessageCallback) {
          this.onMessageCallback(str);
        }
      });

      this.tcpClient.on('connect', () => {
        console.info('on connect');
        this.isConnect = true;
        this.startHeartbeat();
        if (this.onConnectCallback) {
          this.onConnectCallback();
        }
      });

      this.tcpClient.on('close', () => {
        console.info('on close');
        this.isConnect = false;
        this.stopHeartbeat();
        if (this.onCloseCallback) {
          this.onCloseCallback();
        }
        if (this.shouldReconnect && this.remoteHost !== '') {
          this.scheduleReconnect();
        }
      });

      this.tcpClient.on('error', (err: Error) => {
        console.error('socket error: ' + JSON.stringify(err));
        if (this.onErrorCallback) {
          this.onErrorCallback(JSON.stringify(err));
        }
      });

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

  // 发送消息（自动追加换行符）
  async sendMessage(message: string): Promise<void> {
    if (this.tcpClient === undefined || !this.isConnect) {
      const err: string = 'tcpClient is undefined or not connected';
      console.error(err);
      return;
    }

    let opt: socket.TCPSendOptions = {
      data: message + '\n'
    } as socket.TCPSendOptions;

    try {
      await this.tcpClient.send(opt);
      console.info('send success: ' + message);
    } catch (err) {
      console.error('send failed: ' + JSON.stringify(err));
    }
  }

  // 断开连接（主动断开时不自动重连）
  closeTCPClient(): void {
    this.shouldReconnect = false;
    this.stopHeartbeat();
    this.stopReconnect();
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

  isConnected(): boolean {
    return this.isConnect;
  }
}

export const defaultTcpClient: TCPClient = new TCPClient();
