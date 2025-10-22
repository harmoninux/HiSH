export type appOptions = {
  bundleCodeDir: string
  tempDir: string
  filesDir: string
  cpuCount: number
  memSize: number
  portMapping: string,
  isPc: boolean,
  onData: (ArrayBuffer) => void
  onExit: () => void
}

export const startVM: (options: appOptions) => void;
export const sendInput: (content: ArrayBuffer) => void;