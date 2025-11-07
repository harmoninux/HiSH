import { cpuOptions, getCpuCount, getMemSize, memOptions } from "../lib/systemProfile"
import { Emulator } from "../model/Emulator"
import { PortMappingEdit, PortMappingItem } from "./PortMappingEdit"
import ReactiveGrid from "./ReactiveGrid"
import { BlockTitle, ItemTitle, SettingBlockStyle, SettingItem } from "./SettingsBase"
import { util } from "@kit.ArkTS"

@Component
export default struct EditEmulatorContent {
  @Require emulator: Emulator
  @Require onFinished: (item: Emulator) => void
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  @State cpuOptions: SelectOption[] = []
  @State memOptions: SelectOption[] = []
  @Watch('onPortMappingChanged') @State portMappingItems: PortMappingItem[] = []

  aboutToAppear(): void {

    const cpuCount = getCpuCount()
    this.cpuOptions = cpuOptions.filter(c => c <= cpuCount).map(c => ({ value: c.toString() } as SelectOption))

    const memSize = getMemSize()
    this.memOptions = memOptions.filter(c => c < memSize).map(c => ({ value: c.toString() } as SelectOption))

    this.portMappingItems =
      this.emulator.portMapping.map(it => ({ id: util.generateRandomUUID(), model: it } as PortMappingItem))
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
  private memorySetting() {
    Select(this.memOptions)
      .width(100)
      .value(this.emulator.memory.toString())
      .onSelect((_i, value) => {
        this.emulator.memory = parseInt(value)
      })
  }

  @Builder
  buildEmulatorEdit() {
    Column() {
      Column() {
        Text('名称')
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_tertiary'))
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
