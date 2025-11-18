@Component
struct PingContent {
  build() {
    Column() {
      TextInput({ placeholder: 'IP地址' })
    }
  }
}