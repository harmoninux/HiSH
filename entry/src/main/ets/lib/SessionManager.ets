/**
 * SessionManager: Manages multiple terminal sessions.
 * Session 0 is the primary serial port managed by the Native layer (napi.onData/sendInput).
 * Sessions 1..N are managed by ArkTS via UnixSocketSession (backed by NAPI).
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UnixSocketSession } from './UnixSocketSession';

const DOMAIN = 0x0000;
const TAG = 'SessionManager';

export interface TerminalSession {
  /** Session index (0-based). 0 = primary serial port */
  index: number;
  /** Display name for the tab */
  name: string;
  /** Whether this session is currently active/connected */
  connected: boolean;
  /** Whether this session is the primary (native) serial port */
  isPrimary: boolean;
  /** For non-primary sessions, the UnixSocketSession instance */
  socketSession?: UnixSocketSession;
  /** Unix socket path for this session */
  socketPath: string;
  /** Callback to write data to the terminal UI */
  onOutput?: (data: ArrayBuffer) => void;
  /** Pending data buffer (for data arriving before terminal is ready) */
  pendingData: ArrayBuffer[];
}

class SessionManagerClass {
  private sessions: Map<number, TerminalSession> = new Map();
  private maxSessions: number = 1;

  init(maxSessions: number, primarySocketPath: string, extraSocketPaths: string[]): void {
    this.maxSessions = maxSessions;
    this.sessions.clear();

    // Session 0: primary serial port (managed natively)
    this.sessions.set(0, {
      index: 0,
      name: 'Session 1',
      connected: true,
      isPrimary: true,
      socketPath: primarySocketPath,
      pendingData: []
    });

    // Sessions 1..N: extra serial ports (managed by ArkTS via NAPI)
    for (let i = 0; i < extraSocketPaths.length; i++) {
      this.sessions.set(i + 1, {
        index: i + 1,
        name: `Session ${i + 2}`,
        connected: false,
        isPrimary: false,
        socketPath: extraSocketPaths[i],
        pendingData: []
      });
    }

    hilog.info(DOMAIN, TAG, 'Initialized with %{public}d sessions (max: %{public}d)', this.sessions.size, maxSessions);
  }

  getMaxSessions(): number {
    return this.maxSessions;
  }

  getSession(index: number): TerminalSession | undefined {
    return this.sessions.get(index);
  }

  getAllSessions(): TerminalSession[] {
    const result: TerminalSession[] = [];
    this.sessions.forEach((session: TerminalSession) => {
      result.push(session);
    });
    return result;
  }

  /** Open a non-primary session (connect to its Unix socket) */
  async openSession(index: number): Promise<boolean> {
    const session = this.sessions.get(index);
    if (!session) {
      hilog.error(DOMAIN, TAG, 'Session %{public}d not found', index);
      return false;
    }
    if (session.isPrimary) {
      session.connected = true;
      return true;
    }
    if (session.connected) {
      hilog.warn(DOMAIN, TAG, 'Session %{public}d already connected', index);
      return true;
    }

    hilog.info(DOMAIN, TAG, 'Opening session %{public}d, socketPath=%{public}s', index, session.socketPath);

    const sockSession = new UnixSocketSession(
      session.socketPath,
      (data: ArrayBuffer) => {
        hilog.info(DOMAIN, TAG, '[DIAG] onData from socket: session=%{public}d, bytes=%{public}d, onOutput=%{public}s',
          index, data.byteLength, session.onOutput ? 'set' : 'NULL');
        if (session.onOutput) {
          session.onOutput(data);
        } else {
          session.pendingData.push(data);
          hilog.warn(DOMAIN, TAG, '[DIAG] onOutput is NULL, buffered data. session=%{public}d, pendingData=%{public}d',
            index, session.pendingData.length);
        }
      },
      () => {
        session.connected = false;
        session.socketSession = undefined;
        hilog.info(DOMAIN, TAG, 'Session %{public}d closed', index);
      },
      (err: string) => {
        hilog.error(DOMAIN, TAG, 'Session %{public}d error: %{public}s', index, err);
      }
    );

    const connected = await sockSession.connect();
    hilog.info(DOMAIN, TAG, 'Session %{public}d connect result: %{public}s', index, connected ? 'success' : 'failed');
    if (connected) {
      session.socketSession = sockSession;
      session.connected = true;

      // Flush pending data
      if (session.pendingData.length > 0 && session.onOutput) {
        for (const data of session.pendingData) {
          session.onOutput(data);
        }
        session.pendingData = [];
      }

      hilog.info(DOMAIN, TAG, 'Session %{public}d opened (pendingData flushed, onOutput=%{public}s)',
        index, session.onOutput ? 'set' : 'null');
    }
    return connected;
  }

  /** Close a non-primary session */
  async closeSession(index: number): Promise<void> {
    const session = this.sessions.get(index);
    if (!session || session.isPrimary) {
      hilog.warn(DOMAIN, TAG, 'Cannot close session %{public}d (not found or primary)', index);
      return;
    }

    if (session.socketSession) {
      await session.socketSession.close();
      session.socketSession = undefined;
    }
    session.connected = false;
    session.onOutput = undefined;
    session.pendingData = [];
    hilog.info(DOMAIN, TAG, 'Session %{public}d closed', index);
  }

  /** Send input data to a specific session */
  async sendInput(index: number, data: ArrayBuffer): Promise<boolean> {
    const session = this.sessions.get(index);
    if (!session || !session.connected) {
      hilog.warn(DOMAIN, TAG, '[DIAG] sendInput FAIL: session=%{public}d (found=%{public}s, connected=%{public}s)',
        index, session ? 'yes' : 'no', session?.connected ? 'yes' : 'no');
      return false;
    }

    if (session.isPrimary) {
      return false; // Caller should use napi.sendInput directly
    }

    if (session.socketSession) {
      const result = await session.socketSession.write(data);
      hilog.info(DOMAIN, TAG, '[DIAG] sendInput: session=%{public}d, bytes=%{public}d, result=%{public}s',
        index, data.byteLength, result ? 'OK' : 'FAIL');
      return result;
    }
    hilog.warn(DOMAIN, TAG, '[DIAG] sendInput FAIL: session=%{public}d has no socketSession', index);
    return false;
  }

  /** Set the output callback for a session */
  setOutputCallback(index: number, callback: (data: ArrayBuffer) => void): void {
    const session = this.sessions.get(index);
    if (!session) {
      hilog.warn(DOMAIN, TAG, 'setOutputCallback: Session %{public}d not found', index);
      return;
    }

    session.onOutput = callback;
    hilog.info(DOMAIN, TAG, 'setOutputCallback for session %{public}d, pendingData=%{public}d',
      index, session.pendingData.length);

    // Flush any pending data
    if (session.pendingData.length > 0) {
      for (const data of session.pendingData) {
        callback(data);
      }
      session.pendingData = [];
    }
  }

  /** Clear the output callback for a session */
  clearOutputCallback(index: number): void {
    const session = this.sessions.get(index);
    if (session) {
      session.onOutput = undefined;
    }
  }

  /** Clean up all sessions */
  async closeAll(): Promise<void> {
    this.sessions.forEach((session: TerminalSession) => {
      if (session.socketSession) {
        session.socketSession.close();
      }
      session.connected = false;
      session.onOutput = undefined;
      session.pendingData = [];
    });
    this.sessions.clear();
  }
}

/** Singleton session manager */
const sessionManager = new SessionManagerClass();

export default sessionManager;
