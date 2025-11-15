export type appOptions = {
  argsLines: string
}

export const startVM: (options: appOptions) => void;

export const checkPortUsed: (port: number) => boolean;