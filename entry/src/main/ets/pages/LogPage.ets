import { LogStore, LogItem } from './LogStore';
import router from '@ohos.router';

@Entry
@Component
struct LogPage {
  @State logMessages: LogItem[] = [];
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    this.logMessages = LogStore.getAll();
    this.refreshTimer = setInterval(() => {
      this.logMessages = LogStore.getAll();
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  goBack(): void {
    router.back();
  }

  clearLog(): void {
    LogStore.clear();
    this.logMessages = [];
  }

  getLevelColor(level: string): string {
    if (level === 'error') {
      return '#E74C3C';
    }
    if (level === 'warn') {
      return '#F39C12';
    }
    return '#333333';
  }

  build() {
    Column({ space: 8 }) {
      // 标题栏
      Row() {
        Button('← 返回')
          .height(32)
          .fontSize(14)
          .onClick(() => { this.goBack(); })
        Blank()
        Text('📝 系统日志')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
        Blank()
        Button('清空')
          .height(28)
          .fontSize(12)
          .fontColor('#E74C3C')
          .onClick(() => { this.clearLog(); })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
      .margin({ top: 12 })

      // 日志列表
      List({ space: 3 }) {
        ForEach(this.logMessages, (item: LogItem) => {
          ListItem() {
            Text(item.text)
              .fontSize(12)
              .fontColor(this.getLevelColor(item.level))
              .align(Alignment.Start)
              .width('100%')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
      .margin({ left: 12, right: 12, bottom: 12 })
      .border({ width: 1, color: '#DDDDDD' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F0F0F0')
  }
}
