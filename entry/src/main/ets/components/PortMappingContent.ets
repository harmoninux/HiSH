import { common } from '@kit.AbilityKit';
import preference from '@ohos.data.preferences';
import { PortMapping } from '../model/appOption'
import { JSON, util } from '@kit.ArkTS';
import appOption from '../model/appOption';
import { AlertDialog } from "@kit.ArkUI";

interface PortMappingItem {
  id: string
  model: PortMapping
}

const DEFAULT_MAPPING: PortMapping[] = [{ host: 2222, guest: 22 }, { host: 8080, guest: 80 }]

@Component
export struct PortMappingContent {
  @Watch('savePortMapping') @State vmPortMappingEnabled: boolean = false
  @Watch('savePortMapping') @State portMappings: PortMappingItem[] = []
  @State indexToRemove: number = -1
  context = this.getUIContext().getHostContext() as common.UIAbilityContext
  preferences?: preference.Preferences
  confirmController: CustomDialogController = new CustomDialogController({
    builder: AlertDialog({
      primaryTitle: $r('app.string.confirm_remove'),
      content: $r('app.string.confirm_remove_port_mapping'),
      primaryButton: {
        value: $r('app.string.setting_generic_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.setting_generic_confirm'),
        role: ButtonRole.ERROR,
        action: () => {
          if (this.indexToRemove >= 0) {
            this.removePortMappingItem(this.indexToRemove)
            this.indexToRemove = -1
          }
        }
      }
    })
  })

  async aboutToAppear() {
    this.preferences = await preference.getPreferences(this.context.getApplicationContext(), appOption.preferenceName)

    const json = await this.preferences!.get(appOption.portMapping, JSON.stringify(DEFAULT_MAPPING)) as string;
    this.vmPortMappingEnabled = await this.preferences!.get(appOption.portMappingEnabled, false) as boolean
    const parsed: PortMapping[] = JSON.parse(json) as PortMapping[];

    this.portMappings = parsed.map(it => {
      const id = util.generateRandomUUID()
      return { id, model: it } as PortMappingItem
    })
  }

  private addPortMapping() {
    const id = util.generateRandomUUID()
    this.portMappings.push({ id, model: {} });
  }

  build() {
    Column() {

      Row() {
        Row() {
          Text($r('app.string.guest_port'))
            .textAlign(TextAlign.Center)
            .width(100)
          Divider().vertical(true)
          Text($r('app.string.host_port'))
            .textAlign(TextAlign.Center)
            .width(100)
        }
        .height(48)
        .padding({
          left: $r('sys.float.padding_level6'),
          right: $r('sys.float.padding_level6')
        })

        Blank().layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([!this.portMappingError() ? $r('sys.color.icon_secondary') : '#555555'])
          .aspectRatio(1)
          .padding(4)
          .margin({ right: 5 })
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .onClick(() => {
            if (!this.portMappingError()) {
              this.addPortMapping();
            }
          })
      }
      .height(56)

      List() {
        ForEach(this.portMappings, (item: PortMappingItem, index) => {
          this.buildPortMappingItem(item.model, (host) => {
            const it = this.portMappings[index]
            this.replacePortMapping(index, { id: it.id, model: { host, guest: it.model.guest } })
          }, (guest) => {
            const it = this.portMappings[index]
            this.replacePortMapping(index, { id: it.id, model: { guest, host: it.model.host } });
          }, () => {
            this.indexToRemove = index
            this.confirmController.open()
          })
        }, (item: PortMappingItem, index) => 'pm-' + item.id)
      }
      .layoutWeight(1)
      .divider({
        strokeWidth: 0.1,
        color: $r('sys.color.icon_secondary'),
        startMargin: 5,
        endMargin: 5
      })
      .scrollBarWidth(1)

      Column() {

        if (this.portMappingError()) {
          Text(this.portMappingError())
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.alert'))
        } else {
          Text($r('app.string.restart_hish_to_apply_changes'))
            .fontSize($r('sys.float.Body_M'))
            .fontColor($r('sys.color.icon_secondary'))
        }

        Row() {
          Blank().layoutWeight(1)
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
            left: 15,
            right: 15,
            top: 10,
            bottom: 10
          })
          .onClick(() => {
            this.vmPortMappingEnabled = !this.vmPortMappingEnabled
          })
          .clickEffect({ level: ClickEffectLevel.LIGHT })
        }
        .width('100%')
      }
      .margin({ top: 5 })
    }
  }

  private removePortMappingItem(index: number) {
    const copy = [...this.portMappings];
    copy.splice(index, 1);
    this.portMappings = copy;
  }

  @Builder
  buildPortMappingItem(
    item: PortMapping,
    updateHost: (port: number | undefined) => void,
    updateGuest: (port: number | undefined) => void,
    remove: () => void
  ) {
    ListItem() {
      Row() {
        Row() {
          TextInput({ text: item.guest?.toString(), placeholder: 'Guest' })
            .type(InputType.Number)
            .width(90)
            .margin({ left: 5, right: 5 })
            .onChange((value) => {
              const guest = value ? parseInt(value) : undefined;
              updateGuest(guest)
            })
          Divider().vertical(true)
          TextInput({ text: item.host?.toString(), placeholder: 'Host' })
            .type(InputType.Number)
            .width(90)
            .margin({ left: 5, right: 5 })
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
      .height(48)
      .width('100%')
    }
  }

  async savePortMapping() {
    if (!this.portMappingError()) {
      const json = JSON.stringify(this.portMappings.map(it => it.model))
      await this.preferences!.put(appOption.portMappingEnabled, this.vmPortMappingEnabled)
      await this.preferences!.put(appOption.portMapping, json)
      await this.preferences!.flush()
    }
  }

  private replacePortMapping(index: number, up: PortMappingItem) {
    const copy = this.portMappings.map((el, i) => i === index ? up : el);
    this.portMappings = copy;
  }

  addPortMappingEnabled(): boolean {
    const invalid = this.portMappings.map(it => it.model).filter(it => !(it.guest && it.host));
    return invalid.length === 0;
  }

  portMappingError(): string | Resource | undefined {
    let mappings = this.portMappings.map(it => it.model);
    let i = mappings
      .findIndex(it => {
        return !(it.guest && it.host)
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_incomplete_port_mapping'))
      return util.format(temp, (i + 1))
    }

    i = mappings
      .findIndex(it => {
        return (it.host || 0) <= 1000
      })
    if (i >= 0) {
      const temp = this.context.resourceManager.getStringSync($r('app.string.setting_port_should_larger'))
      return util.format(temp, (i + 1))
    }

    const guestPorts = new Set(mappings.map(it => it.guest))
    const hostPorts = new Set(mappings.map(it => it.host))
    if (guestPorts.size < this.portMappings.length || hostPorts.size < this.portMappings.length) {
      return $r('app.string.setting_duplicated_port')
    }

    return undefined
  }
}