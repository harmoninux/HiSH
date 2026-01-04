import { cpuOptions, getCpuCount, getMemSize, memOptions } from "../lib/systemProfile"
import { defaultRootfs, Emulator, RootFilesystem } from "../model/Emulator"
import { PortMappingEdit, PortMappingItem } from "./PortMappingEdit"
import ReactiveGrid from "./ReactiveGrid"
import { BlockTitle, SettingBlockStyle, SettingItem } from "./SettingsBase"
import { util } from "@kit.ArkTS"
import appOption, { savePreference } from "../model/appOption"
import { LoadingDialog, PromptAction } from "@kit.ArkUI"
import copyFile from "../lib/copyFile"
import { BackButton } from "./BackButton"

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
  @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @Prop specifiedBreak?: string = undefined
  @Prop titleBar: boolean = true
  @Prop editing: boolean = true
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
  private vdaSetting() {
    TextInput({ text: this.emulator.rootVda })
      .width(120)
      .onChange((value) => this.emulator.rootVda = value.trim())
  }

  @Builder
  buildEmulatorEdit() {
    Column() {
      Column() {
        Text($r('app.string.emulator_name'))
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .margin({ bottom: 10 })
        TextInput({ placeholder: $r('app.string.emulator_name_placeholder'), text: this.emulator.name })
          .maxLength(64)
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
        BlockTitle({ content: $r('app.string.setting_block_image') })
        Column() {
          SettingItem({
            title: $r('app.string.setting_block_image'),
            subTitle: $r('app.string.setting_image_desc'),
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
            title: $r('app.string.setting_port_mapping'),
            subTitle: $r('app.string.setting_port_mapping_desc')
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
          title: $r('app.string.setting_shared_readonly'),
          subTitle: $r('app.string.setting_shared_readonly_desc'),
          content: () => {
            this.sharedFolderReadonly()
          }
        })
      }
      .attributeModifier(this.blockStyle)

      BlockTitle({ content: $r('app.string.setting_advanced') })
      Column() {
        SettingItem({
          title: $r('app.string.setting_init_script'),
          subTitle: $r('app.string.setting_init_desc'),
          content: () => {
            this.initSetting()
          }
        })
        SettingItem({
          title: $r('app.string.setting_root_device'),
          subTitle: $r('app.string.setting_root_desc'),
          content: () => {
            this.vdaSetting()
          }
        })
      }
      .attributeModifier(this.blockStyle)
    }
    .enabled(this.editing)
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
      if (this.titleBar) {
        Row() {
          BackButton()
            .padding({ left: 15 })

          Text(this.editing ? $r('app.string.edit_emulator_title') : this.emulator.name)
            .fontSize(18)

          Blank().layoutWeight(1)

          if (this.editing) {
            Button($r('app.string.btn_finish'), { buttonStyle: ButtonStyleMode.TEXTUAL })
              .onClick(() => this.onEditFinished())
          }
        }
        .height(56)
      }

      Scroll() {
        ReactiveGrid({
          contentBuilder: () => {
            this.buildEmulatorEdit()
          },
          specifiedBreak: this.specifiedBreak
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)

      if (!this.titleBar && this.editing) {
        Button($r('app.string.btn_finish'))
          .width('100%')
          .onClick(() => this.onEditFinished())
      }
    }
  }

  onPortMappingChanged() {
    this.emulator.portMapping = this.portMappingItems.map(it => it.model)
  }

  private validate(): string | undefined {

    const emulators = AppStorage.get(appOption.emulators) as Emulator[]

    if (this.emulator.name.length === 0) {
      return this.getResourceString('err_input_name')
    }

    const nameUsed = emulators
      .findIndex(it => it.id !== this.emulator.id && it.name === this.emulator.name) >= 0
    if (nameUsed) {
      return this.getResourceString('err_name_duplicate')
    }

    const mappingError = this.portMappingError()
    if (mappingError) {
      return mappingError
    }

    if (this.emulator.init.length === 0) {
      return this.getResourceString('err_need_init')
    }

    return undefined
  }

  private async onEditFinished() {
    const error = this.validate()
    if (!error) {

      const progress = new CustomDialogController({
        builder: LoadingDialog({
          content: $r('app.string.edit_emulator_saving'),
        }),
        autoCancel: false
      })

      try {
        progress.open()
        if (this.isCreate) {
          const roots = AppStorage.get(appOption.rootFilesystems) as RootFilesystem[]
          const vmBaseDir = AppStorage.get(appOption.vmBaseDir) as string
          const selected = roots.find(it => it.name === this.selectedRootfs)!!
          const source = selected.path
          const target = vmBaseDir + '/' + this.emulator.id + selected.path.substring(selected.path.lastIndexOf('.'))
          await copyFile(source, target)
          this.emulator.rootFilesystem = target
        }

        await this.saveEmulators()

        this.onFinished(this.emulator)
      } finally {
        progress.close()
      }
    } else {
      this.promptAction.showToast({
        message: error,
        duration: 3000
      })
    }
  }

  private async saveEmulators() {
    const i = this.emulators.findIndex(it => it.id === this.emulator.id)
    if (i >= 0) {
      //  update
      this.emulators[i] = this.emulator
    } else {
      this.emulators.push(this.emulator)
    }
    await savePreference(appOption.emulators, this.emulators, this.getUIContext())
  }

  private portMappingError(): string | undefined {
    let mappings = this.portMappingItems.map(it => it.model)
    
    for (let i = 0; i < mappings.length; i++) {
      const m = mappings[i]
      if (!m.guest || !m.host) {
        const temp = this.getResourceString('err_port_mapping_incomplete')
        return util.format(temp, (i + 1))
      }
      if ((m.host || 0) <= 1000) {
        const temp = this.getResourceString('err_port_mapping_host_port')
        return util.format(temp, i + 1, m.host)
      }
    }
    
    // 检查重复
    const guestPorts = mappings.map(it => it.guest)
    const hostPorts = mappings.map(it => it.host)
    const dupGuest = guestPorts.find((p, i) => guestPorts.indexOf(p) !== i)
    const dupHost = hostPorts.find((p, i) => hostPorts.indexOf(p) !== i)
    
    if (dupGuest) {
      const temp = this.getResourceString('err_port_duplicate_guest')
      return util.format(temp, dupGuest)
    }
    if (dupHost) {
      const temp = this.getResourceString('err_port_duplicate_host')
      return util.format(temp, dupHost)
    }
    
    return undefined
  }

  private getResourceString(name: string): string | undefined {
    return this.getUIContext()
      .getHostContext()?.resourceManager.getStringByNameSync(name);
  }
}
