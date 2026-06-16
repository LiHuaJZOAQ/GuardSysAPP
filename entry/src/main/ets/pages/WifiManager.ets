import wifiManager from '@ohos.wifiManager';
import deviceInfo from '@ohos.deviceInfo';

// WiFi设备信息接口
export interface WifiDeviceInfo {
  ssid: string;
  bssid: string;
  signalLevel: number;
  securityType: number;
  isConnect: boolean;
}

export class WifiManagerHelper {
  // 扫描WiFi列表
  static async scanWifi(): Promise<boolean> {
    try {
      await wifiManager.scan();
      return true;
    } catch (err) {
      console.error('scanWifi failed: ' + JSON.stringify(err));
      return false;
    }
  }

  // 获取WiFi扫描结果
  static async getWifiList(): Promise<WifiDeviceInfo[]> {
    try {
      const wifiList: Array<wifiManager.WifiScanInfo> = wifiManager.getScanInfoList();
      const result: WifiDeviceInfo[] = [];
      const ssidMap: Map<string, WifiDeviceInfo> = new Map<string, WifiDeviceInfo>();

      // 获取当前连接的SSID
      let currentSSID: string = '';
      try {
        const linkedInfo: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
        currentSSID = linkedInfo.ssid;
      } catch (e) {
        // not connected
      }

      for (let i: number = 0; i < wifiList.length; i++) {
        const info: wifiManager.WifiScanInfo = wifiList[i];
        const ssid: string = info.ssid;

        if (!ssid || ssid === '') continue;

        // 将rssi转换为0-100的信号等级
        const signalLevel: number = Math.min(100, Math.max(0, (info.rssi + 100) * 100 / 70));

        const deviceInfo: WifiDeviceInfo = {
          ssid: ssid,
          bssid: info.bssid,
          signalLevel: signalLevel,
          securityType: info.securityType,
          isConnect: ssid === currentSSID
        };

        if (ssidMap.has(ssid)) {
          const existing: WifiDeviceInfo = ssidMap.get(ssid)!;
          if (deviceInfo.signalLevel > existing.signalLevel) {
            ssidMap.set(ssid, deviceInfo);
          }
        } else {
          ssidMap.set(ssid, deviceInfo);
        }
      }

      ssidMap.forEach((value: WifiDeviceInfo) => {
        result.push(value);
      });

      result.sort((a: WifiDeviceInfo, b: WifiDeviceInfo) => b.signalLevel - a.signalLevel);

      return result;
    } catch (e) {
      console.error('getWifiList failed: ' + JSON.stringify(e));
      return [];
    }
  }

  // 连接WiFi
  static async connectWifi(ssid: string, password: string): Promise<boolean> {
    try {
      const config: wifiManager.WifiDeviceConfig = {
        ssid: ssid,
        preSharedKey: password,
        securityType: wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK
      };

      const networkId: number = await wifiManager.addCandidateConfig(config);
      if (networkId < 0) {
        return false;
      }

      wifiManager.connectToCandidateConfig(networkId);

      await new Promise<boolean>((resolve) => {
        setTimeout(() => {
          const isConnected: boolean = wifiManager.isConnected();
          resolve(isConnected);
        }, 3000);
      });

      return wifiManager.isConnected();
    } catch (err) {
      console.error('connectWifi failed: ' + JSON.stringify(err));
      return false;
    }
  }

  // 断开WiFi
  static async disconnectWifi(): Promise<boolean> {
    try {
      const isConnected: boolean = wifiManager.isConnected();
      if (!isConnected) {
        return true;
      }
      // API 10 没有直接的disconnect方法，使用removeDevice替代
      return false;
    } catch (err) {
      console.error('disconnectWifi failed: ' + JSON.stringify(err));
      return false;
    }
  }

  // 获取当前连接的WiFi信息
  static async getCurrentWifi(): Promise<string> {
    try {
      const linkedInfo: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
      return linkedInfo.ssid;
    } catch (e) {
      return '';
    }
  }

  // 检查WiFi是否已连接
  static isConnected(): boolean {
    try {
      return wifiManager.isConnected();
    } catch (e) {
      return false;
    }
  }

  // 获取本机IP地址
  static getLocalIP(): string {
    try {
      const ipAddress: number = wifiManager.getIpInfo().ipAddress;
      const localIP: string =
        (ipAddress >>> 24) + "." +
          ((ipAddress >> 16) & 0xFF) + "." +
          ((ipAddress >> 8) & 0xFF) + "." +
          (ipAddress & 0xFF);
      return localIP;
    } catch (e) {
      return '0.0.0.0';
    }
  }

  // 获取设备唯一标识（序列号，用于设备 ID）
  static async getDeviceMac(): Promise<string> {
    try {
      const serial: string = deviceInfo.serial;
      if (serial && serial !== '') {
        return serial;
      }
    } catch (e) {
      console.error('deviceInfo.serial failed: ' + JSON.stringify(e));
    }
    // fallback: 使用WiFi MAC地址
    try {
      const info: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
      if (info.macAddress && info.macAddress !== '') {
        return info.macAddress;
      }
    } catch (e) {
      console.error('getLinkedInfo.macAddress failed: ' + JSON.stringify(e));
    }
    return '';
  }

  // 获取当前 WiFi 信号强度 RSSI
  static async getRssi(): Promise<number> {
    try {
      const info: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
      return info.rssi;
    } catch (e) {
      console.error('getRssi failed: ' + JSON.stringify(e));
      return 0;
    }
  }
}
