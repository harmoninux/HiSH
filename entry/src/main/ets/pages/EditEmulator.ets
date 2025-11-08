import EditEmulatorContent from '../components/EditEmulatorContent'
import appOption, { savePreference } from '../model/appOption'
import { Emulator } from '../model/Emulator'
import { util } from '@kit.ArkTS'

@Entry
@Component
struct EditEmulator {
  @StorageLink(appOption.emulators) emulators: Emulator[] = []
  @State emulator?: Emulator = undefined
  private emId = (this.getUIContext().getRouter().getParams() as Record<string, string>)['id'] as string

  aboutToAppear(): void {
    const emulators = AppStorage.get(appOption.emulators) as Emulator[]
    const found = emulators.find(it => it.id === this.emId)

    if (!found) {
      this.emId = util.generateRandomUUID()
      this.emulator = {
        id: this.emId,
        name: '',
        init: '/init',
        cpu: 1,
        memory: 512,
        portMapping: [],
        rootFilesystem: '',
        sharedFolderReadonly: false
      }
    } else {
      this.emulator = {
        id: found.id,
        name: found.name,
        init: found.init,
        cpu: found.cpu,
        memory: found.memory,
        portMapping: found.portMapping,
        rootFilesystem: found.rootFilesystem,
        sharedFolderReadonly: found.sharedFolderReadonly
      }
    }
  }

  build() {
    Column() {
      if (this.emulator) {
        EditEmulatorContent({
          emulator: this.emulator,
          onFinished: async (item: Emulator) => {
            await this.saveEmulator(item)
          }
        })
      }
    }
  }

  private async saveEmulator(em: Emulator) {

    const i = this.emulators.findIndex(it => it.id === em.id)

    if (i >= 0) {
      //  update
      this.emulators[i] = em
    } else {
      this.emulators.push(em)
    }

    await savePreference(appOption.emulators, this.emulators, this.getUIContext())

    this.getUIContext().getRouter().back()
  }
}
