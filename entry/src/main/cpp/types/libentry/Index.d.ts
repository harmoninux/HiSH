export type VmOptions = {
  cpuCount: number
  memSize: number
  onData: (ArrayBuffer) => void
  onExit: () => void
}

export const startVM: (options: VmOptions) => void;
export const send: (content: ArrayBuffer) => void;