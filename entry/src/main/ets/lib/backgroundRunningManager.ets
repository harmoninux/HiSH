import { BusinessError } from '@kit.BasicServicesKit';
import { common, wantAgent } from "@kit.AbilityKit";
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { hilog } from "@kit.PerformanceAnalysisKit";

const TAG = '[backgroundRunningManager]'

export class backgroundRunningManager {
  public static startContinuousTask(context: common.UIAbilityContext): void {
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
    wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj) => {
      try {
        backgroundTaskManager.startBackgroundRunning(context,
          backgroundTaskManager.BackgroundMode.LOCATION, wantAgentObj).then(() => {
          hilog.info(1, TAG, 'startBackgroundRunning succeeded');
        }).catch((err: BusinessError) => {
          hilog.info(1, TAG, `startBackgroundRunning failed Cause:  ${JSON.stringify(err)}`);
        });
      } catch (error) {
        hilog.error(1, TAG, `Operation startBackgroundRunning failed. code is ${error.code}, msg: ${error.message}`);
      }
    });
  }

  // cancel continuous task
  public static stopContinuousTask(context: common.UIAbilityContext): void {
    try {
      backgroundTaskManager.stopBackgroundRunning(context).then(() => {
        hilog.info(1, TAG, 'stopBackgroundRunning succeeded');
      }).catch((err: BusinessError) => {
        hilog.info(1, TAG, `stopBackgroundRunning failed Cause:  ${JSON.stringify(err)}`);
      });
    } catch (error) {
      hilog.error(1, TAG, `Operation stopBackgroundRunning failed. code is ${error.code}, msg: ${error.message}`);
    }
  }
}