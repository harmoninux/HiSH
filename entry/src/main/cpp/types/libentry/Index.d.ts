export type appOptions = {
  bundleCodeDir: string
  tempDir: string
  filesDir: string
  cpuCount: number
  memSize: number
  portMapping: string,
  onData: (ArrayBuffer) => void
  onExit: () => void
}

export const startVM: (options: appOptions) => void;
export const sendInput: (content: ArrayBuffer) => void;