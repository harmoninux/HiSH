import RootfsManagementContent from '../components/RootfsManagementContent'

@Entry
@Component
export struct RootfsManagement {
  build() {
    Column() {
      RootfsManagementContent({ toolBar: true })
    }
  }
}