import { fileIo as fs } from '@kit.CoreFileKit'
import { Emulator, RootFilesystem, PortMapping } from '../model/Emulator';
import { RepeatGrid } from './RepeatGrid';
import { util } from '@kit.ArkTS';
import appOption, { savePreference } from '../model/appOption';
import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI';
import copyFile from '../lib/copyFile';
import napi from 'libentry.so';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want, bundleManager } from '@kit.AbilityKit';
import EmulatorItem from './EmulatorItem';
import PowerManagementContent from './PowerManagementContent';
import ImageManagementContent from './ImageManagementContent';
import deviceInfo from '@ohos.deviceInfo';
import preference from '@ohos.data.preferences';
import { startVm } from '../lib/startVm';
import { startQmpEventListener, stopQmpEventListener, QmpEventType, QmpEventData } from '../lib/QmpEventListener';
import QmpClient from '../lib/QmpClient';
import { QemuAgent } from '../lib/QemuAgent';

const DOMAIN = 0x0000;

@Component
export default struct EmulatorListGrid {
  @State selectedId?: string = undefined
  @State tempEmulatorName: string = ''
  @State tempRootfsName: string = ''
  @Watch('onEmulatorsChange') @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @StorageLink(appOption.rootFilesystems) rootFilesystems: RootFilesystem[] = []
  @State displayEmulators: Emulator[] = []
  @StorageLink(appOption.defaultStartEmulator) defaultStart?: string = undefined
  @StorageProp(appOption.currentRunningEmulator) currentRunning?: string = undefined
  @StorageProp(appOption.bundleInfo) bundleInfo?: bundleManager.BundleInfo = undefined
  @Require onEditEmulator: (item: Emulator, edit: boolean) => void
  @Prop specifiedBreak?: string = undefined
  emulatorNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_copy'),
      secondaryTitle: $r('app.string.dialog_copy_subtitle'),
      contentBuilder: () => {
        this.buildInputEmulatorName()
      }
    })
  })
  rootfsNameController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_export_rootfs'),
      secondaryTitle: $r('app.string.dialog_export_subtitle'),
      contentBuilder: () => {
        this.buildInputRootfsName()
      }
    })
  })
  copyProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.progress_copying'),
    }),
    autoCancel: false
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.progress_exporting'),
    }),
    autoCancel: false
  })
  powerManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.dialog_power_management'),
      contentBuilder: () => {
        this.buildPowerManagement();
      }
    })
  })
  imageManagementController: CustomDialogController | null = null
  @State selectedEmulatorForImage: Emulator | null = null
  filesDir = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  promptAction = this.getUIContext().getPromptAction()

  aboutToAppear(): void {
    this.onEmulatorsChange()
  }

  @Builder
  buildInputEmulatorName() {
    Column() {
      TextInput({
        text: this.tempEmulatorName,
        placeholder: $r('app.string.placeholder_emulator_name')
      })
        .onChange((value) => {
          this.tempEmulatorName = value;
        })
      Button($r('app.string.btn_done'))
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateEmulatorName())
        .onClick(async () => {
          this.emulatorNameController.close()
          await this.copyEmulatorItem()
        })
    }
  }

  @Builder
  buildInputRootfsName() {
    Column() {
      TextInput({
        text: this.tempRootfsName,
        placeholder: $r('app.string.placeholder_export_name')
      })
        .onChange((value) => {
          this.tempRootfsName = value;
        })
      Button($r('app.string.btn_done'))
        .margin({ top: 10 })
        .width('100%')
        .enabled(this.validateRootfsName())
        .onClick(async () => {
          this.rootfsNameController.close()
          await this.exportToRootfs()
        })
    }
  }

  async exportToRootfs() {
    const src = this.emulators.find(it => it.id === this.selectedId)!!

    const id = util.generateRandomUUID()

    const base = AppStorage.get(appOption.rootfsBaseDir) as string;
    const target = base + '/' + id + src.rootFilesystem.substring(src.rootFilesystem.lastIndexOf('.'))

    const srcRootfs = src.rootFilesystem

    this.exportProgress.open()
    try {
      await copyFile(srcRootfs, target)

      const rootfs: RootFilesystem = {
        id,
        name: this.tempRootfsName.trim(),
        path: target
      }
      this.rootFilesystems.push(rootfs)

      await savePreference(appOption.rootFilesystems, this.rootFilesystems, this.getUIContext())
    } finally {
      this.exportProgress.close()
    }
    this.promptAction.showToast({
      message: $r('app.string.msg_export_complete'),
      duration: 3000
    })
  }

  validateRootfsName(): boolean {
    const name = this.tempRootfsName.trim();
    if (name.length <= 0) {
      return false
    }
    const used = this.rootFilesystems.findIndex(it => it.name === name) >= 0
    if (used) {
      return false
    }
    return true
  }

  validateEmulatorName(): boolean {
    const name = this.tempEmulatorName.trim();
    if (name.length <= 0) {
      return false
    }
    const used = this.emulators.findIndex(it => it.name === name) >= 0
    if (used) {
      return false
    }
    return true
  }

  @Builder
  buildEmulatorListItem(emulator: Emulator) {
    EmulatorItem({
      emulator: emulator,
      isRunning: emulator.id === this.currentRunning,
      isDefault: emulator.id === this.defaultStart,
      onEdit: (item) => {
        this.onEditEmulator(item, true)
      },
      onDelete: (item) => {
        if (item.id === this.currentRunning) {
          this.promptAction.showToast({ message: $r('app.string.msg_cannot_delete_running') })
        } else if (item.id === this.defaultStart) {
          this.promptAction.showToast({ message: $r('app.string.msg_cannot_delete_default') })
        } else {
          this.askForDeleteEmulator(item);
        }
      },
      onCopy: (item) => {
        this.selectedId = item.id
        this.emulatorNameController.open()
      },
      onSetDefault: (item) => {
        this.onSetDefault(item);
      },
      onStart: (item) => {
        this.askForStartEmulator(item)
      },
      onExport: async (item) => {
        // 检查是否有快照
        try {
          const result = napi.getSnapshots(item.rootFilesystem)
          const response = JSON.parse(result) as Record<string, Object>
          const snapshots = response['snapshots'] as Array<Object>
          
          if (snapshots && snapshots.length > 0) {
            this.promptAction.showDialog({
              title: $r('app.string.dialog_cannot_export'),
              message: $r('app.string.msg_export_has_snapshots'),
              buttons: [
                { text: $r('app.string.btn_got_it'), color: '#007DFF' }
              ]
            })
            return
          }
        } catch (e) {
          hilog.error(0x0000, 'EmulatorListGrid', '检查快照失败: %{public}s', JSON.stringify(e))
          // 检查失败时仍允许导出，但给出警告
        }
        
        this.selectedId = item.id
        this.rootfsNameController.open()
      },
      onPowerManage: (item) => {
        this.openPowerManageDialog()
      },
      onImageManage: (item) => {
        this.openImageManageDialog(item)
      }
    }).onClick(() => {
      this.onEditEmulator(emulator, false)
    })
  }

  askForStartEmulator(item: Emulator) {
    const isPcOrTablet = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
    
    this.getUIContext().showAlertDialog({
      title: item.name,
      message: isPcOrTablet ? $r('app.string.msg_start_vm_confirm') : $r('app.string.msg_restart_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
          }
        },
        {
          enabled: true,
          style: DialogButtonStyle.HIGHLIGHT,
          backgroundColor: $r('sys.color.warning'),
          value: $r('app.string.btn_run'),
          action: async () => {
            this.startEmulator(item);
          }
        }
      ],
    });
  }

  async startEmulator(item: Emulator) {
    const isPcOrTablet = deviceInfo.deviceType === '2in1' || deviceInfo.deviceType === 'tablet';
    
    if (isPcOrTablet) {
      // PC/平板：直接启动虚拟机
      await this.directStartVM(item);
    } else {
      // 手机：先优雅关机，再重启 HiSH
      await savePreference(appOption.temporaryStartEmulator, item.id, this.getUIContext())
      
      // 执行优雅关机（等待最多 15 秒，因为手机端用户体验需要更快响应）
      const appTempDir = AppStorage.get(appOption.appTempDir) as string;
      const gracefulSuccess = await this.gracefulShutdownAndWait(appTempDir, 15000);
      if (gracefulSuccess) {
        hilog.info(DOMAIN, 'EmulatorListGrid', '✓ 旧虚拟机已正常关机，准备重启应用');
      } else {
        hilog.warn(DOMAIN, 'EmulatorListGrid', '优雅关机失败或超时，应用重启时将强制清理');
      }
      
      await this.restartApp()
    }
  }

  private async restartApp() {
    let applicationContext = this.getUIContext().getHostContext()!!.getApplicationContext();
    let want: Want = {
      bundleName: this.bundleInfo?.name,
      abilityName: 'EntryAbility'
    };
    applicationContext.restartApp(want);
  }

  /**
   * 优雅关闭当前运行的虚拟机并等待退出
   * @param appTempDir 应用临时目录
   * @param timeoutMs 超时时间（毫秒），默认 30 秒
   * @returns 是否成功关机
   */
  private async gracefulShutdownAndWait(appTempDir: string, timeoutMs: number = 30000): Promise<boolean> {
    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
    const pidFilePath = vmBaseDir + '/qemu.pid';
    
    // 检查是否有正在运行的 QEMU 进程
    const isRunning = napi.checkQemuAlive(pidFilePath);
    if (!isRunning) {
      hilog.info(DOMAIN, 'EmulatorListGrid', '没有正在运行的 QEMU 进程，无需关机');
      return true;
    }
    
    hilog.info(DOMAIN, 'EmulatorListGrid', '尝试优雅关机...');
    
    let shutdownSent = false;
    const qgaSocketPath = appTempDir + '/qga_socket';
    const qmpSocketPath = appTempDir + '/qmp_socket_ui';
    
    // 步骤 1: 尝试 QGA 执行 /sbin/poweroff（最兼容）
    try {
      const qgaAgent = new QemuAgent(qgaSocketPath);
      const qgaConnected = await qgaAgent.connect();
      
      if (qgaConnected) {
        hilog.info(DOMAIN, 'EmulatorListGrid', 'QGA 已连接，尝试执行 /sbin/poweroff...');
        try {
          const pid = await qgaAgent.exec('/sbin/poweroff', []);
          if (pid !== null) {
            shutdownSent = true;
            hilog.info(DOMAIN, 'EmulatorListGrid', '✓ /sbin/poweroff 执行成功');
          }
        } catch (e) {
          hilog.warn(DOMAIN, 'EmulatorListGrid', '/sbin/poweroff 失败: %{public}s', JSON.stringify(e));
        }
        
        // 步骤 2: 如果 poweroff 失败，尝试 guest-shutdown
        if (!shutdownSent) {
          try {
            hilog.info(DOMAIN, 'EmulatorListGrid', '尝试 guest-shutdown...');
            const result = await qgaAgent.shutdown();
            if (result) {
              shutdownSent = true;
              hilog.info(DOMAIN, 'EmulatorListGrid', '✓ guest-shutdown 执行成功');
            }
          } catch (e) {
            hilog.warn(DOMAIN, 'EmulatorListGrid', 'guest-shutdown 失败: %{public}s', JSON.stringify(e));
          }
        }
        
        await qgaAgent.disconnect();
      } else {
        hilog.warn(DOMAIN, 'EmulatorListGrid', 'QGA 连接失败');
      }
    } catch (e) {
      hilog.warn(DOMAIN, 'EmulatorListGrid', 'QGA 异常: %{public}s', JSON.stringify(e));
    }
    
    // 步骤 3: 如果 QGA 方法都失败，使用 QMP ACPI 信号
    if (!shutdownSent) {
      try {
        hilog.info(DOMAIN, 'EmulatorListGrid', 'QGA 方法失败，尝试 QMP system_powerdown...');
        const qmpClient = new QmpClient(qmpSocketPath);
        const connected = await qmpClient.connect();
        
        if (connected) {
          const result = await qmpClient.sendCommand('system_powerdown');
          shutdownSent = result !== null;
          hilog.info(DOMAIN, 'EmulatorListGrid', 'system_powerdown 发送结果: %{public}s', shutdownSent ? '成功' : '失败');
          await qmpClient.disconnect();
        } else {
          hilog.warn(DOMAIN, 'EmulatorListGrid', 'QMP 连接失败');
        }
      } catch (e) {
        hilog.warn(DOMAIN, 'EmulatorListGrid', 'QMP 异常: %{public}s', JSON.stringify(e));
      }
    }
    
    if (!shutdownSent) {
      hilog.warn(DOMAIN, 'EmulatorListGrid', '所有优雅关机方法都失败，将使用强制终止');
      return false;
    }
    
    // 等待 QEMU 进程退出
    const pollInterval = 500; // 每 500ms 检查一次
    const startTime = Date.now();
    
    while (Date.now() - startTime < timeoutMs) {
      const stillRunning = napi.checkQemuAlive(pidFilePath);
      if (!stillRunning) {
        hilog.info(DOMAIN, 'EmulatorListGrid', '✓ QEMU 进程已正常退出（等待 %{public}d ms）', Date.now() - startTime);
        return true;
      }
      
      // 等待一段时间后再检查
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, pollInterval));
    }
    
    hilog.warn(DOMAIN, 'EmulatorListGrid', '优雅关机超时（%{public}d ms），将使用强制终止', timeoutMs);
    return false;
  }

  /**
   * PC/平板直接启动虚拟机（不重启 HiSH）
   */
  private async directStartVM(item: Emulator) {
    try {
      hilog.info(DOMAIN, 'EmulatorListGrid', '准备启动虚拟机: %{public}s (ID: %{public}s)', item.name, item.id);

      // 设置 VM 切换标志，防止 WebTerminal.onShutdown 覆盖状态
      AppStorage.setOrCreate(appOption.isVmSwitching, true);
      hilog.info(DOMAIN, 'EmulatorListGrid', '✓ 已设置 VM 切换标志');

      // 停止旧的 QMP 监听器，避免接收旧虚拟机的关机事件
      try {
        hilog.info(DOMAIN, 'EmulatorListGrid', '停止旧 QMP 监听器...');
        await stopQmpEventListener();
        hilog.info(DOMAIN, 'EmulatorListGrid', '✓ 旧 QMP 监听器已停止');
      } catch (e) {
        hilog.warn(DOMAIN, 'EmulatorListGrid', '停止 QMP 监听器异常（可忽略）: %{public}s', JSON.stringify(e));
      }

      const appTempDir = AppStorage.get(appOption.appTempDir) as string;
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
      const kernelFile = AppStorage.get(appOption.kernel) as string;
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string;

      // 尝试优雅关闭当前运行的虚拟机（先正常关机再切换）
      const gracefulSuccess = await this.gracefulShutdownAndWait(appTempDir, 30000);
      if (gracefulSuccess) {
        hilog.info(DOMAIN, 'EmulatorListGrid', '✓ 旧虚拟机已正常关机');
      } else {
        hilog.warn(DOMAIN, 'EmulatorListGrid', '优雅关机失败或超时，startVm 将强制清理旧进程');
      }

      // 检查端口占用情况
      const portUsed = item.portMapping.map(it => it.host!!).filter(p => napi.checkPortUsed(p));
      const portMapping = item.portMapping.filter(it => portUsed.indexOf(it.host!!) < 0);

      hilog.info(DOMAIN, 'EmulatorListGrid', 'host port %{public}s of PortMapping is used by others', JSON.stringify(portUsed));
      AppStorage.setOrCreate(appOption.portUsedByOthers, portUsed);

      // 读取 VNC 启用配置
      const appContext = this.getUIContext().getHostContext()!!.getApplicationContext();
      const appPref: preference.Preferences = await preference.getPreferences(appContext, appOption.preferenceName);
      const vncEnabledPref = await appPref.get(appOption.vncEnabled, true);
      const vncEnabled = typeof vncEnabledPref === 'boolean' ? vncEnabledPref : true;

      // 获取 VNC 端口
      const vncPort = vncEnabled ? this.getFreeVncPort(60000, 65000) : undefined;
      if (vncPort) {
        AppStorage.setOrCreate('vncWebSocketPort', vncPort);
      }

      // 调用 startVm（startVm 内部会清理旧进程和 socket 文件）
      startVm({
        baseDir: vmBaseDir,
        cpu: item.cpu,
        memory: item.memory,
        portMapping: portMapping,  // 使用过滤后的端口映射
        kernel: kernelFile,
        rootVda: item.rootVda,
        rootFilesystem: item.rootFilesystem,
        sharedFolder: sharedFolder,
        serialUnixSocket: appTempDir + '/serial_socket',
        sharedFolderReadonly: item.sharedFolderReadonly,
        init: item.init,
        qmpUnixSocket: appTempDir + '/qmp_socket',
        qmpUnixSocketUI: appTempDir + '/qmp_socket_ui',
        qgaUnixSocket: appTempDir + '/qga_socket',
        vncWebSocketPort: vncPort
      });

      // 更新状态
      AppStorage.setOrCreate(appOption.currentRunningEmulator, item.id);
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');

      // 延迟 3 秒后启动 QMP 监听器，确保旧进程完全退出，新进程已创建 socket 文件
      setTimeout(async (): Promise<void> => {
        try {
          const qmpSocketPath = appTempDir + '/qmp_socket_ui';
          hilog.info(DOMAIN, 'EmulatorListGrid', '启动新 QMP 监听器: %{public}s', qmpSocketPath);
          
          const started = await startQmpEventListener(qmpSocketPath, 
            (event: QmpEventType, data: QmpEventData | undefined): void => {
              hilog.info(DOMAIN, 'EmulatorListGrid', '收到 QMP 事件: %{public}s', event);
              this.handleQmpEvent(event, data);
            }
          );
          
          if (started) {
            hilog.info(DOMAIN, 'EmulatorListGrid', '✓ QMP 监听器已成功启动');
          } else {
            hilog.warn(DOMAIN, 'EmulatorListGrid', '✗ QMP 监听器启动失败，将在后台自动重试');
          }

          // QMP 连接完成后清除 VM 切换标志
          AppStorage.setOrCreate(appOption.isVmSwitching, false);
          hilog.info(DOMAIN, 'EmulatorListGrid', '✓ 已清除 VM 切换标志');
        } catch (e) {
          hilog.error(DOMAIN, 'EmulatorListGrid', 'QMP 重连异常: %{public}s', JSON.stringify(e));
          // 异常时也要清除标志
          AppStorage.setOrCreate(appOption.isVmSwitching, false);
        }
      }, 3000);

      hilog.info(DOMAIN, 'EmulatorListGrid', '虚拟机启动成功: %{public}s', item.name);
    } catch (e) {
      hilog.error(DOMAIN, 'EmulatorListGrid', '虚拟机启动失败: %{public}s', JSON.stringify(e));
      this.getUIContext().showAlertDialog({
        title: $r('app.string.dialog_confirm_delete'),
        message: `启动失败: ${JSON.stringify(e)}`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        buttons: [
          {
            value: $r('app.string.setting_generic_confirm'),
            action: () => {}
          }
        ]
      });
      // 启动失败时也要清除切换标志
      AppStorage.setOrCreate(appOption.isVmSwitching, false);
    }
  }

  /**
   * 处理 QMP 事件
   */
  private handleQmpEvent(event: QmpEventType, data: QmpEventData | undefined): void {
    hilog.info(DOMAIN, 'EmulatorListGrid', '收到 QMP 事件: %{public}s, 数据: %{public}s', 
               event, JSON.stringify(data));
    
    switch (event) {
      case 'SHUTDOWN':
        // 虚拟机关机
        hilog.info(DOMAIN, 'EmulatorListGrid', '虚拟机已关机');
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
        AppStorage.setOrCreate(appOption.currentRunningEmulator, '');
        break;
        
      case 'RESET':
        // 虚拟机重置
        hilog.info(DOMAIN, 'EmulatorListGrid', '虚拟机正在重置');
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING');
        break;
        
      case 'STOP':
        // 虚拟机暂停
        hilog.info(DOMAIN, 'EmulatorListGrid', '虚拟机已暂停');
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED');
        break;
        
      case 'RESUME':
        // 虚拟机恢复运行
        hilog.info(DOMAIN, 'EmulatorListGrid', '虚拟机已恢复运行');
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
        break;
        
      default:
        hilog.info(DOMAIN, 'EmulatorListGrid', '未处理的 QMP 事件: %{public}s', event);
    }
  }

  private getFreeVncPort(min: number, max: number): number | undefined {
    const range = max - min + 1;
    for (let i = 0; i < 100; i++) {
      const port = min + Math.floor(Math.random() * range);
      if (!napi.checkPortUsed(port)) {
        return port;
      }
    }
    return undefined;
  }

  private askForDeleteEmulator(item: Emulator) {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_confirm_delete'),
      message: $r('app.string.msg_delete_emulator_confirm'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
          }
        },
        {
          enabled: true,
          style: DialogButtonStyle.HIGHLIGHT,
          backgroundColor: $r('sys.color.warning'),
          value: $r('app.string.confirm_remove'),
          action: async () => {
            this.deleteEmulatorItem(item);
          }
        }
      ],
    });
  }

  private async onSetDefault(item: Emulator) {
    this.defaultStart = item.id;
    await savePreference(appOption.defaultStartEmulator, this.defaultStart, this.getUIContext())
  }

  async deleteEmulatorItem(item: Emulator) {

    const i = this.emulators.findIndex(it => it.id === item.id)

    const rootfs = item.rootFilesystem
    try {
      fs.unlinkSync(rootfs)
    } catch (e) {
      hilog.info(1, "EmulatorManagement", "failed to delete %{public}s", rootfs)
    }

    this.emulators.splice(i, 1)
    await savePreference(appOption.emulators, this.emulators, this.getUIContext())
  }

  async copyEmulatorItem() {

    const src = this.emulators.find(it => it.id === this.selectedId)!!

    const id = util.generateRandomUUID()

    const base = AppStorage.get(appOption.vmBaseDir) as string;
    const target = base + '/' + id + src.rootFilesystem.substring(src.rootFilesystem.lastIndexOf('.'))

    const srcRootfs = src.rootFilesystem

    this.copyProgress.open()
    try {
      await copyFile(srcRootfs, target)

      const emulator: Emulator = {
        id,
        name: this.tempEmulatorName.trim(),
        cpu: src.cpu,
        memory: src.memory,
        init: src.init,
        portMapping: src.portMapping,
        rootVda: src.rootVda,
        rootFilesystem: target,
        sharedFolderReadonly: src.sharedFolderReadonly
      }
      this.emulators.push(emulator)

      await savePreference(appOption.emulators, this.emulators, this.getUIContext())
    } finally {
      this.copyProgress.close()
    }
  }

  build() {
    Scroll() {
      RepeatGrid({
        items: this.displayEmulators as object[],
        contentBuilder: (item: object, index: number) => {
          this.buildEmulatorListItem(item as Emulator)
        },
        getKey: (item: object, index: number) => (item as Emulator).id,
        specifiedBreak: this.specifiedBreak
      })
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  openPowerManageDialog() {
    this.powerManagementController.open()
  }

  openImageManageDialog(emulator: Emulator) {
    this.selectedEmulatorForImage = emulator
    this.imageManagementController = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: $r('app.string.dialog_image_management'),
        contentBuilder: () => {
          this.buildImageManagement()
        }
      })
    })
    this.imageManagementController.open()
  }

  @Builder
  buildPowerManagement() {
    PowerManagementContent()
  }

  @Builder
  buildImageManagement() {
    if (this.selectedEmulatorForImage) {
      ImageManagementContent({ 
        emulator: this.selectedEmulatorForImage,
        isVmRunning: this.selectedEmulatorForImage.id === this.currentRunning
      })
    }
  }

  onEmulatorsChange() {
    hilog.info(1, "EmulatorManagement", "onEmulatorsChange: %{public}s", JSON.stringify(this.emulators))
    this.displayEmulators.splice(0, this.displayEmulators.length)
    setTimeout(() => {
      this.emulators.forEach(it => this.displayEmulators.push(it))
    }, 20)
  }
}
