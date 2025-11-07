import EditEmulatorContent from '../components/EditEmulatorContent'
import appOption from '../model/appOption'
import { Emulator } from '../model/Emulator'
import { util } from '@kit.ArkTS'

@Entry
@Component
struct EditEmulator {
  @State emulator?: Emulator = undefined
  private emId = (this.getUIContext().getRouter().getParams() as Record<string, string>)['id'] as string

  aboutToAppear(): void {
    const emulators = AppStorage.get(appOption.emulators) as Emulator[]
    this.emulator = emulators.find(it => it.id === this.emId)

    if (!this.emulator) {
      this.emId = util.generateRandomUUID()
      this.emulator = {
        id: this.emId,
        name: '',
        init: '/init',
        cpu: 1,
        memory: 512,
        networking: false,
        portMapping: [],
        rootFilesystem: '',
        sharedFolderReadonly: false
      }
    }
  }

  build() {
    Column() {
      if (this.emulator) {
        EditEmulatorContent({
          emulator: this.emulator,
          onFinished: (item: Emulator) => {
            this.saveEmulator(item)
          }
        })
      }
    }
  }

  private saveEmulator(em: Emulator) {
    //  TODO: add to storage
    //  TODO: copy image
    //  TODO: save to pref
  }
}
