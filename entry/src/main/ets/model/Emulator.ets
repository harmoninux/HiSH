interface PortMapping {
  guest?: number
  host?: number
}

interface RootFilesystem {
  id: string
  name: string
  path: string
}

interface Snippet {
  id: string
  label: string
  command: string
  starred: boolean
  sortOrder: number
}

interface Emulator {
  id: string
  name: string,
  cpu: number,
  memory: number,
  init: string
  portMapping: PortMapping[]
  rootVda: string,
  rootFilesystem: string
  sharedFolderReadonly: boolean
  snippets?: Snippet[]
}

// 预设命令（首次创建 VM 时自动填充）
const DEFAULT_SNIPPETS: Snippet[] = [
  { id: '1', label: '更新软件包', command: 'apt update -y && apt upgrade -y\n', starred: true, sortOrder: 0 },
  { id: '2', label: '查看磁盘', command: 'df -h\n', starred: false, sortOrder: 1 },
  { id: '3', label: '查看内存', command: 'free -m\n', starred: false, sortOrder: 2 },
  { id: '4', label: '查看进程', command: 'ps aux --sort=-%mem | head -20\n', starred: false, sortOrder: 3 },
  { id: '5', label: '网络信息', command: 'ip addr && ping -c 2 8.8.8.8\n', starred: false, sortOrder: 4 },
  { id: '6', label: '重启 SSH', command: 'systemctl restart ssh\n', starred: true, sortOrder: 5 },
]

const defaultRootfs: RootFilesystem = {
  id: 'rootfs_aarch64',
  name: 'Alpine Linux',
  path: 'roots/rootfs_aarch64.qcow2'
}

const defaultEmulator: Emulator = {
  id: 'rootfs_aarch64',
  name: '默认模拟器',
  cpu: 1,
  memory: 512,
  init: '/init',
  portMapping: [],
  rootVda: '/dev/sda',
  rootFilesystem: 'vm/rootfs_aarch64.qcow2',
  sharedFolderReadonly: false
}

export { Emulator, PortMapping, RootFilesystem, Snippet, DEFAULT_SNIPPETS, defaultEmulator, defaultRootfs }
