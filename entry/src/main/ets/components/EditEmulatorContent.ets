import { cpuOptions, getCpuCount, getMemSize, memOptions } from "../lib/systemProfile"
import { defaultEmulator, defaultRootfs, Emulator, RootFilesystem } from "../model/Emulator"
import { PortMappingEdit, PortMappingItem } from "./PortMappingEdit"
import ReactiveGrid from "./ReactiveGrid"
import { BlockTitle, ItemTitle, SettingBlockStyle, SettingItem } from "./SettingsBase"
import { util } from "@kit.ArkTS"
import appOption from "../model/appOption"
import { PromptAction } from "@kit.ArkUI"
import copyFile from "../lib/copyFile"

@Component
export default struct EditEmulatorContent {
  @Require emulator: Emulator
  @Require onFinished: (item: Emulator) => void
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  @State cpuOptions: SelectOption[] = []
  @State memOptions: SelectOption[] = []
  @State isCreate: boolean = true
  @State rootFilesystemOptions: SelectOption[] = []
  @State selectedRootfs: string = defaultRootfs.name
  @Watch('onPortMappingChanged') @State portMappingItems: PortMappingItem[] = []
  filesDir: string = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {

    const cpuCount = getCpuCount()
    this.cpuOptions = cpuOptions.filter(c => c <= cpuCount).map(c => ({ value: c.toString() } as SelectOption))

    const memSize = getMemSize()
    this.memOptions = memOptions.filter(c => c < memSize).map(c => ({ value: c.toString() } as SelectOption))

    this.portMappingItems =
      this.emulator.portMapping.map(it => ({ id: util.generateRandomUUID(), model: it } as PortMappingItem))

    const rootfs = AppStorage.get(appOption.rootFilesystems) as RootFilesystem[]
    this.rootFilesystemOptions = rootfs.map(it => ({ value: it.name } as SelectOption))

    const emulators = AppStorage.get(appOption.emulators) as Emulator[]
    this.isCreate = emulators.findIndex(it => it.id === this.emulator.id) < 0
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
      .onChange((value) => this.emulator.init = value.trim())
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
          .maxLength(64)
          .enabled(this.emulator.id !== defaultEmulator.id)
          .onChange((value) => {
            this.emulator.name = value.trim()
          })
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

      if (this.isCreate) {
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
      }

      BlockTitle({ content: $r("app.string.setting_networking") })
      Column() {
        Column() {
          SettingItem({
            title: '端口映射',
            subTitle: '将对主机的端口访问转发到模拟器'
          })
          PortMappingEdit({
            items: this.portMappingItems,
            onChanged: (value) => this.portMappingItems = value
          })
            .borderRadius(15)
            .margin({ left: 10, right: 10, bottom: 10 })
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
          title: 'init',
          subTitle: '模拟器Linux启动脚本',
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
          .onClick(() => this.onEditFinished())
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

  private validate(): string | undefined {

    const emulators = AppStorage.get(appOption.emulators) as Emulator[]

    if (this.emulator.name.length === 0) {
      return '请输入模拟器名称'
    }

    const nameUsed = emulators
      .findIndex(it => it.id !== this.emulator.id && it.name === this.emulator.name) >= 0
    if (nameUsed) {
      return '模拟器名称重复，请换一个'
    }

    const mappingError = this.portMappingError()
    if (mappingError) {
      return mappingError
    }

    if (this.emulator.init.length === 0) {
      return '需要指定init'
    }

    return undefined
  }

  private async onEditFinished() {
    const error = this.validate()
    if (!error) {
      if (this.isCreate) {
        const roots = AppStorage.get(appOption.rootFilesystems) as RootFilesystem[]
        const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
        const selected = roots.find(it => it.name === this.selectedRootfs)!!
        const source = selected.path
        const target = vmBaseDir + '/' + this.emulator.id + selected.path.substring(selected.path.lastIndexOf('.'))
        await copyFile(source, target)
        this.emulator.rootFilesystem = target
      }

      this.onFinished(this.emulator)
    } else {
      this.promptAction.showToast({
        message: error,
        duration: 3000
      })
    }
  }

  private portMappingError(): string | undefined {
    let mappings = this.portMappingItems.map(it => it.model)
    let i = mappings
      .findIndex(it => {
        return !(it.guest && it.host)
      })
    if (i >= 0) {
      const temp = this.getResourceString('setting_incomplete_port_mapping')
      return util.format(temp, (i + 1))
    }

    i = mappings
      .findIndex(it => {
        return (it.host || 0) <= 1000
      })
    if (i >= 0) {
      const temp = this.getResourceString('setting_port_should_larger')
      return util.format(temp, (i + 1))
    }

    const guestPorts = new Set(mappings.map(it => it.guest))
    const hostPorts = new Set(mappings.map(it => it.host))
    if (guestPorts.size < mappings.length || hostPorts.size < mappings.length) {
      return this.getResourceString('setting_duplicated_port')
    }

    return undefined
  }

  private getResourceString(name: string): string | undefined {
    return this.getUIContext()
      .getHostContext()?.resourceManager.getStringByNameSync(name);
  }
}
