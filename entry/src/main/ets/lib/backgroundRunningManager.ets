import { abilityAccessCtrl, common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import runningLock from '@ohos.runningLock';
import { hilog } from "@kit.PerformanceAnalysisKit";

const TAG = '[backgroundRunningManager]'
let lock: runningLock.RunningLock | null = null

/**
 * 申请 running lock，防止熄屏后系统降频导致 QEMU VM 拿唔够 CPU 时间
 */
async function requestWakeLock() {
  if (lock !== null) {
    if (lock.isHolding()) {
      hilog.info(1, TAG, 'running lock already held, skip')
      return
    }
    lock.hold(-1)
    hilog.info(1, TAG, 'running lock re-held (indefinite)')
    return
  }
  try {
    lock = await runningLock.create('hish_vm', runningLock.RunningLockType.BACKGROUND)
    lock.hold(-1)
    hilog.info(1, TAG, 'running lock acquired (BACKGROUND, indefinite)')
  } catch (e) {
    hilog.error(1, TAG, `requestWakeLock failed: ${JSON.stringify(e)}`)
    lock = null
  }
}

/**
 * 释放 running lock
 */
function releaseWakeLock() {
  if (lock === null) {
    return
  }
  try {
    if (lock.isHolding()) {
      lock.unhold()
    }
    lock = null
    hilog.info(1, TAG, 'running lock released')
  } catch (e) {
    hilog.error(1, TAG, `releaseWakeLock failed: ${JSON.stringify(e)}`)
    lock = null
  }
}

/**
 * VM 运行期间需要持续传输串口/VNC 数据，使用 DATA_TRANSFER 模式维持后台运行
 * 同时持有 RUNNING_LOCK 防止熄屏后 CPU 降频
 */
async function startContinuousTask(context: common.UIAbilityContext) {
  let wantAgentInfo: wantAgent.WantAgentInfo = {
    wants: [
      {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      }
    ],
    operationType: wantAgent.OperationType.START_ABILITY,
    requestCode: 0,
    wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
  };
  const wantAgentObj = await wantAgent.getWantAgent(wantAgentInfo);
  await backgroundTaskManager.startBackgroundRunning(
    context, backgroundTaskManager.BackgroundMode.DATA_TRANSFER, wantAgentObj)
}

async function stopContinuousTask(context: common.UIAbilityContext) {
  await backgroundTaskManager.stopBackgroundRunning(context)
}

export class backgroundRunningManager {
  public static async startBackground(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await startContinuousTask(context)
      await requestWakeLock()
      return true
    } catch (e) {
      hilog.warn(1, TAG, `startBackground failed: ${JSON.stringify(e)}`)
      return false
    }
  }

  public static async stopBackground(context: common.UIAbilityContext): Promise<boolean> {
    releaseWakeLock()
    try {
      await stopContinuousTask(context)
      return true
    } catch (e) {
      hilog.warn(1, TAG, `stopBackground failed: ${JSON.stringify(e)}`)
      return false
    }
  }

  /**
   * 单独释放 running lock（VM 停止但保持后台运行时调用）
   */
  public static releaseWakeLockOnly(): void {
    releaseWakeLock()
  }

  /**
   * VM 启动时申请 running lock（唔依赖 runningInBackground 设置）
   */
  public static async requestWakeLockForVm(): Promise<void> {
    await requestWakeLock()
  }
}
