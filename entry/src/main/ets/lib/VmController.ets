import { fileIo as fs } from '@kit.CoreFileKit'
import napi from 'libentry.so'
import { Emulator, PortMapping, DataDisk } from '../model/Emulator'
import deviceInfo from '@ohos.deviceInfo'
import { startVm, VmOptions } from './startVm'
import { startQmpEventListener, stopQmpEventListener, QmpEventType, QmpEventData, getQmpEventListener } from './QmpEventListener'
import QmpClient, { QmpStatusResult } from './QmpClient'
import { hilog } from '@kit.PerformanceAnalysisKit'
import appOption, { savePreference } from '../model/appOption'
import preference from '@ohos.data.preferences'
import { UIContext } from '@kit.ArkUI'
import { QemuAgent } from './QemuAgent'
import { common, Want } from '@kit.AbilityKit'
import { QemuAgentManager, AgentPriority } from './QemuAgentManager'

class Mutex {
  private queue: Promise<void> = Promise.resolve();

  public async lock(): Promise<() => void> {
    let release: () => void = () => { };
    const currentLock = new Promise<void>(resolve => {
      release = resolve;
    });

    const previousLock = this.queue;
    this.queue = this.queue.then(() => currentLock);

    await previousLock;

    return release;
  }

  async lockAsync<T>(callback: () => Promise<T>): Promise<T> {
    const unlock = await this.lock();
    try {
      return await callback();
    } finally {
      unlock();
    }
  }
}

const DOMAIN = 0x0000;

export class VmController {
  private static instance: VmController;
  private currentUiContext: UIContext | null = null; // Store context for event handling
  private lock: Mutex = new Mutex();
  private portCheckTimer: number = -1;

  private controlClient: QmpClient | null = null;
  private expectManualPause: boolean = false; // [Fix] 显式标志：仅当用户点击暂停时才为真

  public static getInstance(): VmController {
    if (!VmController.instance) {
      VmController.instance = new VmController();
    }
    return VmController.instance;
  }

  /**
   * 销毁资源
   * [修复] 确保所有监听器和定时器在 VM 停止或应用销毁时被清理
   */
  async dispose(): Promise<void> {
    hilog.info(DOMAIN, 'VmController', '正在销毁 VmController 资源...');

    // 1. 停止 QMP 监听器
    try {
      await stopQmpEventListener();
    } catch (e) { }

    // 2. 清理端口检查定时器
    this.stopPortCheck();

    // 3. 强制释放 QGA 连接
    try {
      await QemuAgentManager.release('VmController');
    } catch (e) { }

    this.currentUiContext = null;
    AppStorage.setOrCreate(appOption.isVmSwitching, false);
  }

  /**
   * 停止当前运行的虚拟机
   * 包含完整的优雅关机流程 (QGA -> QMP -> Force Kill)
   */
  public async shutdownVM(): Promise<boolean> {
    return this.lock.lockAsync(async () => {
      hilog.info(DOMAIN, 'VmController', 'Requesting VM shutdown...');
      const appTempDir = AppStorage.get(appOption.appTempDir) as string;
      try {
        const success = await this.gracefulShutdownAndWait(appTempDir, 30000);
        if (success) {
          // Double check if process is really dead
          const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
          const pidFile = vmBaseDir + '/qemu.pid';
          if (!napi.checkQemuAlive(pidFile)) {
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
            AppStorage.setOrCreate(appOption.currentRunningEmulator, '');

            // [手机端特化] 正常关机成功 -> 退出 App
            const isPhone = deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'default';
            if (isPhone && this.currentUiContext) {
              hilog.info(DOMAIN, 'VmController', '手机端正常关机: 退出应用');
              (this.currentUiContext.getHostContext() as common.UIAbilityContext).terminateSelf();
            }
          }
        }
        return success;
      } catch (e) {
        hilog.error(DOMAIN, 'VmController', 'shutdownVM exception: %{public}s', JSON.stringify(e));
        return false;
      }
    });
  }

  /**
   * 重启 VM (QGA -> QMP)
   */
  public async rebootVM(): Promise<boolean> {
    return this.lock.lockAsync(async () => {
      hilog.info(DOMAIN, 'VmController', 'Requesting VM reboot...');
      // [Fix] 重启开始时，重置手动暂停标志，防止残留
      this.expectManualPause = false;
      const appTempDir = AppStorage.get(appOption.appTempDir) as string;
      const vmBaseDir: string = AppStorage.get(appOption.vmBaseDir) as string;
      const pidFilePath: string = vmBaseDir + '/qemu.pid';

      try {
        let rebootSent = false;

        // 步骤 1: 尝试 QGA
        // [Smart Skip] 如果此时管理器报告未连接，说明心跳探测已判定 QGA 不可用，直接跳过以节省时间
        const agentStatus = QemuAgentManager.getStatus();
        if (agentStatus.isConnected) {
          try {
            hilog.info(DOMAIN, 'VmController', '检测到 QGA 已连接，尝试优雅重启...');
            const qgaAgent = await QemuAgentManager.acquire('VmController_Reboot', AgentPriority.HIGH, 3000);
            if (qgaAgent) {
              // 优先尝试 /sbin/reboot 脚本
              const pid = await qgaAgent.exec('/sbin/reboot', []);
              if (pid !== null) {
                rebootSent = true;
              } else {
                // 回退到 RPC 重启
                rebootSent = await qgaAgent.reboot();
              }
              await QemuAgentManager.release('VmController_Reboot');
            }
          } catch (e) {
            hilog.warn(DOMAIN, 'VmController', 'QGA 重启尝试失败: %{public}s', JSON.stringify(e));
          }
        } else {
          hilog.info(DOMAIN, 'VmController', 'QGA 未连接，跳过 QGA 重启尝试');
        }

        // 步骤 2: 尝试 QMP
        if (!rebootSent) {
          const qmpSocketPath = appTempDir + '/qmp_socket';
          hilog.info(DOMAIN, 'VmController', '准备发送 QMP 重置: %{public}s', qmpSocketPath);

          try {
            const client = await this.getControlClient(qmpSocketPath);
            if (client) {
              // 挂起心跳，避免干扰
              getQmpEventListener()?.pauseQuery();

              const success = await client.systemReset();
              if (success) {
                rebootSent = true;
                hilog.info(DOMAIN, 'VmController', '✓ QMP system_reset 指令已确认');
              }

              getQmpEventListener()?.resumeQuery();
            }
          } catch (e) {
            hilog.error(DOMAIN, 'VmController', 'QMP 重置异常: %{public}s', JSON.stringify(e));
            getQmpEventListener()?.resumeQuery();
          }
        }

        if (rebootSent) {
          hilog.info(DOMAIN, 'VmController', '重启指令已发送');
          // [优化] Soft Reset 实际上 VM 仍在运行，不需要切换到 REBOOTING 状态造成 UI 阻塞
          // 只有在需要 "硬重启" (Process Kill -> Start) 时才需要中间状态
          // 保持 RUNNING 状态让用户可以继续操作（如强制关机）
          // [Fix] 强制更新一次状态，确保防止之前的 UI 抖动
          AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
          return true;
        }
        return false;
      } catch (e) {
        hilog.error(DOMAIN, 'VmController', 'rebootVM 发生异常: %{public}s', JSON.stringify(e));
        return false;
      }
    });
  }

  /**
   * 启动虚拟机 (对外公开接口，带锁保护)
   */
  public async startVM(item: Emulator, uiContext: UIContext): Promise<void> {
    return this.lock.lockAsync(async () => {
      await this.internalStartVM(item, uiContext);
    });
  }

  /**
   * 内部启动逻辑 (无锁版本)
   * 用于被 startVM 或其它已持锁的方法 (如 hardResetVM) 调用
   */
  private async internalStartVM(item: Emulator, uiContext: UIContext): Promise<void> {
    this.currentUiContext = uiContext;
    // [Fix] 每次启动新 VM 前，强制重置手动暂停标志，确保状态干净
    this.expectManualPause = false;
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
      // P1-13: 如果超时 (30s) 且未能成功退出，则抛出异常中止启动，防止数据损坏
      const shutdownSuccess = await this.gracefulShutdownAndWait(appTempDir, 30000);
      if (!shutdownSuccess) {
        // 获取宿主 Context 以加载资源
        const resourceManager = this.currentUiContext!!.getHostContext()!!.resourceManager;
        throw new Error(resourceManager.getStringSync($r('app.string.msg_shutdown_timeout').id));
      }

      // P1-08修复: 增加端口范围验证 (1-65535)
      const invalidPorts = item.portMapping.filter((it: PortMapping) => it.host!! < 1 || it.host!! > 65535);
      if (invalidPorts.length > 0) {
        throw new Error(`无效的端口配置: ${invalidPorts.map(it => it.host).join(', ')}。端口必须在 1-65535 范围内。`);
      }

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

      // 获取数据盘路径（如果开启了挂载）
      let dataDiskPath: string | undefined = undefined;
      if (item.dataDiskId && item.mountDataDisk) {
        const dataDisks = (AppStorage.get(appOption.dataDisks) as DataDisk[]) || [];
        const selectedDisk = dataDisks.find(d => d.id === item.dataDiskId);
        if (selectedDisk) {
          dataDiskPath = selectedDisk.path;
        }
      }

      if (appTempDir) {
        // [修复] 启动新进程前，物理清理旧的 Socket 文件，防止残留进程导致通信污染
        const socketFiles = [
          appTempDir + '/qmp_socket',
          appTempDir + '/qmp_socket_ui',
          appTempDir + '/qga_socket',
          appTempDir + '/serial_socket'
        ];
        socketFiles.forEach(path => {
          try {
            if (fs.accessSync(path, fs.AccessModeType.EXIST)) {
              fs.unlinkSync(path);
              hilog.info(DOMAIN, 'VmController', '启动前清理旧 Socket 文件: %{public}s', path);
            }
          } catch (e) {
            hilog.warn(DOMAIN, 'VmController', '清理 Socket 文件失败: %{public}s', path);
          }
        });
      }

      // 0. 重置底层管理器
      await QemuAgentManager.reset();

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
        vncWebSocketPort: vncPort,
        dataDiskPath: dataDiskPath
      });

      // 更新状态
      AppStorage.setOrCreate(appOption.currentRunningEmulator, item.id);
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');

      // 启动 QMP 监听 (注意：这里使用 UI 专用 Socket，避免与控制指令冲突)
      setTimeout(async () => {
        try {
          const qmpSocketPath = appTempDir + '/qmp_socket_ui';
          await startQmpEventListener(qmpSocketPath,
            // 1. 事件回调
            (event, data) => {
              this.handleQmpEvent(event, data);
            },
            // 2. 断开连接回调
            () => {
              hilog.warn(DOMAIN, 'VmController', 'QMP 连接断开，检查 VM 存活状态...');
              const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
              if (vmBaseDir) {
                const pidFile = vmBaseDir + '/qemu.pid';
                // 如果 QMP 断开且进程不存在，说明 VM 已意外退出或关机
                if (!napi.checkQemuAlive(pidFile)) {
                  hilog.info(DOMAIN, 'VmController', '检测到 VM 进程已退出，更新状态为 SHUTDOWN');
                  this.handleQmpEvent('SHUTDOWN', undefined);
                }
              }
            }
          );
          AppStorage.setOrCreate(appOption.isVmSwitching, false);

          // 启动动态端口检查
          this.startPortCheck(item);
        } catch (e) {
          hilog.error(DOMAIN, 'VmController', 'QMP 重连异常: %{public}s', JSON.stringify(e));
          AppStorage.setOrCreate(appOption.isVmSwitching, false);
        }
      }, 500);

    } catch (e) {
      // P1-07 & P1-12修复: 启动失败时清理状态，并优化错误提示
      hilog.error(DOMAIN, 'VmController', '启动失败: %{public}s', JSON.stringify(e));
      AppStorage.setOrCreate(appOption.isVmSwitching, false);
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
      AppStorage.setOrCreate(appOption.currentRunningEmulator, '');

      const errorMsg = (e instanceof Error) ? e.message : JSON.stringify(e);
      uiContext.showAlertDialog({
        title: $r('app.string.msg_start_vm_confirm'),
        message: `启动失败: ${errorMsg}`,
        autoCancel: true,
        alignment: DialogAlignment.Center,
        buttons: [{ value: $r('app.string.setting_generic_confirm'), action: () => { } }]
      });
    }
  }

  /**
   * 恢复虚拟机 (QMP cont)
   */
  public async resumeVM(): Promise<void> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string;
    const qmpSocket = appTempDir + '/qmp_socket';

    return this.lock.lockAsync(async () => {
      try {
        const client = await this.getControlClient(qmpSocket);
        if (client) {
          // 挂起心跳屏蔽
          getQmpEventListener()?.pauseQuery();

          const success = await client.cont();
          if (success) {
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
            hilog.info(DOMAIN, 'VmController', '✓ VM Resume 指令成功执行');
          } else {
            throw new Error('VM Resume 指令执行失败');
          }

          getQmpEventListener()?.resumeQuery();
        } else {
          throw new Error('无法建立 QMP 控制连接');
        }
      } catch (e) {
        getQmpEventListener()?.resumeQuery();
        hilog.error(DOMAIN, 'VmController', 'Resume Exception: %{public}s', JSON.stringify(e));
        throw e as Error;
      }
    });
  }

  /**
   * 强制终止虚拟机进程 (Private Helper)
   * 策略: 尝试 QMP quit (500ms) -> 失败则直接 NAPI Kill -> 等待 PID 消失
   */
  private async killVM(appTempDir: string, vmBaseDir: string): Promise<void> {
    const pidFile = vmBaseDir + '/qemu.pid';
    let quitSuccess = false;

    // 1. 尝试礼貌退出 (QMP Quit) - 给 1s 宽限期
    const qmpSocket = appTempDir + '/qmp_socket';
    try {
      const qmpClient = await this.getControlClient(qmpSocket);
      if (qmpClient) {
        await qmpClient.quit();
        quitSuccess = true;
        hilog.info(DOMAIN, 'VmController', 'QMP Quit sent via ControlClient');
      }
    } catch (ignore) {
      hilog.warn(DOMAIN, 'VmController', 'QMP Quit attempt failed');
    }

    // 2. 等待进程退出 (如果 QMP 成功) 或 直接强杀
    const monitorStart = Date.now();
    while (napi.checkQemuAlive(pidFile)) {
      if (Date.now() - monitorStart > (quitSuccess ? 5000 : 0)) { // 如果 QMP 成功给 5s，否则立即杀
        hilog.warn(DOMAIN, 'VmController', 'Process still alive, executing FORCE KILL');
        napi.killQemuProcess(pidFile); // NAPI Direct Kill

        // 强杀后物理清理 Socket 文件（沉降机制）
        const socketFiles = [
          appTempDir + '/qmp_socket',
          appTempDir + '/qga_socket'
        ];
        socketFiles.forEach(s => {
          try {
            if (fs.accessSync(s, fs.AccessModeType.EXIST)) fs.unlinkSync(s);
          } catch (e) { }
        });

        // 杀完强制等待确保释放
        await new Promise<void>(resolve => setTimeout(resolve, 1000));
        break;
      }
      await new Promise<void>(resolve => setTimeout(resolve, 200));
    }
    // 强制清理控制客户端连接引用
    this.controlClient = null;
  }

  /**
   * 强制重置 (Hard Reset: Kill -> Start)
   * 彻底解决 "卡死" 问题的终极手段
   * @param uiContext 可选的 UIContext，用于在内部 Context 丢失时进行恢复
   */
  public async hardResetVM(uiContext?: UIContext): Promise<void> {
    // 1. 获取必要上下文 (优先使用传入的 Context，其次使用缓存的)
    const context = uiContext || this.currentUiContext;

    if (!context) {
      throw new Error('UIContext not initialized');
    }
    const appTempDir = AppStorage.get(appOption.appTempDir) as string;
    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;
    const currentRunningId = AppStorage.get(appOption.currentRunningEmulator) as string;
    const emulators = AppStorage.get(appOption.emulators) as Emulator[];
    const emulator = emulators.find(e => e.id === currentRunningId);

    if (!emulator) {
      throw new Error('VM config not found');
    }

    return this.lock.lockAsync(async () => {
      try {
        hilog.info(DOMAIN, 'VmController', 'Executing Hard Reset (Kill -> Start)');
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'REBOOTING');
        AppStorage.setOrCreate(appOption.isVmSwitching, true);

        const isPhone = deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'default';

        if (isPhone && context) {
          // [手机端特化] 为了彻底重置 QEMU 线程，必须重启 App
          hilog.info(DOMAIN, 'VmController', '手机端硬重置: 执行 App 重启策略');

          // 1. 保存目标 VM ID 到临时启动项 (确保重启后自动启动同一个 VM)
          await savePreference(appOption.temporaryStartEmulator, emulator.id, context);

          // 2. 触发应用重启
          const abilityContext = context.getHostContext() as common.UIAbilityContext;
          const want: Want = {
            bundleName: abilityContext.abilityInfo.bundleName,
            abilityName: abilityContext.abilityInfo.name
          };
          (abilityContext.getApplicationContext() as common.ApplicationContext).restartApp(want);

        } else {
          // [PC/平板] 保持原有逻辑: 杀进程 -> 启动新进程

          // 2. 强制杀进程并清理
          await this.killVM(appTempDir, vmBaseDir);

          // 3. 修复: 更新当前上下文并使用其启动 VM
          if (uiContext) {
            this.currentUiContext = uiContext;
          }
          // 启动新 VM (使用内部无锁方法，防止嵌套死锁)
          await this.internalStartVM(emulator, context);
        }

      } catch (e) {
        hilog.error(DOMAIN, 'VmController', 'Hard Reset failed: %{public}s', JSON.stringify(e));
        AppStorage.setOrCreate(appOption.isVmSwitching, false);
        throw e as Error;
      }
    });
  }

  /**
   * 强制关机 (Force Power Off: Kill -> Update Status)
   */
  public async forcePowerOff(): Promise<void> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string;
    const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string;

    return this.lock.lockAsync(async () => {
      try {
        hilog.info(DOMAIN, 'VmController', 'Executing Force Power Off (Kill)');

        // 执行强制杀进程
        await this.killVM(appTempDir, vmBaseDir);

        // 强制更新状态
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
        hilog.info(DOMAIN, 'VmController', 'Force Power Off completed, status set to SHUTDOWN');

        // [手机端特化] 强制关机 -> 退出 App
        const isPhone = deviceInfo.deviceType === 'phone' || deviceInfo.deviceType === 'default';
        if (isPhone && this.currentUiContext) {
          hilog.info(DOMAIN, 'VmController', '手机端强制关机: 退出应用');
          (this.currentUiContext.getHostContext() as common.UIAbilityContext).terminateSelf();
        }

      } catch (e) {
        hilog.error(DOMAIN, 'VmController', 'Force Power Off failed: %{public}s', JSON.stringify(e));
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
      }
    });
  }

  /**
   * 暂停虚拟机 (QMP stop)
   */
  public async pauseVM(): Promise<void> {
    const appTempDir = AppStorage.get(appOption.appTempDir) as string;
    const qmpSocket = appTempDir + '/qmp_socket';

    return this.lock.lockAsync(async () => {
      try {
        const client = await this.getControlClient(qmpSocket);
        if (client) {
          // 挂起心跳屏蔽
          getQmpEventListener()?.pauseQuery();

          // [Fix] 发送暂停指令前，设置预期标志
          this.expectManualPause = true;

          const success = await client.stop();
          if (success) {
            // 注意：这里更新状态可能被事件回调覆盖，但由于标志位存在，逻辑是安全的
            AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED');
            hilog.info(DOMAIN, 'VmController', '✓ VM Pause 指令成功执行');
          } else {
            this.expectManualPause = false; // 失败要在回滚
            throw new Error('VM Pause 指令执行失败');
          }

          getQmpEventListener()?.resumeQuery();
        } else {
          throw new Error('无法建立 QMP 控制连接');
        }
      } catch (e) {
        getQmpEventListener()?.resumeQuery();
        hilog.error(DOMAIN, 'VmController', 'Pause Exception: %{public}s', JSON.stringify(e));
        throw e as Error;
      }
    });
  }

  private handleQmpEvent(event: QmpEventType, data: QmpEventData | undefined): void {
    hilog.info(DOMAIN, 'VmController', 'QMP Event: %{public}s', event);
    switch (event) {
      case 'SHUTDOWN':
        // 检查是否正在切换 VM，如果是则跳过状态更新
        const isVmSwitching = AppStorage.get(appOption.isVmSwitching) as boolean;
        if (isVmSwitching) {
          hilog.info(DOMAIN, 'VmController', '检测到 VM 切换/重置进行中，跳过 SHUTDOWN 状态清理');
          return;
        }

        // 保存 Last ID
        const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
        if (currentRunning) {
          AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
        }
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'SHUTDOWN');
        AppStorage.setOrCreate(appOption.currentRunningEmulator, '');

        // 自动清理资源
        this.dispose();
        break;
      case 'RESET':
        hilog.info(DOMAIN, 'VmController', 'QMP RESET event received');
        // [调整] 手机端与 PC 端保持一致：仅更新状态为 RUNNING，不重启 App
        // 这表示 VM 内部发生了软重启
        hilog.info(DOMAIN, 'VmController', 'RESET 事件: 恢复状态为 RUNNING');
        this.expectManualPause = false; // 重置暂停标志
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
        break;
      case 'STOP':
        // [修复] 仅当确认为用户手动暂停时，才允许切换到 PAUSED 状态
        // 任何其他的 STOP 事件（如 Reboot/Reset 过程中的瞬态）都应被忽略，维持 RUNNING 状态
        hilog.info(DOMAIN, 'VmController', '收到 STOP 事件. expectManualPause=%{public}s, CurrentStatus=%{public}s',
          this.expectManualPause, AppStorage.get(appOption.currentEmulatorStatus));

        if (this.expectManualPause) {
          hilog.info(DOMAIN, 'VmController', '确认手动暂停 (STOP -> PAUSED)');
          AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'PAUSED');
          this.expectManualPause = false; // 消费标志
        } else {
          hilog.warn(DOMAIN, 'VmController', '忽略非预期的 STOP 事件 (系统自动产生)，维持当前状态');
        }
        break;
      case 'RESUME':
        hilog.info(DOMAIN, 'VmController', 'RESUME 事件: 恢复状态为 RUNNING');
        this.expectManualPause = false; // 确保清空
        AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING');
        break;
    }
  }

  /**
   * 优雅关机并等待进程退出
   * 注意：此方法通常在 startVM 或 shutdownVM 的锁内部调用
   */
  private async gracefulShutdownAndWait(appTempDir: string, timeoutMs: number): Promise<boolean> {
    const vmBaseDir: string = AppStorage.get(appOption.vmBaseDir) as string;
    const pidFilePath: string = vmBaseDir + '/qemu.pid';

    // 检查是否有正在运行的 QEMU 进程
    const isRunning: boolean = napi.checkQemuAlive(pidFilePath);
    if (!isRunning) {
      hilog.info(DOMAIN, 'VmController', '没有正在运行的 QEMU 进程，无需关机');
      return true;
    }

    hilog.info(DOMAIN, 'VmController', '尝试优雅关机...');

    let shutdownSent = false;
    const qgaSocketPath = appTempDir + '/qga_socket';
    const qmpSocketPath = appTempDir + '/qmp_socket'; // Use Command Socket

    // Explicitly save Last ID before shutdown attempts
    const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
    if (currentRunning) {
      AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
    }

    // 步骤 1: 尝试 QGA
    // [Smart Skip] 如果心跳包探测到未连接，直接跳过 QGA 阶段，节省探测时间
    const agentStatus = QemuAgentManager.getStatus();
    if (agentStatus.isConnected) {
      try {
        const qgaAgent = await QemuAgentManager.acquire('VmController', AgentPriority.HIGH, 3000);
        if (qgaAgent) {
          hilog.info(DOMAIN, 'VmController', 'QGA 已连接，尝试执行 /sbin/poweroff...');
          try {
            await qgaAgent.exec('wall', ['System is shutting down by HiSH Manager...'])
            const pid = await qgaAgent.exec('/sbin/poweroff', []);
            if (pid !== null) {
              shutdownSent = true;
            }
          } catch (execErr) {
            hilog.warn(DOMAIN, 'VmController', '/sbin/poweroff 失败，尝试 QGA RPC');
          }

          // 步骤 1.1: 脚本失败则回退 RPC
          if (!shutdownSent) {
            try {
              shutdownSent = await qgaAgent.shutdown();
            } catch (rpcErr) {
              hilog.warn(DOMAIN, 'VmController', 'QGA RPC 关机失败');
            }
          }
          await QemuAgentManager.release('VmController');
        }
      } catch (acquireErr) {
        hilog.warn(DOMAIN, 'VmController', 'QGA 获取或执行失败');
        try { await QemuAgentManager.release('VmController'); } catch (err) { }
      }
    } else {
      hilog.info(DOMAIN, 'VmController', 'QGA 未连接，智能跳过 QGA 探测');
    }

    // 步骤 2: QGA 失败或跳过，尝试 QMP ACPI
    if (!shutdownSent) {
      try {
        hilog.info(DOMAIN, 'VmController', '尝试 QMP system_powerdown (经长连接控制通道)...');
        const qmpClient = await this.getControlClient(qmpSocketPath);
        if (qmpClient) {
          // 挂起心跳屏蔽，防止在敏感的关机阶段出现包序错乱
          getQmpEventListener()?.pauseQuery();

          const result = await qmpClient.sendCommand('system_powerdown');
          shutdownSent = result !== null;
          hilog.info(DOMAIN, 'VmController', 'QMP system_powerdown 发送结果: %{public}s', shutdownSent);

          getQmpEventListener()?.resumeQuery();
        } else {
          hilog.warn(DOMAIN, 'VmController', 'QMP 关机连接失败');
        }
      } catch (e) {
        getQmpEventListener()?.resumeQuery();
        hilog.error(DOMAIN, 'VmController', 'QMP 关机异常: %{public}s', JSON.stringify(e));
      }
    }

    if (!shutdownSent) {
      hilog.warn(DOMAIN, 'VmController', '所有优雅关机尝试失败，进入强力关机流程');
    }

    // 等待 QEMU 进程退出
    const pollInterval: number = 200;
    const startTime: number = Date.now();
    // 如果没有发送成功关机指令，则只需要等待极短时间检查是否已自动关闭，否则由调用方执行 force kill
    const actualTimeout = shutdownSent ? timeoutMs : 1000;

    while (Date.now() - startTime < actualTimeout) {
      if (!napi.checkQemuAlive(pidFilePath)) {
        hilog.info(DOMAIN, 'VmController', '✓ QEMU 进程已退出');
        return true;
      }
      await new Promise<void>(resolve => setTimeout(resolve, pollInterval));
    }

    hilog.warn(DOMAIN, 'VmController', '优雅关机未能在预期内完成 (Sent: %{public}s)', shutdownSent);
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

  /**
   * 启动动态端口检查
   */
  private startPortCheck(item: Emulator) {
    this.stopPortCheck();
    hilog.info(DOMAIN, 'VmController', '启动动态端口冲突检测...');

    this.portCheckTimer = setInterval(() => {
      const currentStatus = AppStorage.get(appOption.currentEmulatorStatus) as string;
      if (currentStatus !== 'RUNNING') {
        this.stopPortCheck();
        return;
      }

      // 检查映射端口是否被外部抢占
      const portUsed = item.portMapping.map((it: PortMapping) => it.host!!).filter((p: number) => {
        // 如果端口没被占用，说明映射可能失效了（QEMU 崩溃或被杀）
        return !napi.checkPortUsed(p);
      });

      if (portUsed.length > 0) {
        hilog.warn(DOMAIN, 'VmController', '检测到端口映射可能失效: %{public}s', JSON.stringify(portUsed));
      }
    }, 30000); // 30秒检查一次
  }

  private stopPortCheck() {
    if (this.portCheckTimer !== -1) {
      clearInterval(this.portCheckTimer);
      this.portCheckTimer = -1;
    }
  }

  /**
   * 获取或创建业务控制客户端单例
   * 显著减少由于频繁创建/销毁 Socket 导致的连接成本和时序冲突
   */
  private async getControlClient(socketPath: string): Promise<QmpClient | null> {
    if (this.controlClient) {
      // 检查连接是否存活 - 使用 1000ms 短超时进行存活探测
      if (await this.controlClient.connect(1000)) {
        return this.controlClient;
      }
      // 连接失效，准备新建
      await this.controlClient.disconnect();
      this.controlClient = null;
    }

    // 建立新连接尝试 (最多 2 次)
    for (let i = 0; i < 2; i++) {
      const client = new QmpClient(socketPath);
      if (await client.connect(2000)) {
        this.controlClient = client;
        return client;
      }
      await client.disconnect();
      if (i === 0) await new Promise<void>(r => setTimeout(r, 300)); // 失败则稍等重试
    }
    return null;
  }
}
