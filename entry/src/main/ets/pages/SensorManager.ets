import guardsys_napi from '@ohos.guardsys_napi';

export interface Sht30Data {
  temp: number;
  humi: number;
}

export interface Mq2Data {
  smoke: number;
}

export interface SensorData {
  temp: number;
  humi: number;
  smoke: number;
}

export class SensorManager {
  static async getSht30Data(): Promise<Sht30Data> {
    const res: Sht30Data = await guardsys_napi.getSht30Data(5, 0x44) as Sht30Data;
    const result: Sht30Data = { temp: res.temp, humi: res.humi };
    return result;
  }

  static async getMq2Data(): Promise<Mq2Data> {
    const res: Mq2Data = await guardsys_napi.getMq2Data(1) as Mq2Data;
    const result: Mq2Data = { smoke: res.smoke };
    return result;
  }

  static async getAllData(): Promise<SensorData> {
    const sht30: Sht30Data = await SensorManager.getSht30Data();
    const mq2: Mq2Data = await SensorManager.getMq2Data();
    const result: SensorData = { temp: sht30.temp, humi: sht30.humi, smoke: mq2.smoke };
    return result;
  }

  static async setAlarmMode(mode: number): Promise<void> {
    await guardsys_napi.setAlarmStatus(mode, {
      buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383
    });
  }
}
