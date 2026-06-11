import guardsys_napi from '@ohos.guardsys_napi';
import promptAction from '@ohos.promptAction';

@Entry
@Component
struct TestPage {
  @State temp: string = '--';
  @State humi: string = '--';
  @State ir: string = '--';
  @State smoke: string = '--';
  @State alarmResult: string = '--';

  async getSht30() {
    try {
      let res = await guardsys_napi.getSht30Data(5, 0x44);
      this.temp = res.temp.toFixed(1);
      this.humi = res.humi.toFixed(1);
      promptAction.showToast({ message: 'SHT30 ok' });
    } catch (e) {
      promptAction.showToast({ message: 'SHT30 fail: ' + e });
    }
  }

  async getIr() {
    try {
      let res = await guardsys_napi.getIrStatus(9);
      this.ir = res.ir ? '有人' : '无人';
      promptAction.showToast({ message: 'IR ok' });
    } catch (e) {
      promptAction.showToast({ message: 'IR fail: ' + e });
    }
  }

  async getMq2() {
    try {
      let res = await guardsys_napi.getMq2Data(1);
      this.smoke = res.smoke.toString();
      promptAction.showToast({ message: 'MQ2 ok' });
    } catch (e) {
      promptAction.showToast({ message: 'MQ2 fail: ' + e });
    }
  }

  async setAlarmNormal() {
    try {
      await guardsys_napi.setAlarmStatus(0, { buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383 });
      this.alarmResult = '正常模式已设';
      promptAction.showToast({ message: '报警设置为正常' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败: ' + e });
    }
  }

  async setAlarmWarn() {
    try {
      await guardsys_napi.setAlarmStatus(1, { buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383 });
      this.alarmResult = '警告模式已设';
      promptAction.showToast({ message: '报警设置为警告' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败: ' + e });
    }
  }

  async setAlarmAlert() {
    try {
      await guardsys_napi.setAlarmStatus(2, { buzzerPin: 384, rPin: 381, gPin: 382, bPin: 383 });
      this.alarmResult = '报警模式已设';
      promptAction.showToast({ message: '报警设置为报警' });
    } catch (e) {
      promptAction.showToast({ message: '设置失败: ' + e });
    }
  }

  build() {
    Scroll() {
      Column({ space: 15 }) {
        Text('NAPI 接口测试').fontSize(24).margin({ top: 20 })

        Button('获取 SHT30 温湿度').onClick(() => this.getSht30())
        Text(`温度: ${this.temp} °C  湿度: ${this.humi} %`)

        Button('获取 HC-SR501 红外').onClick(() => this.getIr())
        Text(`红外状态: ${this.ir}`)

        Button('获取 MQ-2 烟雾').onClick(() => this.getMq2())
        Text(`烟雾值: ${this.smoke}`)

        Button('报警 - 正常(0)').onClick(() => this.setAlarmNormal())
        Button('报警 - 警告(1)').onClick(() => this.setAlarmWarn())
        Button('报警 - 报警(2)').onClick(() => this.setAlarmAlert())
        Text(`报警结果: ${this.alarmResult}`)
      }
      .width('100%')
      .padding(20)
    }
    .height('100%')        // 关键：给 Scroll 一个确定高度
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
  }
}