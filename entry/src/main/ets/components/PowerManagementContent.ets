import { CustomContentDialog, LoadingDialog } from '@kit.ArkUI'
import appOption from '../model/appOption'
import QemuAgent from '../lib/QemuAgent'
import { QemuAgentManager, AgentPriority } from '../lib/QemuAgentManager'
import QmpClient, { QmpStatusResult } from '../lib/QmpClient'
import { getQmpEventListener } from '../lib/QmpEventListener'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { startVm } from '../lib/startVm'
import { VmController } from '../lib/VmController'
import { Emulator, PortMapping, DataDisk } from '../model/Emulator'
import napi from 'libentry.so'
import preference from '@ohos.data.preferences'

const DOMAIN = 0x0000

/**
 * 获取一个未被占用的随机端口 (用于 VNC WebSocket)
 */
function getFreeVncPort(min: number, max: number): number | undefined {
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
 * 电源管理组件
 * 提供关机、重启、暂停虚拟机的功能
 */
@Component
export default struct PowerManagementContent {
  @StorageProp(appOption.isQgaConnected) isConnected: boolean = false
  @State isOperating: boolean = false  // 防止连续点击
  @State statusMessage: string = ''
  @StorageProp(appOption.currentEmulatorStatus) currentEmulatorStatus: string = ''
  @State processingMessage: string = ''
  private processingDialog: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: this.processingMessage
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center
  })
  private isComponentActive: boolean = false  // [2.2] 生命周期标志

  aboutToAppear() {
    AppStorage.setOrCreate(appOption.isPowerManagementOpen, true)
    this.isComponentActive = true
    // QGA 状态现在统一由 VmStatusBar 在全局分发并感知，本组件不再独立探测
  }

  aboutToDisappear() {
    AppStorage.setOrCreate(appOption.isPowerManagementOpen, false)
    this.isComponentActive = false  // 标记组件已销毁
    this.isOperating = false        // 重置操作状态
  }

  // --- [已移除] 独立连接逻辑 connectToQGA, performAction, connectToQmp, verifyVmStatus ---

  /**
   * 执行全局重置 (最高优先级保命功能)
   * 清理整个 Agent 环境，重置 QMP 监听，并强制 VmStatusBar 刷新状态
   */
  async performGlobalReset() {
    if (this.isOperating) return
    this.isOperating = true

    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resetting_connections').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    try {
      hilog.warn(DOMAIN, 'PowerManagement', '>>> 开始执行全局连接重置 (Global Reset) <<<')

      // 1. 强制重置 QGA 管理器 (这将强制断开所有持有者，包括 VmStatusBar)
      await QemuAgentManager.reset()

      // 2. 强制 VmStatusBar 状态为 False (在重新探测前)
      AppStorage.setOrCreate(appOption.isQgaConnected, false)

      // 3. 重置 QMP 监听器
      const qmpListener = getQmpEventListener()
      if (qmpListener) {
        await qmpListener.reset()
      }

      // 4. 等待资源释放 (物理 Socket 清理通常由 Manager reset 处理，但这里给系统喘息时间)
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, 1500))

      // 5. 触发 VmStatusBar 进行一次立即探测 (心跳重启)
      // 注意：我们不在这里直接连接，而是通过全局状态通知机制
      // 如果 VmStatusBar 发现断连，它的逻辑会自动尝试重连或等待下一次心跳，
      // 但这里我们希望有一个立即的手动反馈？VmStatusBar 没有公开暴露 forceRefresh，
      // 但它的 onPowerManagementChange 逻辑在关闭 PM 时会刷新。
      // 在 PM 开启状态下，我们依赖它的后台心跳。
      // **关键优化**：我们可以临时模拟一次 Agent 获取来验证环境，然后立即释放，以确认“通路”已打通。
      hilog.info(DOMAIN, 'PowerManagement', '验证重置后的 QGA 通路...')
      try {
        // 使用特殊 ID 获取一次高优先级连接，确保存活
        const testAgent = await QemuAgentManager.acquire('PM_GlobalReset_Probe', AgentPriority.HIGH, 3000)
        if (testAgent) {
          const ping = await testAgent.ping()
          hilog.info(DOMAIN, 'PowerManagement', '重置后通路验证结果: %{public}s', ping)
          AppStorage.setOrCreate(appOption.isQgaConnected, ping)
          await QemuAgentManager.release('PM_GlobalReset_Probe')
        } else {
          hilog.warn(DOMAIN, 'PowerManagement', '重置后依然无法获取 QGA Agent')
        }
      } catch (probeErr) {
        hilog.warn(DOMAIN, 'PowerManagement', '重置后探测异常: %{public}s', JSON.stringify(probeErr))
      }

      hilog.info(DOMAIN, 'PowerManagement', '全局连接重置完成，等待 VmStatusBar 重新探测。')
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_connections_success').id)

    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', '全局重置失败: %{public}s', JSON.stringify(e))
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reset_failed').id, JSON.stringify(e))
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }

  async performResume() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resuming').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    try {
      // 委托给 VmController 执行
      await VmController.getInstance().resumeVM();

      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_running').id)
      // QGA 连接状态将通过 VmStatusBar 自动同步更新
    } catch (e) {
      const errorMsg = (e as Error).message || JSON.stringify(e);
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_resume_failed_cmd').id) + `: ${errorMsg}`
      hilog.error(DOMAIN, 'PowerManagement', '恢复失败: %{public}s', errorMsg)
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }
  async performPause() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pausing').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    try {
      // 委托给 VmController 执行
      await VmController.getInstance().pauseVM();

      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_paused').id)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_pause_failed').id)
      hilog.error(DOMAIN, 'PowerManagement', '暂停失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }

  async performShutdown() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutting_down').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    try {
      // 委托给 VmController 执行，包含完整的 QGA -> QMP -> Force Kill 流程
      const success = await VmController.getInstance().shutdownVM()

      if (success) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)
        // 显式保存 Last ID (虽然 VmController 内部可能已处理，但为了 UI 逻辑保险再做一次)
        const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string
        if (currentRunning) {
          AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning)
        }
        // VmController 的 shutdownVM 成功后会更新 SHUTDOWN 状态
      } else {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown_failed').id, 'Timeout or Error')
      }
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', '关机流程异常: %{public}s', JSON.stringify(e))
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_shutdown_failed').id, JSON.stringify(e))
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }

  async performReboot() {
    if (this.isOperating) return
    this.isOperating = true
    this.processingMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_rebooting').id)
    this.processingDialog.open()

    try {
      const success = await VmController.getInstance().rebootVM();
      if (!success) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_failed').id)
        this.getUIContext().showAlertDialog({
          title: $r('app.string.pm_status_reboot_failed'),
          message: getContext(this).resourceManager.getStringSync($r('app.string.pm_status_reboot_failed_hint').id),
          autoCancel: true,
          alignment: DialogAlignment.Center,
          buttons: [{
            value: $r('app.string.setting_generic_confirm'),
            action: () => { }
          }]
        })
      }
    } catch (e) {
      hilog.error(DOMAIN, 'PowerManagement', 'performReboot exception: %{public}s', JSON.stringify(e));
    } finally {
      this.isOperating = false
      this.processingDialog.close()
    }
  }
  /**
   * 状态验证定时器
   * 在指定时间后验证虚拟机状态，确保 UI 状态与实际状态一致
   * @param timeout 超时时间（毫秒）
   */

  /**
   * 验证虚拟机状态 (Core Status Check)
   * 优先级: PID (L1) > QMP (L2) > QGA (Ignored)
   * @returns true if Running/Paused, false if Shutdown/Unknown
   */

  async performHardReset() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_resetting').id)
    this.processingMessage = this.statusMessage // Ensure dialog message is updated
    this.processingDialog.open()

    // 设置重置标志
    AppStorage.setOrCreate(appOption.isVmSwitching, true)

    // 1. 设置 VM 切换标志
    AppStorage.setOrCreate(appOption.isVmSwitching, true)

    // 2. Agent 清理由 VmController.hardResetVM 内部负责，组件层无需手动断开

    try {
      // 委托给 VmController 执行 Hard Reset (传入当前 UIContext 以防底层丢失)
      await VmController.getInstance().hardResetVM(this.getUIContext());

      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_running').id)
      AppStorage.setOrCreate(appOption.currentEmulatorStatus, 'RUNNING')

      // QGA 连接状态将通过 VmStatusBar 自动同步更新
    } catch (e) {
      const errorMsg = (e instanceof Error) ? e.message : JSON.stringify(e);
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_reset_failed').id, errorMsg)
      hilog.error(DOMAIN, 'PowerManagement', '重置失败: %{public}s', errorMsg)
    } finally {
      this.isOperating = false
      this.processingDialog.close()
      // 延迟重置 VM 切换标志
      setTimeout(() => {
        AppStorage.setOrCreate(appOption.isVmSwitching, false)
      }, 1500)
    }
  }

  async performForceShutdown() {
    if (this.isOperating) return
    this.isOperating = true
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_force_shutdown').id)
    this.processingMessage = this.statusMessage
    this.processingDialog.open()

    // Agent 清理委托给底层，无需手动 release

    try {
      // 委托给 VmController 执行 Force Power Off
      await VmController.getInstance().forcePowerOff();

      // VmController 会处理状态更新
      this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_shutdown').id)

    } catch (e) {
      // Should ensure UI is unblocked
    } finally {
      // 显式保存 Last ID (确保重启按钮可用)
      const currentRunning = AppStorage.get(appOption.currentRunningEmulator) as string;
      if (currentRunning) {
        AppStorage.setOrCreate('lastRunningEmulatorId', currentRunning);
      }

      this.isOperating = false
      this.processingDialog.close()
    }
  }

  async performPowerOn() {
    if (this.isOperating) return  // 添加操作锁
    this.isOperating = true
    this.statusMessage = this.getUIContext().getHostContext()!!.resourceManager.getStringSync($r('app.string.pm_status_starting').id)

    try {
      const emulators = AppStorage.get(appOption.emulators) as Emulator[]
      let currentEmulatorId = AppStorage.get(appOption.currentRunningEmulator) as string

      // 如果 currentRunningEmulator 为空，使用 defaultStartEmulator 作为备选
      if (!currentEmulatorId) {
        currentEmulatorId = AppStorage.get(appOption.defaultStartEmulator) as string
        hilog.info(DOMAIN, 'PowerManagement', '使用默认模拟器: %{public}s', currentEmulatorId)
      }

      const emulator = emulators.find((e: Emulator) => e.id === currentEmulatorId)

      if (!emulator) {
        this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed_no_config').id)
        this.isOperating = false
        return
      }

      // 使用 VmController 启动虚拟机 (确保状态同步和事件监听)
      // VmController 内部会自动处理 VNC 端口、数据盘路径等计算
      await VmController.getInstance().startVM(emulator, this.getUIContext());

      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_running').id)

      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_running').id)
    } catch (e) {
      this.statusMessage = getContext(this).resourceManager.getStringSync($r('app.string.pm_status_poweron_failed').id, JSON.stringify(e))
      hilog.error(DOMAIN, 'PowerManagement', '开机失败: %{public}s', JSON.stringify(e))
    } finally {
      this.isOperating = false
    }
  }

  build() {
    Scroll() {
      Column() {
        // 状态显示
        // 状态信息面板
        Column() {
          // QMP 状态
          Row() {
            Text($r('app.string.pm_label_qmp_status'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text(this.currentEmulatorStatus !== '' && this.currentEmulatorStatus !== 'SHUTDOWN' ? $r('app.string.pm_status_qmp_connected') : $r('app.string.pm_status_qmp_disconnected'))
              .fontSize(12)
              .fontColor(this.currentEmulatorStatus !== '' && this.currentEmulatorStatus !== 'SHUTDOWN' ? '#00AA00' : '#AA0000')
          }
          .width('100%')
            .padding({ top: 4, bottom: 4 })

          Divider()
            .color('#33FFFFFF') // 增加透明度，使其更明显
            .strokeWidth(1)     // 增加粗细
            .margin({ top: 12, bottom: 12 }) // 稍微增加间距

          // Guest Agent 状态
          Row() {
            Text($r('app.string.pm_label_ga_status'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
            Blank()
            Text(this.statusMessage)
              .fontSize(12)  // 统一字体大小
              .fontColor(this.isConnected ? '#00AA00' : '#AA0000')
          }
          .width('100%')
            .padding({ top: 4, bottom: 4 })
        }
        .width('100%')
          .padding(12)
          .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
          .borderRadius(8)
          .margin({ bottom: 12 })

        // 强制重连按钮（只要 VM 未关机就显示，总是可用以便打断）
        if (this.currentEmulatorStatus !== 'SHUTDOWN' && this.currentEmulatorStatus !== '') {
          Button($r('app.string.pm_btn_force_reconnect'))
            .width('100%')
            .margin({ bottom: 16 })
            .enabled(!this.isOperating) // 操作中禁用
            .onClick(() => {
              this.performGlobalReset()
            })
        }



        Column({ space: 8 }) {
          // 强制断电按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.bolt_fill'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_force_shutdown'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#8B0000')
            .borderRadius(8)
            .enabled(!this.isOperating && this.currentEmulatorStatus !== 'SHUTDOWN' && this.currentEmulatorStatus !== '')
            .onClick(() => this.performForceShutdown())

          // 强制重置按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_reset'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#C0392B')
            .borderRadius(8)
            .enabled(!this.isOperating && this.currentEmulatorStatus !== 'SHUTDOWN' && this.currentEmulatorStatus !== '')
            .onClick(() => this.performHardReset())

          // 关机按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.power'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_shutdown'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#E74C3C')
            .borderRadius(8)
            // [修复] 仅在 RUNNING 状态允许 ACPI 关机 (PAUSED 下禁用)
            .enabled(!this.isOperating && this.currentEmulatorStatus === 'RUNNING')
            .onClick(() => this.performShutdown())

          // 重启按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.arrow_clockwise'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_reboot'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#F39C12')
            .borderRadius(8)
            // [修复] 仅在 RUNNING 状态允许重启
            .enabled(!this.isOperating && this.currentEmulatorStatus === 'RUNNING')
            .onClick(() => this.performReboot())

          // 暂停按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.pause'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_pause'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#3498DB')
            .borderRadius(8)
            .enabled(!this.isOperating && this.currentEmulatorStatus === 'RUNNING')
            .onClick(() => this.performPause())

          // 恢复按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.play'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_resume'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#2ECC71')
            .borderRadius(8)
            .enabled(!this.isOperating && this.currentEmulatorStatus === 'PAUSED')
            .onClick(() => this.performResume())

          // 开机按钮
          Button({ type: ButtonType.Normal, stateEffect: true }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.power'))
                .fontSize(16)
                .fontColor(['#FFFFFF'])
              Text($r('app.string.pm_btn_poweron'))
                .fontSize(14)
                .fontColor('#FFFFFF')
            }
          }
          .width('100%')
            .height(36)
            .backgroundColor('#27AE60')
            .borderRadius(8)
            .enabled((this.currentEmulatorStatus === 'SHUTDOWN' || this.currentEmulatorStatus === '') && !this.isOperating)
            .onClick(() => this.performPowerOn())
        }
        .width('100%')

        // 说明文字
        Text($r('app.string.pm_note_qga'))
          .fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .margin({ top: 24 })
          .width('100%')
      }
      .width('100%')
        .padding(16)
    }
    .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Auto)
  }
}
