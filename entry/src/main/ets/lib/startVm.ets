import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { PortMapping } from '../model/Emulator'

interface VmOptions {
  baseDir: string
  cpu: number
  memory: number
  portMapping: PortMapping[]
  kernel: string
  rootFilesystem: string
  sharedFolder: string
  serialUnixSocket: string
  sharedFolderReadonly: boolean
  init: string
}

function startVm(options: VmOptions) {

  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const basic = ['-machine', 'virt', '-cpu', 'cortex-a53', '-nographic', '-L', options.baseDir]
  const serial = ['-serial', "unix:" + options.serialUnixSocket + ",server,nowait"]
  const cpuMem = ['-smp', options.cpu.toString(), '-m', options.memory + 'M']
  const kernel = ['-kernel', options.kernel]
  const network = ["-device", "virtio-net-device,netdev=eth0",
    '-netdev', "user,id=eth0" + options.portMapping.map(it => `,hostfwd=tcp::${it.host}-:${it.guest}`).join('')]
  const shared =  ["-fsdev", "local,security_model=mapped-file,id=fsdev0,path=" + options.sharedFolder + sharedFolderOption,
    "-device", "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"]
  const drive = ["-drive", "if=none,format=qcow2,file=" + options.rootFilesystem + ",id=hd0", "-device",
    "virtio-blk-device,drive=hd0"]
  const kernelParam = ["-append",
    "root=/dev/vda rw rootfstype=ext4 console=ttyAMA0 TERM=ansi init=" + options.init]

  const args =
    ['qemu-system-aarch64', ...basic, ...serial, ...cpuMem, ...kernel, ...network, ...shared, ...drive, ...kernelParam]

  if (fs.accessSync(options.serialUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.serialUnixSocket)
  }
  if (!fs.accessSync(options.sharedFolder, fs.AccessModeType.EXIST)) {
    fs.mkdirSync(options.sharedFolder)
  }

  napi.startVM({
    argsLines: args.join('\n'),
    unixSocket: options.serialUnixSocket
  });
}

export { startVm, VmOptions }