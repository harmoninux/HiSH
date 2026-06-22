import { abilityAccessCtrl, common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { hilog } from "@kit.PerformanceAnalysisKit";

const TAG = '[backgroundRunningManager]'

/**
 * VM 运行期间需要持续传输串口/VNC 数据，使用 DATA_TRANSFER 模式维持后台运行
 * 不需 LOCATION 权限，避免 AppGallery 审核风险
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
  const wantAgentObj = await wantAgent.getWantAgent(wantAgentInfo)
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
      return true
    } catch (e) {
      hilog.warn(1, TAG, `startBackground failed: ${JSON.stringify(e)}`)
      return false
    }
  }

  public static async stopBackground(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await stopContinuousTask(context)
      return true
    } catch (e) {
      hilog.warn(1, TAG, `stopBackground failed: ${JSON.stringify(e)}`)
      return false
    }
  }
}