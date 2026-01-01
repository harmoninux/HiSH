import { CustomContentDialog } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';
import { SharedFolderContent, SharedFolderController } from '../components/SharedFolderContent';
import appOption from "../model/appOption";
import { util } from "@kit.ArkTS";
import EmulatorManagementContent from "../components/EmulatorManagementContent";
import EmulatorListGrid from "../components/EmulatorListGrid";
import EditEmulatorContent from "../components/EditEmulatorContent";
import { Emulator } from "../model/Emulator";
import RootfsManagementContent from "../components/RootfsManagementContent";
import UserGuide from "../components/UserGuide";
import { webview } from "@kit.ArkWeb";
import PowerManagementContent from '../components/PowerManagementContent';
import VmStatusBar from '../components/VmStatusBar';

@Component
struct PcIndex {
  @StorageProp(appOption.sharedHost) sharedHost?: string = undefined
  @StorageProp(appOption.sharedGuest) sharedGuest?: string = undefined
  emulatorManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.emulator_management_title'),
      contentBuilder: () => {
        this.buildSimulatorManagement();
      }
    })
  })
  rootfsManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.image_management_title'),
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
      primaryTitle: $r('app.string.user_guide_title'),
      contentBuilder: () => {
        this.buildGuideList();
      }
    })
  })
  powerManagementController: CustomDialogController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.power_management_title'),
      contentBuilder: () => {
        this.buildPowerManagement();
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
          Text($r('app.string.EntryAbility_label'))
            .margin({ left: 10 })
        }

        VmStatusBar()
          .margin({ left: 20 })

        Blank()

        Row() {
          Button({
            type: ButtonType.Normal,
            buttonStyle: ButtonStyleMode.TEXTUAL,
            controlSize: ControlSize.SMALL
          }) {
            SymbolGlyph($r('sys.symbol.display'))
              .fontSize('20vp')
              .width(20)
              .height(20)
              .fontColor(['#ffffff'])
          }
          .borderRadius(4)
          .padding(4)
          .margin({ right: 10 })
          .onClick((event: ClickEvent) => {
            const vncPort = AppStorage.get<number>('vncWebSocketPort');
            if (vncPort) {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/VncPage',
                params: { vncPort: vncPort }
              });
            } else {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.vnc_service_not_started') });
            }
          })
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

      WebTerminal({ virtKeyEnabled: false })
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
      Button($r('app.string.btn_add'))
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
            rootVda: '/dev/sda',
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
        primaryTitle: edit ? $r('app.string.edit_emulator_title') : item.name,
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
      openPage: (title: string | Resource, url: string) => {
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

  @Builder
  buildPowerManagement() {
    PowerManagementContent()
  }
}

@Component
struct PhoneOrTablet {
  build() {
    Column() {
      // 虚拟机状态监控条
      Row() {
        VmStatusBar()
          .layoutWeight(1)
      }
      .width('100%')
      .height(32)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))

      WebTerminal({ virtKeyEnabled: true })
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
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
    Column() {
      if (this.isPc) {
        PcIndex()
      } else {
        PhoneOrTablet()
      }
    }
    .width('100%')
    .height('100%')
  }
}
