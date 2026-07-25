import EmulatorManagementContent from '../components/EmulatorManagementContent'

@Entry
@Component
export struct EmulatorManagementPage {
  build() {
    Column() {
      EmulatorManagementContent()
    }
  }
}