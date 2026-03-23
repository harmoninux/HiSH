import { hilog } from '@kit.PerformanceAnalysisKit';
import napi from 'libentry.so';

const DOMAIN = 0x0001;
const LOG_TAG = 'NativeVnc';

@Component
export default struct NativeVncViewer {
  @Prop address: string = '127.0.0.1'
  @Prop port: number = 5900
  @Prop password: string = ''
  @Prop connected: boolean = false

  @State isConnected: boolean = false
  @State errorMessage: string = ''
  @State statusMessage: string = ''

  private updateInterval?: number = undefined

  aboutToAppear() {
    hilog.info(DOMAIN, LOG_TAG, 'NativeVncViewer initializing: %{public}s:%{public}d', this.address, this.port);
    this.connectVnc();
  }

  aboutToDisappear() {
    this.disconnectVnc();
  }

  onConnectedChanged() {
    if (!this.connected) {
      this.disconnectVnc();
    }
  }

  private connectVnc() {
    try {
      this.statusMessage = 'Connecting to VNC server...';
      const result = napi.vncInit(this.address, this.port, this.password);
      hilog.info(DOMAIN, LOG_TAG, 'vncInit result: %{public}s', JSON.stringify(result));

      if (result) {
        this.isConnected = true;
        this.statusMessage = 'Connected! Waiting for VNC updates...';
        hilog.info(DOMAIN, LOG_TAG, 'VNC connected successfully');
        this.startUpdateLoop();
      } else {
        this.errorMessage = 'Connection failed';
        this.statusMessage = 'Connection failed';
        hilog.error(DOMAIN, LOG_TAG, 'VNC init failed');
      }
    } catch (e) {
      this.errorMessage = 'Error: ' + JSON.stringify(e);
      this.statusMessage = 'Error: ' + JSON.stringify(e);
      hilog.error(DOMAIN, LOG_TAG, 'VNC connection error: %{public}s', JSON.stringify(e));
    }
  }

  private disconnectVnc() {
    if (this.isConnected) {
      try {
        napi.vncClose();
        this.isConnected = false;
        this.stopUpdateLoop();
        this.statusMessage = 'Disconnected';
        hilog.info(DOMAIN, LOG_TAG, 'VNC disconnected');
      } catch (e) {
        hilog.error(DOMAIN, LOG_TAG, 'Error disconnecting VNC: %{public}s', JSON.stringify(e));
      }
    }
  }

  private startUpdateLoop() {
    this.updateInterval = setInterval(() => {
      try {
        const result = napi.vncUpdate(
          (size: number) => {
            hilog.info(DOMAIN, LOG_TAG, 'VNC resize: %{public}d bytes', size);
            const newBuffer = new ArrayBuffer(size);
            return newBuffer;
          },
          (updateInfo: ArrayBuffer) => {
            const data = new Uint8Array(updateInfo);
            const view = new DataView(updateInfo);
            const width = view.getInt32(0, true);
            const height = view.getInt32(4, true);
            const x = view.getInt32(8, true);
            const y = view.getInt32(12, true);
            const w = view.getInt32(16, true);
            const h = view.getInt32(20, true);

            hilog.info(DOMAIN, LOG_TAG, 'VNC update: %{public}dx%{public}d at (%{public}d,%{public}d), %{public}dx%{public}d',
                      width, height, x, y, w, h);
            this.statusMessage = 'Update: ' + w + 'x' + h + ' at ' + x + ',' + y;
          }
        );
      } catch (e) {
        hilog.error(DOMAIN, LOG_TAG, 'VNC update error: %{public}s', JSON.stringify(e));
        this.errorMessage = 'Update error: ' + JSON.stringify(e);
        this.isConnected = false;
        this.stopUpdateLoop();
      }
    }, 100);
  }

  private stopUpdateLoop() {
    if (this.updateInterval !== undefined) {
      clearInterval(this.updateInterval);
      this.updateInterval = undefined;
    }
  }

  build() {
    Text(this.errorMessage || this.statusMessage || 'Ready')
  }
}
