import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { defaultEmulator, PortMapping } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'
import SerialChannel from './serialChannel'
import { ShellChannel } from './shellChannel'

interface VmOptions {
  baseDir: string
  cpu: number
  memory: number
  portMapping: PortMapping[]
  kernel: string
  rootVda: string
  rootFilesystem: string
  sharedFolder: string
  terminalUnixSocket: string
  controlUnixSocket: string
  qmpUnixSocket: string
  sharedFolderReadonly: boolean
  init: string
}

interface StartResult {
  portsSkipped: number[]
  serial: SerialChannel
}

const serialChannel = new SerialChannel()
const shellChannel = new ShellChannel()

function startVm(options: VmOptions): StartResult {

  const root = options.rootVda ? options.rootVda : defaultEmulator.rootVda;
  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const portUsed = options.portMapping.map(it => it.host!!).filter(p => napi.checkPortUsed(p))
  const portMapping = options.portMapping.filter(it => portUsed.indexOf(it.host!!) < 0)

  const basic = ['-machine', 'virt', '-cpu', 'cortex-a53', '-nographic', '-L', options.baseDir]
  const serial = [options.terminalUnixSocket, options.controlUnixSocket]
    .flatMap(s => ['-serial', "unix:" + s + ",server,nowait"])
  const cpuMem = ['-smp', options.cpu.toString(), '-m', options.memory + 'M']
  const kernel = ['-kernel', options.kernel]
  const network = ["-device", "virtio-net-device,netdev=eth0",
    '-netdev', "user,id=eth0" + portMapping.map(it => `,hostfwd=tcp::${it.host}-:${it.guest}`).join('')]
  const shared =
    ["-fsdev", "local,security_model=mapped-file,id=fsdev0,path=" + options.sharedFolder + sharedFolderOption,
      "-device", "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"]
  const drive = ["-drive", "if=none,format=qcow2,file=" + options.rootFilesystem + ",id=hd0", "-device",
    "virtio-blk-device,drive=hd0"]
  const kernelParam = ["-append",
    "root=" + root + " rw rootfstype=ext4 console=ttyAMA0 TERM=ansi init=" + options.init]
  const monitor = ['-qmp', 'unix:' + options.qmpUnixSocket + ',server,nowait']

  const sharedUserFolder = deviceInfo.deviceType !== '2in1' ? [] :
    ["-fsdev", "local,security_model=mapped-file,id=fsdev1,path=/storage/Users/currentUser", "-device",
      "virtio-9p-pci,id=fs1,fsdev=fsdev1,mount_tag=usershare"]

  const args = [
    'qemu-system-aarch64',
    ...basic,
    ...serial,
    ...cpuMem,
    ...kernel,
    ...network,
    ...shared,
    ...sharedUserFolder,
    ...drive,
    ...kernelParam,
    ...monitor
  ]

  if (fs.accessSync(options.terminalUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.terminalUnixSocket)
  }
  if (fs.accessSync(options.controlUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.controlUnixSocket)
  }
  if (fs.accessSync(options.qmpUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.qmpUnixSocket)
  }
  if (!fs.accessSync(options.sharedFolder, fs.AccessModeType.EXIST)) {
    fs.mkdirSync(options.sharedFolder)
  }

  napi.startVM({
    argsLines: args.join('\n')
  })

  serialChannel.connect(options.terminalUnixSocket)
  shellChannel.connect(options.controlUnixSocket)
  return { portsSkipped: portUsed, serial: serialChannel }
}

export { startVm, VmOptions, StartResult, serialChannel }