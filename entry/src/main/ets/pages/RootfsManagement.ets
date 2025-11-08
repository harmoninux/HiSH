import RootfsManagementContent from '../components/RootfsManagementContent'

@Entry
@Component
struct RootfsManagement {
  build() {
    Column() {
      RootfsManagementContent({ toolBar: true })
    }
  }
}