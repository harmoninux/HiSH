export type appOptions = {
  bundleCodeDir: string
  tempDir: string
  filesDir: string
  vmBaseDir: string
  cpuCount: number
  memSize: number
  portMapping: string,
  rootFilesystem: string,
  kernel: string,
  sharedFolder: string,
  isPc: boolean
}

export const startVM: (options: appOptions) => void;

export const onData: (onData: (ArrayBuffer) => void) => void;

export const sendInput: (content: ArrayBuffer) => void;