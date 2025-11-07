import { util } from '@kit.ArkTS';
import { AlertDialog, SelectDialog } from "@kit.ArkUI";
import { PortMapping } from '../model/Emulator';

interface PortMappingItem {
  id: string
  model: PortMapping
}

interface MappingCandidate {
  name: ResourceStr
  host: number
  guest: number
}

const CANDIDATES: MappingCandidate[] = [{
  name: 'SSH',
  guest: 22,
  host: 2222
}, {
  name: 'HTTP',
  guest: 80,
  host: 8000
}, {
  name: 'HTTPS',
  guest: 443,
  host: 1443
}, {
  name: 'MySQL',
  guest: 3306,
  host: 3306
}, {
  name: 'RDP',
  guest: 3389,
  host: 3389
}, {
  name: 'VNC',
  guest: 5900,
  host: 5900
}, {
  name: 'SMB',
  guest: 445,
  host: 1445
}, {
  name: 'SMTP',
  guest: 25,
  host: 1025
}, {
  name: 'Telnet',
  guest: 23,
  host: 1023
}]

@Component
export struct PortMappingEdit {
  @State items: PortMappingItem[] = []
  @Require onChanged: (value: PortMappingItem[]) => void
  @State indexToRemove: number = -1
  @Watch('onCandidateToAdd') @State candidateToAdd: number | undefined = undefined
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
  portCandidatesController: CustomDialogController = new CustomDialogController({
    builder: SelectDialog({
      title: $r('app.string.select_freq_used_port'),
      selectedIndex: this.candidateToAdd,
      confirm: {
        value: $r('app.string.setting_generic_cancel'),
        action: () => {
        },
      },
      radioContent: CANDIDATES.map((c, i) => ({
        title: util.format('%s(%d:%d)', c.name, c.guest, c.host),
        action: () => {
          this.candidateToAdd = i
        }
      } as SheetInfo))
    })
  })

  private addPortMapping() {
    const id = util.generateRandomUUID()
    this.items.push({ id, model: {} });
  }

  build() {
    Column() {

      Row() {
        Row() {
          Text($r('app.string.guest_port'))
            .fontSize($r('sys.float.Body_M'))
            .textAlign(TextAlign.Center)
            .width(100)
          Divider().vertical(true)
          Text($r('app.string.host_port'))
            .fontSize($r('sys.float.Body_M'))
            .textAlign(TextAlign.Center)
            .width(100)
        }
        .height(36)
        .padding({
          left: $r('sys.float.padding_level6'),
          right: $r('sys.float.padding_level6')
        })

        Blank().layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([$r('sys.color.icon_secondary')])
          .margin({ right: 8 })
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .bindMenu([{
            enabled: !this.portMappingError(),
            value: $r('app.string.add_freq_used_port'),
            action: () => {
              this.candidateToAdd = undefined
              this.portCandidatesController.open()
            }
          }, {
            enabled: !this.portMappingError(),
            value: '自定义端口',
            action: () => {
              if (!this.portMappingError()) {
                this.addPortMapping();
              }
            }
          }])
      }
      .height(48)

      List() {
        ForEach(this.items, (item: PortMappingItem, index) => {
          this.buildPortMappingItem(item.model, (host) => {
            const it = this.items[index]
            this.replacePortMapping(index, { id: it.id, model: { host, guest: it.model.guest } })
          }, (guest) => {
            const it = this.items[index]
            this.replacePortMapping(index, { id: it.id, model: { guest, host: it.model.host } });
          }, () => {
            this.indexToRemove = index
            this.confirmController.open()
          })
        }, (item: PortMappingItem, index) => 'pm-' + item.id)
      }
      .divider({
        strokeWidth: 0.1,
        color: $r('sys.color.icon_secondary'),
        startMargin: 5,
        endMargin: 5
      })
    }
  }

  private removePortMappingItem(index: number) {
    const copy = [...this.items];
    copy.splice(index, 1);
    this.items = copy;
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
            .fontSize($r('sys.float.Body_M'))
            .type(InputType.Number)
            .width(90)
            .margin({ left: 5, right: 5 })
            .onChange((value) => {
              const guest = value ? parseInt(value) : undefined;
              updateGuest(guest)
            })
          Divider().vertical(true)
          TextInput({ text: item.host?.toString(), placeholder: 'Host' })
            .fontSize($r('sys.float.Body_M'))
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
          .fontSize(18)
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
      .height(42)
      .width('100%')
    }
  }

  private replacePortMapping(index: number, up: PortMappingItem) {
    const copy = this.items.map((el, i) => i === index ? up : el);
    this.items = copy;
  }

  addPortMappingEnabled(): boolean {
    const invalid = this.items.map(it => it.model).filter(it => !(it.guest && it.host));
    return invalid.length === 0;
  }

  portMappingError(): string | Resource | undefined {
    let mappings = this.items.map(it => it.model);
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
    if (guestPorts.size < this.items.length || hostPorts.size < this.items.length) {
      return $r('app.string.setting_duplicated_port')
    }

    return undefined
  }

  onCandidateToAdd() {
    if (this.candidateToAdd !== undefined) {
      const c: MappingCandidate = CANDIDATES[this.candidateToAdd!!]
      const id: string = util.generateRandomUUID();
      this.items.push({
        id: id,
        model: { host: c.host, guest: c.guest }
      })
    }
  }

  private getResourceString(name: string): string | undefined {
    return this.getUIContext()
      .getHostContext()?.resourceManager.getStringByNameSync(name);
  }
}

export { PortMappingItem }