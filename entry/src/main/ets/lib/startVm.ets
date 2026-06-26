import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { defaultEmulator, PortMapping } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'
import { hilog } from '@kit.PerformanceAnalysisKit'
import appOption from '../model/appOption'

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
  init: string,
  vncEnabled: boolean
  vncPortMode: string  // 'local' | 'lan'
  vncPort: number      // VNC port number (e.g. 5900)
}

function startVm(options: VmOptions): boolean {
  const root = options.rootVda ? options.rootVda : defaultEmulator.rootVda;
  const sharedFolderOption = options.sharedFolderReadonly ? ",readonly" : ""

  const basic = ['-machine', 'virt,acpi=on,gic-version=max,' +
    'iommu=none,its=off,usb=on,virtualization=off,memory-backend=mem0,compact-highmem=on,' +
    'dump-guest-core=off,mem-merge=off,hmat=off',
    '-overcommit', 'cpu-pm=off',
    '-cpu', 'max,pauth-impdef=on,sve=off,pmu=off', '-accel', 'tcg,thread=multi,tb-size=512',
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
    '-netdev', `user,id=eth0${options.portMapping
      .filter(it => it.host !== undefined && it.host !== null &&
                    it.guest !== undefined && it.guest !== null)
      .map(it => `,hostfwd=tcp::${it.host}-:${it.guest}`)
      .join('')}`]
  const shared =
    ["-virtfs", `local,path=${options.sharedFolder},mount_tag=hostshare,security_model=mapped-file${sharedFolderOption},fmode=0666,dmode=0777`]
  const drive = ["-global", "virtio-blk-pci.scsi=off", "-global", "virtio-scsi-pci.cmd_per_lun=128",
    "-global", "virtio-scsi-pci.packed=on", "-drive", "if=none,format=qcow2,file=" + options.rootFilesystem
    + ",id=hd0,cache=writeback,aio=threads,discard=unmap", "-object", "iothread,id=iothread0,poll-max-ns=500000",
    "-device", "virtio-scsi-pci-non-transitional,id=scsi0,num_queues=" + options.cpu.toString() +
    ",virtqueue_size=256,iothread=iothread0",
    "-device", "scsi-hd,drive=hd0,bus=scsi0.0,logical_block_size=4096,physical_block_size=4096,rotation_rate=1,bootindex=1"]
  const kernelParam = ["-append",
    "root=" + root + " rw rootfstype=ext4 rootwait console=tty0 console=ttyAMA0 consoleblank=0 " +
    "quiet loglevel=3 " +    // 抑制 INFO/DEBUG 内核日志污染终端
    "elevator=noop skew_tick=1 acpi=on " +
    "mitigations=off audit=0 nmi_watchdog=0 hardened_usercopy=off random.trust_cpu=on virtio_balloon.config_impl=0 " +
    "security=none selinux=0 apparmor=0 psi=0 page_alloc.shuffle=0 swiotlb=noforce idle=halt " +
    "cpuidle.off=1 transparent_hugepage=always pci=noaer scsi_mod.use_blk_mq=1 rng_core.default_quality=1000 " +
    "systemd.mask=run-lock.mount systemd.mask=sys-kernel-debug.mount systemd.mask=dev-hugepages.mount " +
    "cryptomgr.notests rodata=off rcupdate.rcu_cpu_stall_timeout=300 " +  // 5min，熄屏恢复不误触发
    "rcu_expedited=1 init_on_free=0 init_on_alloc=1 page_poison=0 slub_debug=- " +
    "nohz=on highres=off clocksource=arch_sys_counter " +  // 省电：tickless + 高效时钟源
    "net.core.netdev_budget=300 " +                         // 减少网络软中断
    "TERM=xterm-256color init=" + options.init]
  const monitor = ['-qmp', 'unix:' + options.qmpUnixSocket + ',server,nowait']
  const qga = [
    '-device', 'virtio-serial-pci-non-transitional,id=virtio-serial0',
    '-chardev', 'socket,path=' + options.qgaUnixSocket + ',server=on,wait=off,id=qga0',
    '-device', 'virtserialport,chardev=qga0,bus=virtio-serial0.0,name=org.qemu.guest_agent.0'
  ]

  const sharedUserFolder = deviceInfo.deviceType !== '2in1' ? [] :
    ["-virtfs", "local,path=/storage/Users/currentUser,mount_tag=usershare,security_model=mapped-file,fmode=0666,dmode=0777"]

  // HarmonyOS app进程fd配额有限，过多hostfwd监听socket会耗尽fd，导致VNC init失败→exit(1)
  // 保守阈值：映射数>4时禁用VNC，避免vnc_init_func中的socket()返回EMFILE
  const MAX_PORT_MAPPING_WITH_VNC = 4
  let vncEnabled = options.vncEnabled
  if (vncEnabled && options.portMapping.length > MAX_PORT_MAPPING_WITH_VNC) {
    vncEnabled = false
    hilog.warn(0x0000, 'startVm', 'Port mapping count %{public}d exceeds VNC-safe limit %{public}d, disabling VNC to prevent fd exhaustion crash',
      options.portMapping.length, MAX_PORT_MAPPING_WITH_VNC)
  }

  const vnc: string[] = vncEnabled ? [
    '-vnc', `${options.vncPortMode === 'lan' ? '0.0.0.0' : '127.0.0.1'}:${options.vncPort - 5900}`,
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
    try {
      fs.unlinkSync(options.serialUnixSocket)
    } catch (e) {
      hilog.warn(0x0000, 'startVm', 'Failed to unlink serial socket: %{public}s', (e as Error).message ?? 'unknown')
    }
  }
  if (fs.accessSync(options.qmpUnixSocket, fs.AccessModeType.EXIST)) {
    try {
      fs.unlinkSync(options.qmpUnixSocket)
    } catch (e) {
      hilog.warn(0x0000, 'startVm', 'Failed to unlink qmp socket: %{public}s', (e as Error).message ?? 'unknown')
    }
  }
  if (fs.accessSync(options.qgaUnixSocket, fs.AccessModeType.EXIST)) {
    try {
      fs.unlinkSync(options.qgaUnixSocket)
    } catch (e) {
      hilog.warn(0x0000, 'startVm', 'Failed to unlink qga socket: %{public}s', (e as Error).message ?? 'unknown')
    }
  }
  if (!fs.accessSync(options.sharedFolder, fs.AccessModeType.EXIST)) {
    fs.mkdirSync(options.sharedFolder)
  }

  const started: boolean = napi.startVM({
    argsLines: args.join('\n'),
    unixSocket: options.serialUnixSocket,
    qmpSocket: options.qmpUnixSocket
  });
  return started === true
}

export { startVm, VmOptions }
