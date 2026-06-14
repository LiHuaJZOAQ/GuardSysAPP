export interface LogItem {
  text: string;
  level: string;
}

export class LogStore {
  private static messages: LogItem[] = [];

  static add(msg: string, level: string = 'info'): void {
    const time: string = new Date().toLocaleTimeString();
    const item: LogItem = { text: '[' + time + '] ' + msg, level: level };
    LogStore.messages.push(item);
    if (LogStore.messages.length > 200) {
      LogStore.messages.shift();
    }
  }

  static getAll(): LogItem[] {
    return LogStore.messages;
  }

  static clear(): void {
    LogStore.messages = [];
  }
}
