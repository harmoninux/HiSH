/**
 * UnixSocketSession: ArkTS-level serial port session manager for extra serial ports.
 * Uses @kit.NetworkKit (LocalSocket) to connect to QEMU serial port Unix sockets.
 * Only used for sessions beyond the first (primary) serial port.
 *
 * This is the same LocalSocket API used by QemuAgent.ets for QGA communication.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { socket } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;
const TAG = 'UnixSocketSession';

export class UnixSocketSession {
  private socketPath: string;
  private onOutput: (data: ArrayBuffer) => void;
  private onClose: () => void;
  private onError: (err: string) => void;
  private client: socket.LocalSocket | null = null;
  private connected: boolean = false;

  constructor(socketPath: string, onOutput: (data: ArrayBuffer) => void,
    onClose: () => void, onError: (err: string) => void) {
    this.socketPath = socketPath;
    this.onOutput = onOutput;
    this.onClose = onClose;
    this.onError = onError;
  }

  async connect(): Promise<boolean> {
    // Wait for socket file to exist (max 10 seconds)
    hilog.info(DOMAIN, TAG, 'Connecting to: %{public}s', this.socketPath);
    const startTime = Date.now();
    const maxWait = 10000;
    while (Date.now() - startTime < maxWait) {
      try {
        if (fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)) {
          hilog.info(DOMAIN, TAG, 'Socket file found after %{public}d ms', Date.now() - startTime);
          break;
        }
      } catch (e) {
        // accessSync may throw, ignore
      }
      await new Promise<void>(resolve => setTimeout(resolve, 100));
    }

    // Final check
    try {
      if (!fs.accessSync(this.socketPath, fs.AccessModeType.EXIST)) {
        const errMsg = `Socket file not found after ${maxWait}ms: ${this.socketPath}`;
        hilog.error(DOMAIN, TAG, errMsg);
        this.onError(errMsg);
        return false;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Failed to check socket file: %{public}s', JSON.stringify(e));
    }

    try {
      this.client = socket.constructLocalSocketInstance();

      // Subscribe to message events before connecting
      this.client.on('message', (value: socket.LocalSocketMessageInfo) => {
        hilog.info(DOMAIN, TAG, '[DIAG] message event on %{public}s, byteLength=%{public}d',
          this.socketPath, value?.message?.byteLength ?? -1);
        if (value && value.message) {
          this.onOutput(value.message);
        } else {
          hilog.warn(DOMAIN, TAG, '[DIAG] message event but value/message is null on %{public}s', this.socketPath);
        }
      });

      this.client.on('close', () => {
        hilog.info(DOMAIN, TAG, 'Socket closed: %{public}s', this.socketPath);
        if (this.connected) {
          this.connected = false;
          this.onClose();
        }
      });

      this.client.on('error', (err: Error) => {
        hilog.error(DOMAIN, TAG, 'Socket error on %{public}s: %{public}s', this.socketPath, JSON.stringify(err));
        if (this.connected) {
          this.connected = false;
          this.onError(JSON.stringify(err));
        }
      });

      // Connect using LocalConnectOptions (same pattern as QemuAgent)
      const address: socket.LocalAddress = {
        address: this.socketPath
      };
      const connectOptions: socket.LocalConnectOptions = {
        address: address,
        timeout: 6000
      };
      await this.client.connect(connectOptions);

      this.connected = true;
      hilog.info(DOMAIN, TAG, 'Connected to: %{public}s', this.socketPath);

      // Send a newline to trigger getty to re-print the login prompt.
      // With QEMU's "server,nowait" mode, any serial output before a client connects
      // is discarded. Sending \n causes getty/agetty to re-display the prompt.
      try {
        const newline = new ArrayBuffer(1);
        new Uint8Array(newline)[0] = 0x0A; // '\n'
        await this.client.send({ data: newline });
        hilog.info(DOMAIN, TAG, 'Sent newline to trigger getty prompt on %{public}s', this.socketPath);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Failed to send newline: %{public}s', JSON.stringify(e));
      }

      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'connect error for %{public}s: %{public}s', this.socketPath, JSON.stringify(e));
      this.onError(String(e));
      this.connected = false;
      return false;
    }
  }

  async write(data: ArrayBuffer): Promise<boolean> {
    if (!this.connected || !this.client) {
      hilog.warn(DOMAIN, TAG, '[DIAG] Write failed: not connected (connected=%{public}s, client=%{public}s, path=%{public}s)',
        this.connected, this.client ? 'exists' : 'null', this.socketPath);
      return false;
    }
    try {
      const sendOptions: socket.LocalSendOptions = {
        data: data
      };
      await this.client.send(sendOptions);
      hilog.info(DOMAIN, TAG, '[DIAG] Write OK: %{public}d bytes to %{public}s', data.byteLength, this.socketPath);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, '[DIAG] Write failed for %{public}s: %{public}s', this.socketPath, JSON.stringify(e));
      return false;
    }
  }

  isConnected(): boolean {
    return this.connected;
  }

  async close(): Promise<void> {
    if (this.connected && this.client) {
      const client = this.client;
      this.client = null;
      this.connected = false;

      try {
        client.off('message');
        client.off('error');
        client.off('close');
        await client.close();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Close error for %{public}s: %{public}s', this.socketPath, JSON.stringify(e));
      }
      this.onClose();
    }
  }
}
