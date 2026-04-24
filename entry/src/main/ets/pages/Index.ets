import { CustomContentDialog } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import WebTerminal from '../components/WebTerminal'
import SettingsContent from '../components/SettingsContent';
import { SharedFolderContent } from '../components/SharedFolderContent';
import appOption from "../model/appOption";
import { util } from "@kit.ArkTS";
import EmulatorListGrid from "../components/EmulatorListGrid";
import EditEmulatorContent from "../components/EditEmulatorContent";
import { Emulator } from "../model/Emulator";
import RootfsManagementContent from "../components/RootfsManagementContent";
import UserGuide from "../components/UserGuide";
import { webview } from "@kit.ArkWeb";
import VmStatusBar from '../components/VmStatusBar';
import sessionManager from '../lib/SessionManager';

/** Represents an active terminal session tab */
@Observed
class SessionTab {
  index: number = 0;
  name: string = '';
  connected: boolean = false;

  constructor(index: number, name: string, connected: boolean) {
    this.index = index;
    this.name = name;
    this.connected = connected;
  }
}

@Component
struct SessionTabBar {
  @Link activeSessionIndex: number
  @State tabs: SessionTab[] = []
  @StorageProp(appOption.maxSessions) maxSessions: number = 1
  /** Called when a new session is opened, with the session index */
  onSessionOpened?: (index: number) => void
  /** Called when user clicks an existing tab to switch to it */
  onSessionSwitched?: (index: number) => void

  aboutToAppear(): void {
    this.refreshTabs()
  }

  private refreshTabs(): void {
    const sessions = sessionManager.getAllSessions()
    const newTabs: SessionTab[] = []
    for (const s of sessions) {
      newTabs.push(new SessionTab(s.index, s.name, s.connected))
    }
    this.tabs = newTabs
  }

  build() {
    Row() {
      ForEach(this.tabs, (tab: SessionTab) => {
        Button(tab.name, { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(28)
          .fontSize(12)
          .borderRadius(4)
          .padding({ left: 8, right: 8 })
          .backgroundColor(this.activeSessionIndex === tab.index ? '#444' : '#222')
          .fontColor(this.activeSessionIndex === tab.index ? '#fff' : '#999')
          .margin({ right: 2 })
          .onClick(() => {
            this.activeSessionIndex = tab.index
            if (this.onSessionSwitched) {
              this.onSessionSwitched(tab.index)
            }
          })
      }, (tab: SessionTab) => tab.index.toString())

      if (this.tabs.length < this.maxSessions) {
        Button('+', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(28)
          .width(28)
          .fontSize(14)
          .borderRadius(4)
          .fontColor('#999')
          .backgroundColor('#222')
          .margin({ right: 2 })
          .onClick(async () => {
            // Find the next unopened session
            const allSessions = sessionManager.getAllSessions()
            const unopened = allSessions.find(s => !s.connected)
            if (unopened) {
              await sessionManager.openSession(unopened.index)
              this.refreshTabs()
              this.activeSessionIndex = unopened.index
              if (this.onSessionOpened) {
                this.onSessionOpened(unopened.index)
              }
            }
          })
      }
    }
    .width('100%')
    .height(32)
    .padding({ left: 4 })
    .backgroundColor('#1a1a1a')
  }
}

@Component
struct PcIndex {
  @StorageProp(appOption.sharedHost) sharedHost?: string = undefined
  @StorageProp(appOption.sharedGuest) sharedGuest?: string = undefined
  @StorageProp(appOption.displayStatusBar) displayStatusBar: boolean = false
  @StorageProp(appOption.maxSessions) maxSessions: number = 1
  @State activeSessionIndex: number = 0
  /** Track which session indices have been opened (need a WebTerminal) */
  @State openedSessionIndices: number[] = [0]
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
  webController = new webview.WebviewController()

  build() {
    Column() {
      Row() {
        Row() {
          Image($r('app.media.startIcon'))
            .width(20)
          Text($r('app.string.EntryAbility_label'))
            .fontColor($r('sys.color.white'))
            .margin({ left: 10 })
        }

        if (this.displayStatusBar) {
          VmStatusBar({ reactive: false })
            .margin({ left: 20 })
        }

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
            const vncEnabled = AppStorage.get<boolean>(appOption.vncEnabled)!!
            if (vncEnabled) {
              this.getUIContext().getRouter().pushUrl({
                url: 'pages/VncPage'
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

      if (this.maxSessions > 1) {
        SessionTabBar({
          activeSessionIndex: $activeSessionIndex,
          onSessionOpened: (idx: number) => {
            this.openedSessionIndices = [...this.openedSessionIndices, idx]
          },
          onSessionSwitched: (idx: number) => {
            // Ensure the WebTerminal for this session exists
            if (!this.openedSessionIndices.includes(idx)) {
              this.openedSessionIndices = [...this.openedSessionIndices, idx]
            }
          }
        })
      }

      // Stack multiple WebTerminal instances, show only the active one.
      // Use offset to move inactive terminals off-screen instead of visibility:Hidden,
      // because Hidden WebViews may not execute JS or respond to runJavaScript.
      Stack() {
        ForEach(this.openedSessionIndices, (idx: number) => {
          WebTerminal({
            virtKeyEnabled: false,
            sessionIndex: idx,
            isActive: this.activeSessionIndex === idx
          })
            .layoutWeight(1)
            .offset({ y: this.activeSessionIndex === idx ? 0 : '-100%' })
        }, (idx: number) => idx.toString())
      }
      .layoutWeight(1)
      .clip(true)
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
            sharedFolderReadonly: false,
            maxSessions: 1
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
      sharedFolderReadonly: item.sharedFolderReadonly,
      maxSessions: item.maxSessions ?? 1
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
}

@Component
struct PhoneOrTablet {
  @StorageProp(appOption.displayStatusBar) displayStatusBar: boolean = false
  @StorageProp(appOption.maxSessions) maxSessions: number = 1
  @State activeSessionIndex: number = 0
  /** Track which session indices have been opened (need a WebTerminal) */
  @State openedSessionIndices: number[] = [0]

  build() {
    Column() {
      if (this.displayStatusBar) {
        // 虚拟机状态监控条
        Row() {
          VmStatusBar({ reactive: true })
            .layoutWeight(1)
        }
        .width('100%')
        .height(28)
        .padding({ left: 6, right: 6 })
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      }

      if (this.maxSessions > 1) {
        SessionTabBar({
          activeSessionIndex: $activeSessionIndex,
          onSessionOpened: (idx: number) => {
            this.openedSessionIndices = [...this.openedSessionIndices, idx]
          },
          onSessionSwitched: (idx: number) => {
            // Ensure the WebTerminal for this session exists
            if (!this.openedSessionIndices.includes(idx)) {
              this.openedSessionIndices = [...this.openedSessionIndices, idx]
            }
          }
        })
      }

      // Stack multiple WebTerminal instances, show only the active one.
      // Use offset to move inactive terminals off-screen instead of visibility:Hidden,
      // because Hidden WebViews may not execute JS or respond to runJavaScript.
      Stack() {
        ForEach(this.openedSessionIndices, (idx: number) => {
          WebTerminal({
            virtKeyEnabled: true,
            sessionIndex: idx,
            isActive: this.activeSessionIndex === idx
          })
            .layoutWeight(1)
            .offset({ y: this.activeSessionIndex === idx ? 0 : '-100%' })
        }, (idx: number) => idx.toString())
      }
      .layoutWeight(1)
      .clip(true)
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
