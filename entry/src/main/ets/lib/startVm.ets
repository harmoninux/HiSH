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
  qgaUnixSocket: string
  sharedFolderReadonly: boolean
  init: string
  vncWebSocketPort?: number // VNC WebSocket 端口 (可选，由外部传入)
}

function startVm(options: VmOptions) {
  const root = options.rootVda ? options.rootVda : defaultEmulator.rootVda;
  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const basic = ['-machine', 'virt,acpi=on,gic-version=max,' +
    'iommu=none,its=off,usb=off,virtualization=off,memory-backend=mem0,compact-highmem=on,' +
    'dump-guest-core=off,mem-merge=off,hmat=off',
    '-overcommit', 'cpu-pm=off',
    '-cpu', 'max,pauth-impdef=on,sve=off,pmu=off', '-accel', 'tcg,thread=multi,tb-size=2048',
    "-object", "rng-random,filename=/dev/urandom,id=rng0",
    "-device", "virtio-rng-pci-non-transitional,rng=rng0",
    '-rtc', 'base=utc,clock=host', '-L', options.baseDir]
  const serial = ['-serial', "unix:" + options.serialUnixSocket + ",server,nowait"]
  const cpuMem = ['-smp', `cpus=${options.cpu},sockets=1,cores=${options.cpu},threads=1`,
    "-object", `memory-backend-ram,id=mem0,size=${options.memory}M,merge=off,prealloc=off`, '-m', options.memory + 'M']
  const kernel = ['-kernel', options.kernel]
  const network = ["-global", "virtio-net-pci.ctrl_guest_offloads=off", "-global", "virtio-net-pci.packed=on",
    "-device", "virtio-net-pci-non-transitional," +
    "netdev=eth0,csum=on,gso=on,guest_tso4=on,guest_tso6=on,guest_ecn=off,mrg_rxbuf=on,tx=bh",
    '-netdev', "user,id=eth0" + options.portMapping.map(it => `,hostfwd=tcp::${it.host}-:${it.guest}`).join('')]
  const shared =
    ["-fsdev", "local,security_model=mapped-file,id=fsdev0,path=" + options.sharedFolder + sharedFolderOption,
    "-device", "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshare"]
  const drive = ["-global", "virtio-blk-pci.scsi=off", "-global", "virtio-scsi-pci.cmd_per_lun=128",
    "-global", "virtio-scsi-pci.packed=on", "-drive", "if=none,format=qcow2,file=" + options.rootFilesystem
    + ",id=hd0,cache=writeback,aio=threads,discard=unmap", "-object", "iothread,id=iothread0,poll-max-ns=2000000",
    "-device", "virtio-scsi-pci-non-transitional,id=scsi0,num_queues=" + options.cpu.toString() +
    ",virtqueue_size=256,iothread=iothread0",
    "-device", "scsi-hd,drive=hd0,bus=scsi0.0,logical_block_size=4096,physical_block_size=4096,rotation_rate=1,bootindex=1"]
  const kernelParam = ["-append",
    "root=" + root + " rw rootfstype=ext4 rootwait console=tty0 console=ttyAMA0 consoleblank=0 " +
    "elevator=noop skew_tick=1 acpi=on " +
    "mitigations=off audit=0 nmi_watchdog=0 hardened_usercopy=off random.trust_cpu=on virtio_balloon.config_impl=0 " +
    "security=none selinux=0 apparmor=0 psi=0 page_alloc.shuffle=0 swiotlb=noforce idle=halt " +
    "cpuidle.off=1 transparent_hugepage=always pci=noaer scsi_mod.use_blk_mq=1 rng_core.default_quality=1000 " +
    "systemd.mask=run-lock.mount systemd.mask=sys-kernel-debug.mount systemd.mask=dev-hugepages.mount " +
    "cryptomgr.notests rodata=off rcupdate.rcu_cpu_stall_timeout=60 " +
    "rcu_expedited=1 init_on_free=0 init_on_alloc=1 page_poison=0 slub_debug=- " +
    "TERM=xterm init=" + options.init]
  const monitor = ['-qmp', 'unix:' + options.qmpUnixSocket + ',server,nowait']
  const qga = [
    '-device', 'virtio-serial-pci-non-transitional,id=virtio-serial0',
    '-chardev', 'socket,path=' + options.qgaUnixSocket + ',server=on,wait=off,id=qga0',
    '-device', 'virtserialport,chardev=qga0,bus=virtio-serial0.0,name=org.qemu.guest_agent.0'
  ]

  const sharedUserFolder = deviceInfo.deviceType !== '2in1' ? [] :
    ["-fsdev", "local,security_model=mapped-file,id=fsdev1,path=/storage/Users/currentUser", "-device",
      "virtio-9p-pci,id=fs1,fsdev=fsdev1,mount_tag=usershare"]

  // VNC 服务器 (仅当 vncWebSocketPort 已设置时启用)
  const vnc: string[] = options.vncWebSocketPort ? [
    '-vnc', `127.0.0.1:0,websocket=${options.vncWebSocketPort}`,
    '-device', 'virtio-gpu-pci',
    '-device', 'virtio-keyboard-pci',
    '-device', 'virtio-tablet-pci'
  ] : []

  const args = [
    'qemu-system-aarch64',
    ...basic,
    ...serial,
    ...cpuMem,
    ...kernel,
    ...network,
    ...shared,
    ...drive,
    ...kernelParam,
    ...monitor,
    ...qga,
    ...vnc,
    ...sharedUserFolder
  ]

  if (fs.accessSync(options.serialUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.serialUnixSocket)
  }
  if (fs.accessSync(options.qmpUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.qmpUnixSocket)
  }
  if (fs.accessSync(options.qgaUnixSocket, fs.AccessModeType.EXIST)) {
    fs.unlinkSync(options.qgaUnixSocket)
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
