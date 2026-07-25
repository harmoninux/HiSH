import { abilityAccessCtrl, common, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from "@kit.BackgroundTasksKit";
import { hilog } from "@kit.PerformanceAnalysisKit";
import { geoLocationManager } from '@kit.LocationKit';

const TAG = '[backgroundRunningManager]'

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
    context, backgroundTaskManager.BackgroundMode.LOCATION, wantAgentObj)
}

async function stopContinuousTask(context: common.UIAbilityContext) {
  await backgroundTaskManager.stopBackgroundRunning(context)
}

export class backgroundRunningManager {
  public static async startBackground(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const granted = await backgroundRunningManager.grantLocationPermission(context);
      if (granted) {
        geoLocationManager.on("locationChange", {
          interval: 15,
          locationScenario: geoLocationManager.PowerConsumptionScenario.NO_POWER_CONSUMPTION
        }, () => {
        })
        await startContinuousTask(context)
        return true
      }
      return false
    } catch (e) {
      hilog.info(1, TAG, `startBackground failed Cause:  ${JSON.stringify(e)}`);
      return false
    }
  }

  public static async grantLocationPermission(context: common.UIAbilityContext) {
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, ['ohos.permission.APPROXIMATELY_LOCATION']);
      return result.authResults[0] === 0;
    } catch (e) {
      hilog.info(1, TAG, `grantLocationPermission failed Cause:  ${JSON.stringify(e)}`);
      return false
    }
  }

  public static async stopBackground(context: common.UIAbilityContext): Promise<boolean> {
    try {
      geoLocationManager.off('locationChange')
      stopContinuousTask(context)
      return true
    } catch (e) {
      hilog.info(1, TAG, `stopBackground failed Cause:  ${JSON.stringify(e)}`);
      return false
    }
  }
}