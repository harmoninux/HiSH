export type appOptions = {
  argsLines: string
  unixSocket: string
  qmpSocket: string
}

export const startVM: (options: appOptions) => void;

export const checkPortUsed: (port: number) => boolean;