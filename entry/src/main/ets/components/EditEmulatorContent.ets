import { cpuOptions, getCpuCount, getMemSize, memOptions } from "../lib/systemProfile"
import { defaultRootfs, Emulator, RootFilesystem } from "../model/Emulator"
import { PortMappingEdit, PortMappingItem } from "./PortMappingEdit"
import ReactiveGrid from "./ReactiveGrid"
import { BlockTitle, ItemTitle, SettingBlockStyle, SettingItem } from "./SettingsBase"
import { util } from "@kit.ArkTS"
import appOption from "../model/appOption"

@Component
export default struct EditEmulatorContent {
  @Require emulator: Emulator
  @Require onFinished: (item: Emulator) => void
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  @State cpuOptions: SelectOption[] = []
  @State memOptions: SelectOption[] = []
  @State rootFilesystemOptions: SelectOption[] = []
  @State selectedRootfs: string = defaultRootfs.name
  @Watch('onPortMappingChanged') @State portMappingItems: PortMappingItem[] = []

  aboutToAppear(): void {

    const cpuCount = getCpuCount()
    this.cpuOptions = cpuOptions.filter(c => c <= cpuCount).map(c => ({ value: c.toString() } as SelectOption))

    const memSize = getMemSize()
    this.memOptions = memOptions.filter(c => c < memSize).map(c => ({ value: c.toString() } as SelectOption))

    this.portMappingItems =
      this.emulator.portMapping.map(it => ({ id: util.generateRandomUUID(), model: it } as PortMappingItem))

    const rootfs = AppStorage.get(appOption.rootFilesystems) as RootFilesystem[]
    this.rootFilesystemOptions = rootfs.map(it => ({ value: it.name } as SelectOption))
  }

  @Builder
  private cpuSetting() {
    Select(this.cpuOptions)
      .width(100)
      .value(this.emulator.cpu.toString())
      .onSelect((_i, value) => {
        this.emulator.cpu = parseInt(value)
      })
  }

  @Builder
  private rootFilesystemSetting() {
    Select(this.rootFilesystemOptions)
      .width(150)
      .value(this.selectedRootfs)
      .onSelect((_i, value) => {
        this.selectedRootfs = value
      })
  }

  @Builder
  private memorySetting() {
    Select(this.memOptions)
      .width(100)
      .value(this.emulator.memory.toString())
      .onSelect((_i, value) => {
        this.emulator.memory = parseInt(value)
      })
  }

  @Builder
  private initSetting() {
    TextInput({ text: this.emulator.init })
      .width(120)
      .onChange((value) => this.emulator.init = value)
  }

  @Builder
  buildEmulatorEdit() {
    Column() {
      Column() {
        Text('名称')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .margin({ bottom: 10 })
        TextInput({ placeholder: '名称', text: this.emulator.name })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: $r("app.string.setting_block_system") })
      Column() {
        SettingItem({
          title: $r('app.string.setting_cpu'),
          subTitle: $r('app.string.setting_cpu_desc'),
          content: () => {
            this.cpuSetting()
          }
        })

        SettingItem({
          title: $r('app.string.setting_mem_size'),
          subTitle: $r('app.string.setting_mem_size_desc'),
          content: () => {
            this.memorySetting()
          }
        })
      }
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: '镜像' })
      Column() {
        SettingItem({
          title: '镜像',
          subTitle: '选择模拟器使用的镜像',
          content: () => {
            this.rootFilesystemSetting()
          }
        })
      }
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: $r("app.string.setting_networking") })
      Column() {
        SettingItem({
          title: '开启网络',
          subTitle: '开启模拟器的网络',
          content: () => {
            this.enableNetworking()
          }
        })

        Column() {
          ItemTitle({
            title: '端口映射',
            subTitle: '将对主机的端口访问转发到模拟器'
          })
            .padding({ left: $r('sys.float.padding_level6'), right: $r('sys.float.padding_level6') })
          PortMappingEdit({
            items: this.portMappingItems,
            onChanged: (value) => this.portMappingItems = value
          })
            .borderRadius(15)
            .margin(10)
            .backgroundColor($r('app.color.setting_block_background_2'))
        }
        .flexGrow(1)
        .alignItems(HorizontalAlign.Start)
      }
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: $r("app.string.setting_shared_folder") })
      Column() {
        SettingItem({
          title: '共享文件夹只读',
          subTitle: '禁止模拟器对共享文件夹进行写操作',
          content: () => {
            this.sharedFolderReadonly()
          }
        })
      }
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: '高级设置' })
      Column() {
        SettingItem({
          title: '设置init',
          subTitle: '模拟器启动时的配置脚本',
          content: () => {
            this.initSetting()
          }
        })
      }
      .attributeModifier(this.blockStyle)
    }
    .width('100%')
  }

  @Builder
  private enableNetworking() {
    Checkbox()
      .select(this.emulator.networking)
      .onChange((value: boolean) => {
        this.emulator.networking = value
      })
  }

  @Builder
  private sharedFolderReadonly() {
    Checkbox()
      .select(this.emulator.sharedFolderReadonly)
      .onChange((value: boolean) => {
        this.emulator.sharedFolderReadonly = value
      })
  }

  build() {
    Column() {
      Row() {
        Text('编辑模拟器')
          .fontSize(16)
          .padding({ left: 15 })

        Blank().layoutWeight(1)

        Button('完成', { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => this.onFinished(this.emulator))
      }
      .height(56)

      Scroll() {
        ReactiveGrid({
          contentBuilder: () => {
            this.buildEmulatorEdit()
          }
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }

  onPortMappingChanged() {
    this.emulator.portMapping = this.portMappingItems.map(it => it.model)
  }
}
