import { common } from "@kit.AbilityKit"
import { CustomContentDialog } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';
import { SharedFolderContent } from '../components/SharedFolderContent';
import appOption from "../model/appOption";
import { util } from "@kit.ArkTS";
import EmulatorManagement from "../components/EmulatorManagement";
import EmulatorListGrid from "../components/EmulatorListGrid";
import EditEmulatorContent from "../components/EditEmulatorContent";
import { Emulator } from "../model/Emulator";
import RootfsManagementContent from "../components/RootfsManagementContent";
import UserGuide from "../components/UserGuide";
import { webview } from "@kit.ArkWeb";
import { ToolBox } from "../components/ToolBox";

@Component
struct PcIndex {
  @StorageProp(appOption.sharedHost) sharedHost?: string = undefined
  @StorageProp(appOption.sharedGuest) sharedGuest?: string = undefined
  emulatorManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '模拟器管理',
      contentBuilder: () => {
        this.buildSimulatorManagement();
      }
    })
  })
  rootfsManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '镜像管理',
      contentBuilder: () => {
        this.buildRootfsManagement();
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
  settingController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.Setting_title'),
      contentBuilder: () => {
        this.buildSettings();
      }
    })
  })
  userGuideController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: '使用指南',
      contentBuilder: () => {
        this.buildGuideList();
      }
    })
  })
  webController = new webview.WebviewController()

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
          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            SymbolGlyph($r('sys.symbol.more'))
              .fontSize('20vp')
              .width(20)
              .height(20)
              .fontColor(['#ffffff'])
          }
          .borderRadius(4)
          .padding(4)
          .margin({ right: 10 })
          .onClick((event: ClickEvent) => {
            this.emulatorManagementController.open()
          })

          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            SymbolGlyph($r('sys.symbol.externaldrive_3'))
              .fontSize('20vp')
              .width(20)
              .height(20)
              .fontColor(['#ffffff'])
          }
          .borderRadius(4)
          .padding(4)
          .margin({ right: 10 })
          .onClick((event: ClickEvent) => {
            this.rootfsManagementController.open()
          })

          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            Image($r('app.media.folder')).width(20)
          }
          .borderRadius(4)
          .padding(4)
          .margin({ right: 10 })
          .onClick((event: ClickEvent) => {
            this.sharedFolderController.open()
          })

          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            Image($r('app.media.gearshape')).width(20)
          }
          .borderRadius(4)
          .padding(4)
          .margin({ right: 10 })
          .onClick((event: ClickEvent) => {
            this.settingController.open()
          })

          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            SymbolGlyph($r('sys.symbol.book_pages'))
              .fontSize('20vp')
              .width(20)
              .height(20)
              .fontColor(['#ffffff'])
          }
          .borderRadius(4)
          .padding(4)
          .onClick((event: ClickEvent) => {
            this.userGuideController.open()
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
  buildSimulatorManagement() {
    Column() {
      EmulatorListGrid({
        onEditEmulator: (item, edit) => {
          this.openEditEmulatorDialog(item, edit);
        },
        specifiedBreak: 'xs'
      })
      Button('添加')
        .width('100%')
        .onClick(() => {
          const id = util.generateRandomUUID()
          const emulatorToEdit: Emulator = {
            id,
            name: '',
            init: '/init',
            cpu: 1,
            memory: 512,
            portMapping: [],
            rootVda: '/dev/vda',
            rootFilesystem: '',
            sharedFolderReadonly: false
          }
          this.openEditEmulatorDialog(emulatorToEdit, true)
        })
    }
  }

  private openEditEmulatorDialog(item: Emulator, edit: boolean) {
    const emulatorToEdit: Emulator = {
      id: item.id,
      name: item.name,
      init: item.init,
      cpu: item.cpu,
      memory: item.memory,
      portMapping: item.portMapping,
      rootVda: item.rootVda,
      rootFilesystem: item.rootFilesystem,
      sharedFolderReadonly: item.sharedFolderReadonly
    };
    const controller = new CustomDialogController({
      builder: CustomContentDialog({
        primaryTitle: edit ? '编辑模拟器' : item.name,
        contentBuilder: () => {
          this.buildEditEmulator(emulatorToEdit, edit, (): void => controller.close());
        }
      })
    });
    controller.open();
  }

  @Builder
  buildRootfsManagement() {
    Column() {
      RootfsManagementContent({
        toolBar: false,
        specifiedBreak: 'xs'
      })
    }
  }

  @Builder
  buildEditEmulator(emulator: Emulator, edit: boolean, onFinished: (item: Emulator) => void) {
    EditEmulatorContent({
      emulator: emulator,
      onFinished: onFinished,
      specifiedBreak: 'xs',
      titleBar: false,
      editing: edit
    })
  }

  @Builder
  buildGuideList() {
    UserGuide({
      toolBar: false,
      openPage: (title: string, url: string) => {
        const controller = new CustomDialogController({
          builder: CustomContentDialog({
            primaryTitle: title,
            contentBuilder: () => {
              this.buildGuideWebView(url);
            }
          })
        })
        controller.open()
      }
    })
  }

  @Builder
  private buildGuideWebView(url: string) {
    Web({
      src: $rawfile(url),
      controller: this.webController
    }).javaScriptProxy({
      permission: `{
          "javascriptProxyPermission": {
            "urlPermissionList": [
              {
                "scheme": "resource",
                "host": "rawfile",
                "port": "",
                "path": ""
              }
            ]
          }
        }`,
      object: this,
      name: 'native',
      methodList: [],
      controller: this.webController
    })
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.black'));
  }

  @Builder
  buildSettings() {
    SettingsContent()
  }

  @Builder
  buildSharedFolder() {
    Row() {
      if (this.sharedHost) {
        SharedFolderContent({
          host: this.sharedHost,
          guest: this.sharedGuest
        })
      }
    }
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
        Column() {
          ToolBox()
        }
      }
      .tabBar(this.tabBuilder('开发者工具', 2, $r('sys.symbol.briefcase')))

      TabContent() {
        Column() {
          Text($r('app.string.Setting_title'))
            .fontSize(18)
            .height(56)
            .width('100%')
            .padding({ left: 15, right: 15 })
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

  aboutToAppear(): void {
    // webview.WebviewController.setWebDebuggingAccess(true)
  }

  build() {
    if (this.isPc) {
      PcIndex()
    } else {
      PhoneOrTablet()
    }
  }
}
