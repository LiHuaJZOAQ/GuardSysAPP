import guardsys_napi from '@ohos.guardsys_napi';

export interface Sht30Data {
  temp: number;
  humi: number;
}

export interface Mq2Data {
  smoke: number;
}

export interface IrData {
  ir: boolean;
}

export interface SensorData {
  temp: number;
  humi: number;
  smoke: number;
  ir: boolean;
}

export class SensorManager {
  static currentAlarmMode: number = 0;

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

  static async getIrData(): Promise<IrData> {
    const res: IrData = await guardsys_napi.getIrStatus(9) as IrData;
    const result: IrData = { ir: !!res.ir };
    return result;
  }

  static async getAllData(): Promise<SensorData> {
    let temp: number = 0;
    let humi: number = 0;
    let smoke: number = 0;
    let ir: boolean = false;

    try {
      const sht30: Sht30Data = await SensorManager.getSht30Data();
      temp = sht30.temp;
      humi = sht30.humi;
    } catch (e) {
      console.error('getSht30Data failed: ' + JSON.stringify(e));
    }

    try {
      const mq2: Mq2Data = await SensorManager.getMq2Data();
      smoke = mq2.smoke;
    } catch (e) {
      console.error('getMq2Data failed: ' + JSON.stringify(e));
    }

    try {
      const irData: IrData = await SensorManager.getIrData();
      ir = irData.ir;
    } catch (e) {
      console.error('getIrData failed: ' + JSON.stringify(e));
    }

    const result: SensorData = { temp: temp, humi: humi, smoke: smoke, ir: ir };
    return result;
  }

  static async initAlarm(): Promise<void> {
    await guardsys_napi.setAlarmStatus(0, {
      buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383
    });
  }

  static async setAlarmMode(mode: number): Promise<void> {
    SensorManager.currentAlarmMode = mode;
    await guardsys_napi.setAlarmStatus(mode, {
      buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383
    });
  }
}
