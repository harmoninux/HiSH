import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { defaultEmulator, PortMapping } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'
import { socket } from '@kit.NetworkKit'

interface VmOptions {
  baseDir: string
  cpu: number
  memory: number
  portMapping: PortMapping[]
  kernel: string
  rootVda: string
  rootFilesystem: string
  sharedFolder: string
  serialUnixSocket: string
  qmpUnixSocket: string
  sharedFolderReadonly: boolean
  init: string
}

const sleep = (ms: number): Promise<void> => {
  return new Promise(resolve => setTimeout(resolve, ms));
}

class SerialChannel {
  private buffer: ArrayBuffer[]
  private socket?: socket.LocalSocket
  private receiver?: (buf: ArrayBuffer) => void

  constructor() {
    this.buffer = []
  }

  async connect(socketPath: string) {
    this.socket = socket.constructLocalSocketInstance()
    while (true) {
      const exist = await fs.access(socketPath, fs.AccessModeType.EXIST)
      if (!exist) {
        await sleep(10)
      } else {
        break
      }
    }
    await this.socket.connect({ address: { address: socketPath } })
    this.socket.on('message', info => {
      if (this.receiver) {
        this.receiver(info.message)
      } else {
        this.buffer.push(info.message)
      }
    })
  }

  onMessage(receiver: (buf: ArrayBuffer) => void) {
    this.receiver = receiver
    if (this.buffer.length > 0) {
      this.buffer.forEach(it => receiver(it))
      this.buffer.splice(0, this.buffer.length)
    }
  }

  async sendMessage(buf: ArrayBuffer) {
    return await this.socket!!.send({ data: buf })
  }
}

interface StartResult {
  portsSkipped: number[]
  serial: SerialChannel
}

const serialChannel = new SerialChannel()

function startVm(options: VmOptions): StartResult {

  const root = options.rootVda ? options.rootVda : defaultEmulator.rootVda;
  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const portUsed = options.portMapping.map(it => it.host!!).filter(p => napi.checkPortUsed(p))
  const portMapping = options.portMapping.filter(it => portUsed.indexOf(it.host!!) < 0)

  const basic = ['-machine', 'virt', '-cpu', 'cortex-a53', '-nographic', '-L', options.baseDir]
  const serial = ['-serial', "unix:" + options.serialUnixSocket + ",server"]
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

  if (fs.accessSync(options.serialUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.serialUnixSocket)
  }
  if (fs.accessSync(options.qmpUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.qmpUnixSocket)
  }
  if (!fs.accessSync(options.sharedFolder, fs.AccessModeType.EXIST)) {
    fs.mkdirSync(options.sharedFolder)
  }

  napi.startVM({
    argsLines: args.join('\n'),
    unixSocket: options.serialUnixSocket,
    qmpSocket: options.qmpUnixSocket
  })

  serialChannel.connect(options.serialUnixSocket)
  return { portsSkipped: portUsed, serial: serialChannel }
}

export { startVm, VmOptions, StartResult, serialChannel }