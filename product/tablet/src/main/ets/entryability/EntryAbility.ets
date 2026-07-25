import { EntryAbility as BaseEntryAbility } from 'hish_main';
import { AbilityConstant, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export default class EntryAbility extends BaseEntryAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onCreate - tablet thin');
    super.onCreate(want, launchParam);
  }

  onDestroy(): void {
    super.onDestroy();
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, 'testTag', 'EntryAbility onWindowStageCreate - tablet thin');
    await super.onWindowStageCreate(windowStage);
  }
}
