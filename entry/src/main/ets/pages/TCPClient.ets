import webSocket from '@ohos.net.webSocket';

export class TCPClient {
  private ws: webSocket.WebSocket | undefined = undefined;
  private isConnect: boolean = false;
  private isConnecting: boolean = false;
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
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      if (this.isConnect) {
        this.ws?.send(JSON.stringify({ type: 'ping' }) + '\n');
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

  private createUrl(host: string, port: number): string {
    const protocol: string = port === 443 ? 'wss://' : 'ws://';
    const portPart: string = port !== 443 ? ':' + port : '';
    return protocol + host + portPart + '/device';
  }

  // 连接服务器（支持域名或IP）
  async connectServer(remoteHost: string, remotePort: number): Promise<void> {
    if (this.isConnecting) {
      if (this.onErrorCallback) {
        this.onErrorCallback('正在连接中，请勿重复点击（目标 ' + remoteHost + ':' + remotePort + '）');
      }
      return;
    }

    if (!remoteHost || remoteHost.trim() === '') {
      if (this.onErrorCallback) {
        this.onErrorCallback('服务器地址不能为空');
      }
      return;
    }
    if (remotePort <= 0 || remotePort > 65535) {
      if (this.onErrorCallback) {
        this.onErrorCallback('端口号无效（1-65535），当前值: ' + remotePort);
      }
      return;
    }

    // 清理旧连接
    this.shouldReconnect = false;
    this.stopHeartbeat();
    this.stopReconnect();
    this.closeWebSocket();

    this.remoteHost = remoteHost;
    this.remotePort = remotePort;
    this.shouldReconnect = true;
    this.isConnect = false;
    this.isConnecting = true;

    this.ws = webSocket.createWebSocket();

    this.ws.on('open', () => {
      console.info('ws open: ' + remoteHost + ':' + remotePort);
      this.isConnect = true;
      this.isConnecting = false;
      this.startHeartbeat();
      if (this.onConnectCallback) {
        this.onConnectCallback();
      }
    });

    this.ws.on('message', (err: Object, value: Object) => {
      let msg: string = '';
      if (typeof value === 'string') {
        msg = value as string;
      }
      if (this.onMessageCallback) {
        this.onMessageCallback(msg);
      }
    });

    this.ws.on('close', () => {
      console.info('ws close: ' + remoteHost + ':' + remotePort + ', was connected: ' + this.isConnect);
      this.isConnect = false;
      this.isConnecting = false;
      this.stopHeartbeat();
      if (this.onCloseCallback) {
        this.onCloseCallback();
      }
      if (this.shouldReconnect && this.remoteHost !== '') {
        this.scheduleReconnect();
      }
    });

    this.ws.on('error', (err: Error) => {
      console.error('ws error: ' + JSON.stringify(err) + ', target: ' + remoteHost + ':' + remotePort);
      this.isConnecting = false;
      if (this.onErrorCallback) {
        this.onErrorCallback(JSON.stringify(err));
      }
    });

    const url: string = this.createUrl(remoteHost, remotePort);
    console.info('Connecting to ' + url);
    try {
      await this.ws.connect(url);
      console.info('ws connect() resolved ok');
    } catch (e) {
      this.isConnecting = false;
      console.error('ws connect() failed: ' + JSON.stringify(e) + ', url=' + url);
      if (this.onErrorCallback) {
        this.onErrorCallback('WebSocket连接失败: ' + JSON.stringify(e) + '\nURL: ' + url);
      }
    }

    setTimeout(() => {
      if (this.isConnecting) {
        console.warn('ws watchdog: ' + remoteHost + ':' + remotePort + ' timeout 20s');
        this.isConnecting = false;
        this.isConnect = false;
        if (this.onErrorCallback) {
          this.onErrorCallback('连接超时：目标 ' + remoteHost + ':' + remotePort + ' 在20秒内无响应\n'
            + 'URL: ' + url + '\n'
            + '可能原因：\n'
            + '1. 服务器未启动\n'
            + '2. 地址/端口错误\n'
            + '3. 网络不通\n'
            + '4. 防火墙阻止');
        }
      }
    }, 20000);
  }

  private closeWebSocket(): void {
    if (this.ws === undefined) {
      return;
    }
    try {
      this.ws.off('open');
      this.ws.off('message');
      this.ws.off('close');
      this.ws.off('error');
      this.ws.close();
    } catch (e) {
      // ignore close error
    }
    this.ws = undefined;
  }

  // 发送消息
  async sendMessage(message: string): Promise<void> {
    if (this.ws === undefined || !this.isConnect) {
      const err: string = 'ws not connected';
      console.error(err);
      return;
    }
    try {
      await this.ws.send(message + '\n');
      console.info('ws send ok');
    } catch (err) {
      console.error('ws send failed: ' + JSON.stringify(err));
    }
  }

  // 断开连接
  async closeTCPClient(): Promise<void> {
    this.shouldReconnect = false;
    this.stopHeartbeat();
    this.stopReconnect();
    if (this.ws === undefined || !this.isConnect) {
      this.isConnecting = false;
      return;
    }
    try {
      await this.ws.close();
      console.info('ws close ok');
    } catch (err) {
      console.error('ws close failed: ' + JSON.stringify(err));
    }
    this.isConnect = false;
    this.isConnecting = false;
  }

  release(): void {
    this.shouldReconnect = false;
    this.stopHeartbeat();
    this.stopReconnect();
    this.closeWebSocket();
    this.isConnect = false;
    this.isConnecting = false;
    console.info('WebSocket Client released');
  }

  isConnected(): boolean {
    return this.isConnect;
  }
}

export const defaultTcpClient: TCPClient = new TCPClient();
