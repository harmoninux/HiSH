import { common } from "@kit.AbilityKit"
import { CustomContentDialog } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';
import { SharedFolderContent } from '../components/SharedFolderContent';
import { PortMappingContent } from "../components/PortMappingContent";

@Component
struct PcIndex {
  @Require rootFs: string
  @Require sharedFolder: string
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

      WebTerminal({ showVirtKey: false, sharedFolder: this.sharedFolder, rootFs: this.rootFs })
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
      host: (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext().filesDir +
        '/share',
      guest: '/mnt/share'
    })
  }
}

@Component
struct PhoneOrTablet {
  @Require rootFs: string
  @Require sharedFolder: string
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
        WebTerminal({
          showVirtKey: true, sharedFolder: this.sharedFolder, rootFs: this.rootFs
        })
      }
      .tabBar(this.tabBuilder($r('app.string.shell'), 0, $r('sys.symbol.house')))

      TabContent() {
        SharedFolderContent({
          host: this.appContext.filesDir + '/share',
          guest: '/mnt/share'
        })
      }
      .tabBar(this.tabBuilder($r('app.string.setting_shared_folder'), 1, $r('sys.symbol.folder')))

      TabContent() {
        PortMappingContent()
      }
      .tabBar(this.tabBuilder($r('app.string.setting_port_mapping'), 2, $r('sys.symbol.reverse_order')))

      TabContent() {
        SettingsContent()
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

  aboutToAppear(): void {
    // webview.WebviewController.setWebDebuggingAccess(true)
  }

  build() {
    if (this.isPc) {
      PcIndex({ rootFs: 'rootfs_aarch64.qcow2', sharedFolder: 'share' })
    } else {
      PhoneOrTablet({ rootFs: 'rootfs_aarch64.qcow2', sharedFolder: 'share' })
    }
  }
}
