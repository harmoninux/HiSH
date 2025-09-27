import { CustomContentDialog } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { LinkItem } from "./LinkItem"
import { common, Want } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { BusinessError } from '@ohos.base';
import vmOption from '../model/vmOption';

@Component
export default struct SettingsContent {
  @Watch('saveVmCpuCount') @StorageProp(vmOption.cpuCountName) vmCpuCount: number = 1
  @Watch('saveVmMemSize') @StorageProp(vmOption.memSizeName) vmMemSize: number = 512
  webController: webview.WebviewController = new webview.WebviewController()
  openSourceController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.open_source_license'),
      contentBuilder: () => {
        this.buildOpenSourceView();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.openSourceController.close();
        }
      }]
    })
  })
  aboutController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.about_me'),
      contentBuilder: () => {
        this.buildAboutMe();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.aboutController.close();
        }
      }]
    })
  })
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences

  async aboutToAppear(): Promise<void> {
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), vmOption.preferenceName)
  }

  saveVmCpuCount() {
    this.preferences!.put(vmOption.cpuCountName, this.vmCpuCount)
    this.preferences!.flush()
  }

  saveVmMemSize() {
    this.preferences!.put(vmOption.memSizeName, this.vmMemSize)
    this.preferences!.flush()
  }

  build() {
    Scroll() {
      Column() {

        Row() {
          Column() {
            Text('CPU').fontSize($r('sys.float.Body_L')).fontColor($r('sys.color.font_primary'))
            Text('设置CPU核数').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
          }
          .flexGrow(1)
          .alignItems(HorizontalAlign.Start)

          Select([{ value: '1' }, { value: '2' }, { value: '4' }])
            .width(100)
            .value(this.vmCpuCount.toString())
            .onSelect((_i, value) => AppStorage.setOrCreate(vmOption.cpuCountName, parseInt(value)))
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .height(56)
        .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

        Row() {
          Column() {
            Text('内存').fontSize($r('sys.float.Body_L')).fontColor($r('sys.color.font_primary'))
            Text('设置内存大小（MB）').fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
          }
          .flexGrow(1)
          .alignItems(HorizontalAlign.Start)

          Select([{ value: '512' }, { value: '1024' }, { value: '2048' }, { value: '4096' }])
            .width(100)
            .value(this.vmMemSize.toString())
            .onSelect((_i, value) => AppStorage.setOrCreate(vmOption.memSizeName, parseInt(value)))
        }
        .alignItems(VerticalAlign.Center)
        .width('100%')
        .height(56)
        .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

        LinkItem({
          icon: $r('sys.symbol.house'),
          title: $r('app.string.code_repository'),
          click: () => {
            this.toWebBrowser('https://github.com/harmoninux/hish')
          }
        })

        LinkItem({
          icon: $r('sys.symbol.doc_text_badge_checkmark'),
          title: $r('app.string.open_source_license'),
          click: () => {
            this.openSourceController.open();
          }
        })

        LinkItem({
          icon: $r('sys.symbol.info_circle'),
          title: $r('app.string.about_me'),
          click: () => {
            this.aboutController.open();
          }
        })
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
  }

  @Builder
  buildOpenSourceView() {
    Web({ src: $rawfile('pages/osl.html'), controller: this.webController })
      .onLoadIntercept((e: OnLoadInterceptEvent) => {
        let url = e.data.getRequestUrl();
        if (url.startsWith('http')) {
          this.toWebBrowser(e.data.getRequestUrl());
          return true;
        } else {
          return false;
        }
      })
  }

  @Builder
  buildAboutMe() {
    Column() {

      Image($r('app.media.startIcon'))
        .width(50)

      Text($r('app.string.app_name'))
        .margin({ top: 10 })
    }
    .width('100%')
  }

  async toWebBrowser(url: string): Promise<void> {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    let want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url,
      parameters: {
        bundleName: context.abilityInfo.bundleName
      }
    };
    await context.startAbility(want);
  }
}