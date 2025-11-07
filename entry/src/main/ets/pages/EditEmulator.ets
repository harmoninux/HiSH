import EditEmulatorContent from '../components/EditEmulatorContent'
import { Emulator } from '../model/Emulator'

const e: Emulator = {
  id: '1',
  name: '777777',
  cpu: 0,
  memory: 0,
  networking: false,
  init: undefined,
  portMapping: [],
  rootFilesystem: '',
  sharedFolder: undefined
}

@Preview
@Entry
@Component
struct EditEmulator {
  build() {
    Column() {
      EditEmulatorContent({ emulator: e })
    }
  }
}
