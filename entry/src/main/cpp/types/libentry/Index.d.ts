export type NapiVmOptions = {
  argsLines: string
  unixSocket: string
  qmpSocket: string
  isPcDevice: boolean
}

export const startVM: (options: NapiVmOptions) => void;

export const onData: (callback: (data: ArrayBuffer) => void) => void;

export const onShutdown: (callback: () => void) => void;

export const sendInput: (content: ArrayBuffer) => void;

export const checkPortUsed: (port: number) => boolean;