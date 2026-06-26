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
  { id: '7', label: '系统信息', command: 'uname -a && cat /etc/os-release\n', starred: false, sortOrder: 6 },
  { id: '8', label: '查看端口', command: 'ss -tlnp\n', starred: false, sortOrder: 7 },
  { id: '9', label: 'DNS 测试', command: 'nslookup google.com\n', starred: false, sortOrder: 8 },
  { id: '10', label: '清理缓存', command: 'apt clean && apt autoremove -y\n', starred: false, sortOrder: 9 },
  { id: '11', label: '查看日志', command: 'journalctl -n 50 --no-pager\n', starred: false, sortOrder: 10 },
  { id: '12', label: 'CPU 信息', command: 'lscpu | head -20\n', starred: false, sortOrder: 11 },
  { id: '13', label: '安装软件', command: 'apt install -y ', starred: false, sortOrder: 12 },
  { id: '14', label: '查看文件', command: 'ls -lah\n', starred: false, sortOrder: 13 },
  { id: '15', label: '网络诊断', command: 'traceroute -n 8.8.8.8\n', starred: false, sortOrder: 14 },
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
