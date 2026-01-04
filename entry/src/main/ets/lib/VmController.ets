import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { Emulator, PortMapping } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'
import { startVm, VmOptions } from './startVm'
import { startQmpEventListener, stopQmpEventListener, QmpEventType, QmpEventData } from './QmpEventListener'
import QmpClient from './QmpClient'
import { hilog } from '@kit.PerformanceAnalysisKit'
import appOption, { savePreference } from '../model/appOption'
import preference from '@ohos.data.preferences'
import { UIContext } from '@kit.ArkUI'
import { QemuAgent } from './QemuAgent'
import { common, Want } from '@kit.AbilityKit'

const DOMAIN = 0x0000;

export class VmController {
  private static instance: VmController;
  private currentUiContext: UIContext | null = null; // Store context for event handling

  public static getInstance(): VmController {
    if (!VmController.instance) {
      VmController.instance = new VmController();
    }
    return VmController.instance;
  }

  /**
   * 启动虚拟机
   */
  async startVM(item: Emulator, uiContext: UIContext): Promise<void> {
    this.currentUiContext = uiContext;
    try {
      hilog.info(DOMAIN, 'VmController', '准备启动虚拟机: %{public}s (ID: %{public}s)', item.name, item.id);

      // 手机端切换优化：如果当前有 VM 运行，则通过重启应用来实现干净的切换
      const isMobile = deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'default';
      const currentStatus = AppStorage.get(appOption.currentEmulatorStatus) as string;
      const isVmRunning = currentStatus && currentStatus !== 'SHUTDOWN' && currentStatus !== '';

      if (isMobile && isVmRunning && AppStorage.get(appOption.currentRunningEmulator) !== item.id) {
        hilog.info(DOMAIN, 'VmController', '手机端检测到 VM 运行中，执行重启切换策略');
        const abilityContext = uiContext.getHostContext() as common.UIAbilityContext;
        const appContext = abilityContext.getApplicationContext();
        // 1. 保存目标 VM ID 到临时启动项
        await savePreference(appOption.temporaryStartEmulator, item.id, uiContext);
        // 2. 触发应用重启
        const want: Want = {
          bundleName: abilityContext.abilityInfo.bundleName,
          abilityName: abilityContext.abilityInfo.name
        };
        appContext.restartApp(want);
        return;
      }

      // 设置 VM 切换标志
      AppStorage.setOrCreate(appOption.isVmSwitching, true);

      // 停止旧的 QMP 监听器
      try {
        await stopQmpEventListener();
      } catch (e) {
        hilog.warn(DOMAIN, 'VmController', '停止 QMP 监听器异常: %{public}s', JSON.stringify(e));
      }

      const appTempDir = AppStorage.get(appOption.appTempDir) as string;
      const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
      const kernelFile = AppStorage.get(appOption.kernel) as string;
      const sharedFolder = AppStorage.get(appOption.sharedHost) as string;

      // 尝试优雅关闭当前运行的虚拟机
      await this.gracefulShutdownAndWait(appTempDir, 30000);

      // 检查端口占用
      const portUsed = item.portMapping.map((it: PortMapping) => it.host!!).filter((p: number) => napi.checkPortUsed(p));
      const portMapping = item.portMapping.filter((it: PortMapping) => portUsed.indexOf(it.host!!) < 0);

      AppStorage.setOrCreate(appOption.portUsedByOthers, portUsed);

      // VNC配置
      const appContext = uiContext.getHostContext()!!.getApplicationContext();
      const appPref = await preference.getPreferences(appContext, appOption.preferenceName);
      const vncEnabledPref = await appPref.get(appOption.vncEnabled, true);
      const vncEnabled = typeof vncEnabledPref === 'boolean' ? vncEnabledPref : true;

      const vncPort = vncEnabled ? this.getFreeVncPort(60000, 65000) : undefined;
      if (vncPort) {
        AppStorage.setOrCreate('vncWebSocketPort', vncPort);
      }

      startVm({
        baseDir: vmBaseDir,
        cpu: item.cpu,
        memory: item.memory,
        portMapping: portMapping,
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

      // 启动 QMP 监听
      setTimeout(async () => {
        try {
          const qmpSocketPath = appTempDir + '/qmp_socket_ui';
          await startQmpEventListener(qmpSocketPath, (event, data) => {
            this.handleQmpEvent(event, data);
          });
          AppStorage.setOrCreate(appOption.isVmSwitching, false);
        } catch (e) {
          hilog.error(DOMAIN, 'VmController', 'QMP 重连异常: %{public}s', JSON.stringify(e));
          AppStorage.setOrCreate(appOption.isVmSwitching, false);
        }
      }, 3000);

    } catch (e) {
      hilog.error(DOMAIN, 'VmController', '启动失败: %{public}s', JSON.stringify(e));
      AppStorage.setOrCreate(appOption.isVmSwitching, false);
      
      uiContext.showAlertDialog({
        title: $r('app.string.msg_start_vm_confirm'), 
        message: `启动失败: ${JSON.stringify(e)}`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        buttons: [{ value: $r('app.string.setting_generic_confirm'), action: () => {} }]
      });
    }
  }

  /**
   * 恢复虚拟机 (QMP cont)
   */
  async resumeVM(): Promise<void> {
     const appTempDir = AppStorage.get(appOption.appTempDir) as string;
     const qmpSocket = appTempDir + '/qmp_socket'; // Use Command Socket

     // Explicitly retry connection
     for (let attempt = 0; attempt < 3; attempt++) {
       const client = new QmpClient(qmpSocket);
       try {
         if (await client.connect()) {
           await client.sendCommand('cont');
           await client.disconnect();
           AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
           return;
         }
       } catch (e) {
         hilog.warn(DOMAIN, 'VmController', 'Resume attempt %{public}d failed: %{public}s', attempt + 1, JSON.stringify(e));
       }
       // Wait short duration
       await new Promise<void>((resolve: () => void) => setTimeout(resolve, 500));
     }
     hilog.error(DOMAIN, 'VmController', 'Resume failed after 3 attempts');
  }

  private handleQmpEvent(event: QmpEventType, data: QmpEventData | undefined): void {
    hilog.info(DOMAIN, 'VmController', 'QMP Event: %{public}s', event);
    switch (event) {
      case 'SHUTDOWN':
        // 保存 Last ID
        const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
        if (currentRunning) {
             AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
        }
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
        AppStorage.setOrCreate(appOption.currentRunningEmulator, '');
        break;
      case 'RESET':
        // 重启 App - 仅当 currentUiContext 有效时
        if (this.currentUiContext) {
            const context = this.currentUiContext.getHostContext() as common.UIAbilityContext;
            const want: Want = {
                bundleName: context.abilityInfo.bundleName,
                abilityName: context.abilityInfo.name
            };
            try {
               (context.getApplicationContext() as common.ApplicationContext).restartApp(want);
            } catch(e) {
               hilog.error(DOMAIN, 'VmController', 'Restart App failed: %{public}s', JSON.stringify(e));
            }
        }
        break;
      case 'STOP':
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED');
        break;
      case 'RESUME':
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
        break;

    }
  }

  private async gracefulShutdownAndWait(appTempDir: string, timeoutMs: number): Promise<boolean> {
    const vmBaseDir: string = AppStorage.get(appOption.vmBaseDir) as string;
    const pidFilePath: string = vmBaseDir + '/qemu.pid';
    
    // 检查是否有正在运行的 QEMU 进程
    const isRunning: boolean = napi.checkQemuAlive(pidFilePath);
    if (!isRunning) {
      hilog.info(DOMAIN, 'EmulatorListGrid', '没有正在运行的 QEMU 进程，无需关机');
      return true;
    }
    
    hilog.info(DOMAIN, 'EmulatorListGrid', '尝试优雅关机...');
    
    let shutdownSent = false;
    const qgaSocketPath = appTempDir + '/qga_socket';
    const qmpSocketPath = appTempDir + '/qmp_socket'; // Use Command Socket

    // Explicitly save Last ID before shutdown attempts
    const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
    if (currentRunning) {
        AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
    }
    
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
    const pollInterval: number = 500; // 每 500ms 检查一次
    const startTime: number = Date.now();
    
    while (Date.now() - startTime < timeoutMs) {
      const stillRunning: boolean = napi.checkQemuAlive(pidFilePath);
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
  
  // Helper for VNC port
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
}
