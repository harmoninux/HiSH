import { common } from "@kit.AbilityKit"
import { CustomContentDialog, PromptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';
import { SharedFolderContent } from '../components/SharedFolderContent';
import { PortMappingContent } from "../components/PortMappingContent";
import appOption from "../model/appOption";
import { util } from "@kit.ArkTS";
import EmulatorManagement from "../components/EmulatorManagement";

@Component
struct PcIndex {
  @StorageProp(appOption.sharedHost) sharedHost: string = ''
  @StorageProp(appOption.sharedGuest) sharedGuest: string = ''
  private appContext: common.ApplicationContext =
    (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext()
  settingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.Setting_title'),
      contentBuilder: () => {
        this.buildSettings();
      },
      buttons: [{
        value: $r('app.string.SettingComplete_label'),
        buttonStyle: ButtonStyleMode.TEXTUAL,
        action: () => {
          this.settingController.close()
        }
      }]
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  })
  portMappingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_port_mapping'),
      contentBuilder: () => {
        this.buildPortMapping();
      }
    })
  })
  sharedFolderController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.setting_shared_folder'),
      contentBuilder: () => {
        this.buildSharedFolder();
      }
    })
  })

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.startIcon'))
            .width(20)
          Text($r('app.string.app_name'))
            .margin({ left: 10 })
        }

        Blank()

        Row() {
          Image($r('app.media.folder'))
            .width(28)
            .aspectRatio(1)
            .padding(4)
            .margin({ right: 10 })
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.sharedFolderController.open()
            })
          Image($r('app.media.reverse_order'))
            .width(28)
            .aspectRatio(1)
            .padding(4)
            .margin({ right: 10 })
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.portMappingController.open()
            })
          Image($r('app.media.gearshape'))
            .width(28)
            .aspectRatio(1)
            .padding(4)
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.settingController.open()
            })
        }
      }
      .width('100%')
      .height(48)
      .padding({
        left: 15,
        right: 150,
      })

      WebTerminal({ showVirtKey: false })
        .layoutWeight(1)
    }
    .width("100%")
    .height('100%')
  }

  @Builder
  buildSettings() {
    SettingsContent()
  }

  @Builder
  buildPortMapping() {
    PortMappingContent()
  }

  @Builder
  buildSharedFolder() {
    SharedFolderContent({
      host: this.sharedHost,
      guest: this.sharedGuest
    })
  }
}

@Component
struct PhoneOrTablet {
  @StorageProp(appOption.sharedHost) sharedHost: string = ''
  @StorageProp(appOption.sharedGuest) sharedGuest: string = ''
  @State currentIndex: number = 0;
  private tabsController: TabsController = new TabsController();
  private appContext: common.ApplicationContext =
    (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext()

  @Builder
  tabBuilder(title: Resource | string, index: number, selectedImg: Resource) {
    Column() {
      SymbolGlyph(selectedImg)
        .fontSize('24vp')
        .width(24)
        .height(24)
        .fontColor([this.currentIndex === index ? '#3388ff' : '#777777'])
      Text(title)
        .margin({ top: 4 })
        .fontSize(10)
        .fontColor(this.currentIndex === index ? '#3388ff' : '#777777')
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .height(52)
    .width('100%')
    .onClick(() => {
      this.currentIndex = index;
      this.tabsController.changeIndex(this.currentIndex);
    })
  }

  build() {
    Tabs({
      barPosition: BarPosition.End,
      controller: this.tabsController
    }) {
      TabContent() {
        WebTerminal({ showVirtKey: true })
      }
      .tabBar(this.tabBuilder($r('app.string.shell'), 0, $r('sys.symbol.house')))

      TabContent() {
        EmulatorManagement()
      }
      .tabBar(this.tabBuilder('模拟器管理', 1, $r('sys.symbol.more')))

      TabContent() {
        PortMappingContent()
      }
      .tabBar(this.tabBuilder('使用指南', 2, $r('sys.symbol.book_pages')))

      TabContent() {
        Column() {
          Text($r('app.string.Setting_title'))
            .fontSize(23)
            .height(56)
            .width('100%')
            .padding({ left: 20, right: 20 })
          SettingsContent()
        }
        .width('100%')
        .height('100%')
      }
      .tabBar(this.tabBuilder($r('app.string.Setting_title'), 3, $r('sys.symbol.gearshape')))
    }
    .width('100%')
    .barHeight(52)
    .barMode(BarMode.Fixed)
    .onAnimationStart((index: number, targetIndex: number) => {
      this.currentIndex = targetIndex;
    })
  }
}

@Entry
@Component
struct Index {
  isPc: boolean = deviceInfo.deviceType === '2in1'
  @StorageProp(appOption.use9pRootFs) use9pRootFs: boolean = false
  private uiContext: UIContext = this.getUIContext();
  private promptAction: PromptAction = this.uiContext.getPromptAction();

  aboutToAppear(): void {
    // webview.WebviewController.setWebDebuggingAccess(true)
    const promptFormat = this.uiContext
      .getHostContext()?.resourceManager.getStringByNameSync('port_used_prompt')
    const portUsedByOthers = AppStorage.get(appOption.portUsedByOthers) as number[]
    if (portUsedByOthers.length > 0) {
      try {
        const ports = portUsedByOthers.map(i => i.toString()).join(',')
        const prompt = util.format(promptFormat, ports)
        this.promptAction.showToast({
          message: prompt,
          duration: 4000
        })
      } catch (e) {
        console.error(`showToast error`, e);
      }
    }
  }

  build() {
    if (this.isPc) {
      PcIndex()
    } else {
      PhoneOrTablet()
    }
  }
}
