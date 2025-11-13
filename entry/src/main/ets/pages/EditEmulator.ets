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
          onFinished: (item: Emulator) => {
            this.getUIContext().getRouter().back()
          },
          titleBar: true,
          editing: true
        })
      }
    }
  }
}
