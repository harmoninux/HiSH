import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { defaultEmulator, PortMapping } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'

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

function startVm(options: VmOptions) {
  const root = options.rootVda ? options.rootVda : defaultEmulator.rootVda;
  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const basic = ['-machine', 'virt,gic-version=max,usb=off,memory-backend=mem0',
    '-cpu', 'max,pauth-impdef=on', '-accel', 'tcg,thread=multi,tb-size=1024',
    "-object", "rng-random,filename=/dev/urandom,id=rng0",
    "-device", "virtio-rng-pci-non-transitional,rng=rng0",
    '-nographic', '-L', options.baseDir]
  const serial = ['-serial', "unix:" + options.serialUnixSocket + ",server,nowait"]
  const cpuMem = ['-smp', options.cpu.toString(),
    "-object", `memory-backend-ram,id=mem0,size=${options.memory}M,merge=off,prealloc=off`, '-m', options.memory + 'M']
  const kernel = ['-kernel', options.kernel]
  const network = ["-device", "virtio-net-pci-non-transitional," +
    "netdev=eth0,csum=on,gso=on,guest_tso4=on,guest_tso6=on,guest_ecn=off,mrg_rxbuf=on",
    '-netdev', "user,id=eth0" + options.portMapping.map(it => `,hostfwd=tcp::${it.host}-:${it.guest}`).join('')]
  const shared =
    ["-fsdev", "local,security_model=mapped-file,id=fsdev0,path=" + options.sharedFolder + sharedFolderOption,
    "-device", "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"]
  const drive = ["-drive", "if=none,format=qcow2,file=" + options.rootFilesystem
    + ",id=hd0,cache=none,aio=threads,discard=unmap,detect-zeroes=unmap",
    "-object", "iothread,id=iothread0",
    "-device", "virtio-scsi-pci-non-transitional,id=scsi0,num_queues=" + options.cpu.toString() + ",iothread=iothread0",
    "-device", "scsi-hd,drive=hd0,bus=scsi0.0"]
  const kernelParam = ["-append",
    "root=" + root + " rw rootfstype=ext4 rootwait console=ttyAMA0 " +
    "mitigations=off audit=0 nmi_watchdog=0 hardened_usercopy=off random.trust_cpu=on virtio_balloon.config_impl=0 " +
    "TERM=ansi init=" + options.init]
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
  });
}

export { startVm, VmOptions }
