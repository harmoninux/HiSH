import { CustomContentDialog, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { LinkItem } from "./LinkItem"
import { common, Want } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { PortMapping } from '../model/appOption'
import { JSON, util } from '@kit.ArkTS';
import appOption from '../model/appOption';

@Component
export default struct SettingsContent {
  @Watch('saveVmCpuCount') @StorageProp(appOption.cpuCountName) vmCpuCount: number = 1
  @Watch('saveVmMemSize') @StorageProp(appOption.memSizeName) vmMemSize: number = 512
  @Watch('saveKeepScreenOn') @StorageProp(appOption.keepScreenOn) keepScreenOn: boolean = false
  @StorageProp('versionName') versionName: string = ''
  @StorageProp('versionCode') versionCode: number = 0
  @State vmPortMappingEnabled: boolean = false
  @State portMappings: PortMapping[] = [{ guest: 22, host: 2222 }]
  webController: webview.WebviewController = new webview.WebviewController()
  portMappingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_port_mapping'),
      contentBuilder: () => {
        this.buildPortMapping();
      }
    })
  })
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
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), appOption.preferenceName)
  }

  saveVmCpuCount() {
    this.preferences!.put(appOption.cpuCountName, this.vmCpuCount)
    this.preferences!.flush()
  }

  saveVmMemSize() {
    this.preferences!.put(appOption.memSizeName, this.vmMemSize)
    this.preferences!.flush()
  }

  saveKeepScreenOn() {
    this.preferences!.put(appOption.keepScreenOn, this.keepScreenOn)
    this.preferences!.flush()

    const mainWindow = AppStorage.get('mainWindow') as window.Window
    if (mainWindow) {
      mainWindow.setWindowKeepScreenOn(this.keepScreenOn)
    }
  }

  build() {
    Scroll() {
      Column() {

        Text($r("app.string.setting_block_system"))
          .margin({ bottom: 10, left: 20 })
          .width('100%')
        Column() {
          Row() {
            Column() {
              Text($r('app.string.setting_cpu'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_cpu_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Select([{ value: '1' }, { value: '2' }, { value: '4' }])
              .width(100)
              .value(this.vmCpuCount.toString())
              .onSelect((_i, value) => AppStorage.setOrCreate(appOption.cpuCountName, parseInt(value)))
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

          Row() {
            Column() {
              Text($r('app.string.setting_mem_size'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_mem_size_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Select([{ value: '512' }, { value: '1024' }, { value: '2048' }, { value: '4096' }])
              .width(100)
              .value(this.vmMemSize.toString())
              .onSelect((_i, value) => AppStorage.setOrCreate(appOption.memSizeName, parseInt(value)))
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })

          Row() {
            Column() {
              Text($r('app.string.setting_port_mapping'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_port_mapping_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.chevron_right'))
              .fontColor([$r('sys.color.icon_secondary')])
              .fontSize('24vp')
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          .onClick(async () => {
            await this.loadAndOpenPortMapping()
          })

          Row() {
            Column() {
              Text($r('app.string.setting_reset_linux'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_port_mapping_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontColor([$r('sys.color.icon_secondary')])
              .fontSize('24vp')
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          .onClick(() => this.openResetLinuxDialog())
        }
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))

        Text($r("app.string.setting_block_display"))
          .margin({ top: 20, bottom: 10, left: 20 })
          .width('100%')
        Column() {
          Row() {
            Column() {
              Text($r('app.string.setting_keep_screen_on'))
                .fontSize($r('sys.float.Body_L'))
                .fontColor($r('sys.color.font_primary'))
              Text($r('app.string.setting_keep_screen_on_desc'))
                .fontSize($r('sys.float.Body_M'))
                .fontColor($r('sys.color.font_tertiary'))
            }
            .flexGrow(1)
            .alignItems(HorizontalAlign.Start)

            Checkbox()
              .select(this.keepScreenOn)
              .onChange((value: boolean) => {
                AppStorage.setOrCreate(appOption.keepScreenOn, value)
              })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .height(56)
          .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
        }
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))

        Text($r('app.string.setting_block_about'))
          .margin({ top: 20, bottom: 10, left: 20 })
          .width('100%')
        Column() {
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
        .borderRadius(20)
        .backgroundColor($r('app.color.setting_block_background'))
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
  }

  async loadAndOpenPortMapping() {
    const json = await this.preferences!.get(appOption.portMapping, '[]') as string;
    this.vmPortMappingEnabled = await this.preferences!.get(appOption.portMappingEnabled, false) as boolean
    this.portMappings = JSON.parse(json) as PortMapping[]
    this.portMappingController.open()
  }

  async savePortMapping() {
    const json = JSON.stringify(this.portMappings)
    await this.preferences!.put(appOption.portMappingEnabled, this.vmPortMappingEnabled)
    await this.preferences!.put(appOption.portMapping, json)
    await this.preferences!.flush()
    this.portMappingController.close()
  }

  @Builder
  buildPortMappingItem(
    item: PortMapping,
    updateHost: (port: number | undefined) => void,
    updateGuest: (port: number | undefined) => void,
    remove: () => void
  ) {
    Row() {
      Row() {
        TextInput({ text: item.guest?.toString(), placeholder: 'Guest' })
          .type(InputType.Number)
          .width(80)
          .onChange((value) => {
            const guest = value ? parseInt(value) : undefined;
            updateGuest(guest)
          })
        Text(':').margin({ left: 5, right: 5 })
        TextInput({ text: item.host?.toString(), placeholder: 'Host' })
          .type(InputType.Number)
          .width(80)
          .onChange((value) => {
            const host = value ? parseInt(value) : undefined;
            updateHost(host)
          })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      SymbolGlyph($r('sys.symbol.minus_circle'))
        .fontColor([$r('sys.color.alert')])
        .fontSize('24vp')
        .onClick(() => remove())
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: $r('sys.float.padding_level6'),
      right: $r('sys.float.padding_level6'),
      top: $r('sys.float.padding_level2'),
      bottom: $r('sys.float.padding_level2')
    })
    .width('100%')
  }

  @Builder
  buildPortMapping() {
    Column() {

      Row() {
        Text($r('app.string.setting_enable_port_mapping'))
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
        Checkbox()
          .select(this.vmPortMappingEnabled)
          .onChange((value: boolean) => {
            this.vmPortMappingEnabled = value
          })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({
        left: $r('sys.float.padding_level6'),
        right: $r('sys.float.padding_level4'),
        top: $r('sys.float.padding_level2'),
        bottom: $r('sys.float.padding_level2')
      })
      .width('100%')

      ForEach(this.portMappings, (item: PortMapping, index) => {
        this.buildPortMappingItem(item, (host) => {
          const it = this.portMappings[index]
          this.replacePortMapping(index, { host, guest: it.guest })
        }, (guest) => {
          const it = this.portMappings[index]
          this.replacePortMapping(index, { guest, host: it.host });
        }, () => {
          const copy = [...this.portMappings]
          copy.splice(index, 1)
          this.portMappings = copy
        })
      }, (_item: PortMapping, index) => 'port-mapping-' + index)

      Column() {

        if (this.portMappingError()) {
          Text(this.portMappingError())
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.alert'))
        }

        Button($r('app.string.setting_add'), { buttonStyle: ButtonStyleMode.NORMAL })
          .enabled(this.addPortMappingEnabled() && !this.portMappingError())
          .width('100%')
          .margin({ top: 10 })
          .onClick(() => {
            this.portMappings.push({})
          })

        Button($r('app.string.SettingSave_label'))
          .enabled(!this.portMappingError())
          .width('100%')
          .margin({ top: 10 })
          .onClick(() => {
            this.savePortMapping()
          })
      }
      .margin({ top: 30 })
    }
  }

  private replacePortMapping(index: number, up: PortMapping) {
    const copy = this.portMappings.map((el, i) => i === index ? up : el);
    this.portMappings = copy;
  }

  addPortMappingEnabled(): boolean {
    const invalid = this.portMappings.filter(it => !(it.guest && it.host));
    return invalid.length === 0;
  }

  portMappingError(): string | Resource | undefined {
    let i = this.portMappings
      .findIndex(it => {
        return !(it.guest && it.host)
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_incomplete_port_mapping'))
      return util.format(temp, (i + 1))
    }

    i = this.portMappings
      .findIndex(it => {
        return (it.host || 0) <= 1000
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_port_should_larger'))
      return util.format(temp, (i + 1))
    }

    const guestPorts = new Set(this.portMappings.map(it => it.guest))
    const hostPorts = new Set(this.portMappings.map(it => it.host))
    if (guestPorts.size < this.portMappings.length || hostPorts.size < this.portMappings.length) {
      return $r('app.string.setting_duplicated_port')
    }

    return undefined
  }

  private openResetLinuxDialog() {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.setting_reset_linux_title'),
      message: $r('app.string.setting_reset_linux_content'),
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
          value: $r('app.string.setting_reset_linux_reset'),
          action: async () => {
            await this.preferences?.put(appOption.resetLinuxFlag, true)
            await this.preferences?.flush()
            this.restartApp();
          }
        }
      ],
    });
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

      Text(`${this.versionName}(${this.versionCode})`)
        .fontSize(14)
        .fontColor('#ccc')
        .margin({ top: 5 })
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

  async restartApp() {
    let applicationContext = this.context.getApplicationContext();
    let want: Want = {
      bundleName: 'app.hackeris.hish',
      abilityName: 'EntryAbility'
    };
    applicationContext.restartApp(want);
  }
}