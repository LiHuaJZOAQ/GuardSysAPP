export class LogStore {
  private static messages: string[] = [];

  static add(msg: string): void {
    const time: string = new Date().toLocaleTimeString();
    LogStore.messages.push('[' + time + '] ' + msg);
    if (LogStore.messages.length > 200) {
      LogStore.messages.shift();
    }
  }

  static getAll(): string[] {
    return LogStore.messages;
  }

  static clear(): void {
    LogStore.messages = [];
  }
}
