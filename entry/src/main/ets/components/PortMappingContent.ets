import { common } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { PortMapping } from '../model/appOption'
import { JSON, util } from '@kit.ArkTS';
import appOption from '../model/appOption';

@Component
export struct PortMappingContent {
  @State vmPortMappingEnabled: boolean = false
  @State portMappings: PortMapping[] = [{ guest: 22, host: 2222 }]
  onSaved?: () => void
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences

  async aboutToAppear() {
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), appOption.preferenceName)

    const json = await this.preferences!.get(appOption.portMapping, '[]') as string;
    this.vmPortMappingEnabled = await this.preferences!.get(appOption.portMappingEnabled, false) as boolean
    this.portMappings = JSON.parse(json) as PortMapping[]
  }

  build() {
    Column() {

      Row() {
        Text($r('app.string.setting_enable_port_mapping'))
          .fontSize($r('sys.float.Body_L'))
          .fontColor($r('sys.color.font_primary'))
        Checkbox()
          .select(this.vmPortMappingEnabled)
          .onChange((value: boolean) => {
            this.vmPortMappingEnabled = value
          })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
      .padding({
        left: $r('sys.float.padding_level6'),
        right: $r('sys.float.padding_level4'),
        top: $r('sys.float.padding_level2'),
        bottom: $r('sys.float.padding_level2')
      })
      .width('100%')

      ForEach(this.portMappings, (item: PortMapping, index) => {
        this.buildPortMappingItem(item, (host) => {
          const it = this.portMappings[index]
          this.replacePortMapping(index, { host, guest: it.guest })
        }, (guest) => {
          const it = this.portMappings[index]
          this.replacePortMapping(index, { guest, host: it.host });
        }, () => {
          const copy = [...this.portMappings]
          copy.splice(index, 1)
          this.portMappings = copy
        })
      }, (_item: PortMapping, index) => 'port-mapping-' + index)

      Column() {

        if (this.portMappingError()) {
          Text(this.portMappingError())
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.alert'))
        }

        Button($r('app.string.setting_add'), { buttonStyle: ButtonStyleMode.NORMAL })
          .enabled(this.addPortMappingEnabled() && !this.portMappingError())
          .width('100%')
          .margin({ top: 10 })
          .onClick(() => {
            this.portMappings.push({})
          })

        Button($r('app.string.SettingSave_label'))
          .enabled(!this.portMappingError())
          .width('100%')
          .margin({ top: 10 })
          .onClick(() => {
            this.savePortMapping()
          })
      }
      .margin({ top: 30 })
    }
  }

  @Builder
  buildPortMappingItem(
    item: PortMapping,
    updateHost: (port: number | undefined) => void,
    updateGuest: (port: number | undefined) => void,
    remove: () => void
  ) {
    Row() {
      Row() {
        TextInput({ text: item.guest?.toString(), placeholder: 'Guest' })
          .type(InputType.Number)
          .width(80)
          .onChange((value) => {
            const guest = value ? parseInt(value) : undefined;
            updateGuest(guest)
          })
        Text(':').margin({ left: 5, right: 5 })
        TextInput({ text: item.host?.toString(), placeholder: 'Host' })
          .type(InputType.Number)
          .width(80)
          .onChange((value) => {
            const host = value ? parseInt(value) : undefined;
            updateHost(host)
          })
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      SymbolGlyph($r('sys.symbol.minus_circle'))
        .fontColor([$r('sys.color.alert')])
        .fontSize('24vp')
        .onClick(() => remove())
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: $r('sys.float.padding_level6'),
      right: $r('sys.float.padding_level6'),
      top: $r('sys.float.padding_level2'),
      bottom: $r('sys.float.padding_level2')
    })
    .width('100%')
  }

  async savePortMapping() {
    const json = JSON.stringify(this.portMappings)
    await this.preferences!.put(appOption.portMappingEnabled, this.vmPortMappingEnabled)
    await this.preferences!.put(appOption.portMapping, json)
    await this.preferences!.flush()

    if (this.onSaved) {
      this.onSaved()
    }
  }

  private replacePortMapping(index: number, up: PortMapping) {
    const copy = this.portMappings.map((el, i) => i === index ? up : el);
    this.portMappings = copy;
  }

  addPortMappingEnabled(): boolean {
    const invalid = this.portMappings.filter(it => !(it.guest && it.host));
    return invalid.length === 0;
  }

  portMappingError(): string | Resource | undefined {
    let i = this.portMappings
      .findIndex(it => {
        return !(it.guest && it.host)
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_incomplete_port_mapping'))
      return util.format(temp, (i + 1))
    }

    i = this.portMappings
      .findIndex(it => {
        return (it.host || 0) <= 1000
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_port_should_larger'))
      return util.format(temp, (i + 1))
    }

    const guestPorts = new Set(this.portMappings.map(it => it.guest))
    const hostPorts = new Set(this.portMappings.map(it => it.host))
    if (guestPorts.size < this.portMappings.length || hostPorts.size < this.portMappings.length) {
      return $r('app.string.setting_duplicated_port')
    }

    return undefined
  }
}