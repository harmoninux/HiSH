export type appOptions = {
  argsLines: string
  unixSocket: string
}

export const startVM: (options: appOptions) => void;

export const onData: (onData: (ArrayBuffer) => void) => void;

export const sendInput: (content: ArrayBuffer) => void;

export const checkPortUsed: (port: number) => boolean;