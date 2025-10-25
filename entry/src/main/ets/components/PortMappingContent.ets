import { common } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { PortMapping } from '../model/appOption'
import { JSON, util } from '@kit.ArkTS';
import appOption from '../model/appOption';

@Component
export struct PortMappingContent {
  @Watch('savePortMapping') @State vmPortMappingEnabled: boolean = false
  @Watch('savePortMapping') @State portMappings: PortMapping[] = []
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences

  async aboutToAppear() {
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), appOption.preferenceName)

    const json = await this.preferences!.get(appOption.portMapping, '[]') as string;
    this.vmPortMappingEnabled = await this.preferences!.get(appOption.portMappingEnabled, false) as boolean
    this.portMappings = JSON.parse(json) as PortMapping[]
  }

  private addPortMapping() {
    this.portMappings.push({});
  }

  build() {
    Column() {

      Row() {
        Blank().layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([!this.portMappingError() ? $r('sys.color.icon_secondary') : '#555555'])
          .aspectRatio(1)
          .padding(4)
          .margin({ right: 5 })
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            if (!this.portMappingError()) {
              this.addPortMapping();
            }
          })
      }

      Scroll() {
        Column() {
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
        }
      }
      .layoutWeight(1)
      .align(Alignment.Top)

      Column() {

        if (this.portMappingError()) {
          Text(this.portMappingError())
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.alert'))
        }

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
      }
      .margin({ top: 5 })
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
    if (!this.portMappingError()) {
      const json = JSON.stringify(this.portMappings)
      await this.preferences!.put(appOption.portMappingEnabled, this.vmPortMappingEnabled)
      await this.preferences!.put(appOption.portMapping, json)
      await this.preferences!.flush()
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