import { Emulator } from '../model/Emulator';
import readQcow2VirtualSize from '../lib/readQcow2VirtualSize';
import appOption from '../model/appOption';
import { util } from '@kit.ArkTS';

@Component
export default struct EmulatorItem {
  @Prop emulator: Emulator
  @Prop isRunning: boolean
  @Prop isDefault: boolean
  @Require onEdit: (item: Emulator) => void
  @Require onDelete: (item: Emulator) => void
  @Require onExport: (item: Emulator) => void
  @Require onCopy: (item: Emulator) => void
  @Require onSetDefault: (item: Emulator) => void
  @Require onStart: (item: Emulator) => void
  @Require onPowerManage: (item: Emulator) => void
  @Require onImageManage: (item: Emulator) => void
  @StorageProp(appOption.currentEmulatorStatus) currentStatus: string = 'RUNNING'
  @State storageSize: number = 0
  filesDir = this.getUIContext().getHostContext()!!.getApplicationContext().filesDir

  aboutToAppear(): void {
    const rootfsPath = this.emulator.rootFilesystem
    const virtualSize = readQcow2VirtualSize(rootfsPath)
    this.storageSize = virtualSize / (1024 * 1024 * 1024)
  }

  build() {
    Column() {
      Row() {
        Text(this.emulator.name)
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)
        if (this.isRunning) {
          Text(this.getStatusText())
            .fontSize($r('sys.float.Body_M'))
            .fontColor(this.getStatusColor())
            .height(20)
          Button($r('app.string.btn_power_management'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
            .fontSize($r('sys.float.Body_M'))
            .onClick(() => this.onPowerManage(this.emulator))
            .height(20)
          Button($r('app.string.btn_image_management'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
            .fontSize($r('sys.float.Body_M'))
            .onClick(() => this.onImageManage(this.emulator))
            .height(20)
        } else {
          Button($r('app.string.btn_run'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
            .fontSize($r('sys.float.Body_M'))
            .onClick(() => this.onStart(this.emulator))
            .height(20)
          Button($r('app.string.btn_image_management'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
            .fontSize($r('sys.float.Body_M'))
            .onClick(() => this.onImageManage(this.emulator))
            .height(20)
        }

      }
      .padding({
        left: 5,
        right: 5,
        top: 10,
        bottom: 10
      })
      .width('100%')

      Row() {
        Column() {
          Text(this.emulator.cpu + ' ' + getContext(this).resourceManager.getStringSync($r('app.string.label_cores').id)).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text('CPU').fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.formatMemory()).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_primary'))
          Text($r('app.string.label_memory')).fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.storageSize.toFixed(1) + ' GB')
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.label_virtual_disk')).fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)

        Column() {
          Text(this.emulator.portMapping.length.toString())
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.font_primary'))
          Text($r('app.string.label_port_mapping')).fontSize($r('sys.float.Body_S')).fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .layoutWeight(1)
      }
      .padding({ top: 10, bottom: 10 })
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background_2'))
      .width('100%')

      Row() {
        Row() {
          Checkbox()
            .select(this.isDefault)
            .size({ width: $r('sys.float.Body_L'), height: $r('sys.float.Body_L') })
            .enabled(false)
          Text($r('app.string.label_set_default')).fontSize($r('sys.float.Body_M')).fontColor($r('sys.color.font_tertiary'))
        }
        .clickEffect({ level: ClickEffectLevel.LIGHT })
        .onClick(() => {
          this.onSetDefault(this.emulator)
        })

        Blank().layoutWeight(1)
        Button($r('app.string.btn_delete'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onDelete(this.emulator))
        Button($r('app.string.btn_export'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onExport(this.emulator))
        Button($r('app.string.btn_copy'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onCopy(this.emulator))
        Button($r('app.string.btn_modify'), { buttonStyle: ButtonStyleMode.TEXTUAL, controlSize: ControlSize.SMALL })
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .onClick(() => this.onEdit(this.emulator))
      }
      .padding({ top: 5, bottom: 5 })
      .width('100%')
    }
    .borderRadius(10)
    .padding({
      left: 10,
      right: 10
    })
    .clickEffect({ level: ClickEffectLevel.LIGHT })
    .backgroundColor($r('app.color.setting_block_background'))
  }

  private formatMemory() {
    if (this.emulator.memory >= 1024) {
      return (this.emulator.memory / 1024).toFixed(1) + ' GB'
    }
    return this.emulator.memory + ' MB';
  }

  private getStatusText(): Resource {
    switch (this.currentStatus) {
      case 'PAUSED':
        return $r('app.string.status_paused2')
      case 'REBOOTING':
        return $r('app.string.status_rebooting')
      case 'SHUTDOWN':
        return $r('app.string.status_shutdown2')
      case 'ABNORMAL':
        return $r('app.string.status_abnormal')
      case 'RUNNING':
      default:
        return $r('app.string.status_running')
    }
  }

  private getStatusColor(): string {
    switch (this.currentStatus) {
      case 'PAUSED':
        return '#3498DB' // Blue
      case 'REBOOTING':
        return '#F39C12' // Orange
      case 'SHUTDOWN':
        return '#E74C3C' // Red
      case 'ABNORMAL':
        return '#E74C3C' // Red
      case 'RUNNING':
      default:
        return '#388E3C' // Green
    }
  }
}
