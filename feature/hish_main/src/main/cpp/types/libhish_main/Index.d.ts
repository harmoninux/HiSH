export type NapiVmOptions = {
  argsLines: string
  unixSocket: string
  qmpSocket: string
  supportJit: boolean
}

export const startVM: (options: NapiVmOptions) => boolean;
export const onData: (callback: (ArrayBuffer) => void) => void;
export const onShutdown: (callback: () => void) => void;
export const sendInput: (content: ArrayBuffer) => void;
export const checkPortUsed: (port: number) => boolean;
export const getImageInfo: (imagePath: string) => string;
export const getSnapshots: (imagePath: string) => string;
export const createSnapshot: (imagePath: string, snapshotName: string) => string;
export const applySnapshot: (imagePath: string, snapshotName: string) => string;
export const deleteSnapshot: (imagePath: string, snapshotName: string) => string;
export const optimizeImage: (imagePath: string, outputPath: string, mode: 'sparse' | 'prealloc' | 'cleanup' | 'optimize') => string;
export const vncInit: (address: string, port: number, password: string) => boolean;
export const vncClose: () => number;
export const vncMouseEvent: (x: number, y: number, buttonMask: number) => void;
export const vncKeyEvent: (keyCode: number, down: boolean) => void;
export interface VncPollResult { status: number; fbWidth: number; fbHeight: number; }
export const vncStartUpdateLoop: (onStatusUpdate: (result: VncPollResult) => void) => boolean;
export const vncStopUpdateLoop: () => void;
export const vncCreateSurface: (surfaceId: bigint) => boolean;
export const vncResizeSurface: (surfaceId: bigint, width: number, height: number) => number;
export const vncDestroySurface: () => number;
