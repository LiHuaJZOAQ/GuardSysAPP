# GuardSysAPP — AGENTS.md

## Project

OpenHarmony 4.0 (九联开发板) northbound monitoring system. NAPI reads SHT30/MQ-2/HC-SR501 sensors, TCP reports to cloud server, web frontend displays.

- **Entry point**: `entry/src/main/ets/pages/Index.ets` (`@Entry struct Index`)
- **Build**: DevEco Studio UI only (`Build → Build Hap(s)/APP(s)`) — CLI `hvigorw` requires npmrc setup
- **NAPI module**: `@ohos.guardsys_napi` — hardware-specific, **do not modify** pin numbers or parameter signatures

## ArkTS restrictions (non-negotiable compiler errors)

- **No destructuring**: `const [a, b] = await Promise.all(...)` → use index access: `const list: Object[] = all as Object[]; const a = list[0] as TypeA;`
- **No `any` / `unknown`** in type positions: use explicit types or `Object`/`Error`
- **No catch type annotations**: `catch (e: Error)` → `catch (e)` (e is `Error` by default)
- **No standalone `this`**: cannot use `this` inside callbacks passed to `setTimeout`/`setInterval`. Use arrow functions in struct methods only. In `build()` event handlers, arrow functions with `this` are allowed.
- **No object literals as type declarations**: `Promise<{ temp: number }>` → define explicit `interface Sht30Data` and use `Promise<Sht30Data>`
- **No untyped object literals**: `return { temp: x, humi: y }` → assign to typed variable: `const r: Sht30Data = { temp: x, humi: y }; return r;`
- **Explicit types required**: every variable needs a type annotation (inference is limited)
- **NAPI inline object params OK** as function arguments: `setAlarmStatus(0, { buzzerPin: 384, ... })` is fine

## API 10 WiFi quirks

- `wifiManager.addCandidateConfig()` + `wifiManager.connectToCandidateConfig()` (NOT `addDeviceConfig`/`connectToDevice`)
- Signal level: compute from `rssi`: `Math.min(100, Math.max(0, (info.rssi + 100) * 100 / 70))`
- Connection status: compare `getLinkedInfo().ssid` against scan results
- `getLinkedInfo()` is async (await required)

## Permissions

| Permission | Grant | Where |
|---|---|---|
| `INTERNET` | system | `module.json5` |
| `GET_WIFI_INFO` | system | `module.json5` |
| `SET_WIFI_INFO` | system | `module.json5` |
| `LOCATION` | user_grant | `module.json5` + runtime `abilityAccessCtrl.createAtManager().requestPermissionsFromUser()` |
| `APPROXIMATELY_LOCATION` | user_grant | same as LOCATION |

## Sensor pin map (DO NOT CHANGE)

| Sensor | Interface |
|---|---|
| SHT30 | `getSht30Data(5, 0x44)` → `{temp, humi}` |
| MQ-2 | `getMq2Data(1)` → `{smoke}` |
| HC-SR501 | `getIrStatus(9)` → `{ir}` (0/1, convert with `!!res.ir`) |
| Alarm | `setAlarmStatus(mode, {buzzerPin:384, rPin:381, gPin:382, bPin:383})` |

## TCP client

- Callbacks (`onConnectCallback`, `onMessageCallback`, etc.) must be assigned **before** `connectServer()` call, or connect event is missed
- `connectServer()` supports domain names (not just IP)

## Auto-report (in SettingsPage)

- `@State autoReport: boolean = true` (default on)
- `@State reportInterval: number = 1` (1 second)
- Uses `SensorManager.currentAlarmMode` for the alarm field in the report payload
- Starts automatically on page load when TCP is connected
- Stopped on disconnect or page disappear

## Sensor reading

- `collectAll(silent: boolean)` — auto-refresh calls with `true` (no log), manual with `false`
- `Promise.all` for parallel reads (3 sensors), but avoid destructuring
- `sensorError: string` — set on failure, cleared on success, shown as red banner in UI

## Auto-refresh timer

- `setInterval` in `aboutToAppear` calls `collectAll(true)` every 1000ms
- Cleaned up in `aboutToDisappear` with `clearInterval`

## Alarm thresholds (in `checkAlarmThreshold`)

| smoke >= 200 | alarm mode 2 (报警, red + buzzer) |
|---|---|
| smoke >= 100 or temp >= 40 | mode 1 (警告, yellow) |
| smoke >= 50 or temp >= 35 | mode 0 (正常, green, with log notice) |
| else | mode 0 (正常, green) |

## Startup

`aboutToAppear` calls `SensorManager.initAlarm()` → sets normal mode (green LED on).

## Files

| File | Purpose |
|---|---|---|
| `Index.ets` | Dashboard (entry) — sensor cards, alarm status display, network status indicators, "日志"/"设置" navigation buttons |
| `SettingsPage.ets` | Settings page — WiFi scan/connect, TCP server config/connect/disconnect, auto-report (default on, 1s), debug alarm controls |
| `LogPage.ets` | Standalone log viewer page (reads from LogStore) |
| `SensorManager.ets` | NAPI wrapper — getSht30Data/getMq2Data/getIrData/getAllData/initAlarm/setAlarmMode; exports `currentAlarmMode` |
| `TCPClient.ets` | `@ohos.net.socket` TCP client with callback pattern; exports `defaultTcpClient` singleton |
| `WifiManager.ets` | WiFi scan/connect/info (API 10 adapted) |
| `LogStore.ets` | Shared singleton for log messages across all pages |
| `PriSensorData.ets` | Raw NAPI test page (preserved) |
| `PriTCPTestIndex.ets` | Original TCP test page (preserved) |
