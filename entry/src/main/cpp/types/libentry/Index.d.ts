export type VmOptions = {
  bundleCodeDir: string
  tempDir: string
  filesDir: string
  cpuCount: number
  memSize: number
  onData: (ArrayBuffer) => void
  onExit: () => void
}

export const startVM: (options: VmOptions) => void;
export const send: (content: ArrayBuffer) => void;