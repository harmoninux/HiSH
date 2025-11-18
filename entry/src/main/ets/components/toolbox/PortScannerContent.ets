@Preview
@Component
export struct PortScannerContent {
  @Builder
  build() {
    Column() {
      TextInput({ placeholder: '输入主机地址' })
        .margin({  bottom: 15 })

      TextInput({ placeholder: '输入端口范围' })
        .margin({  bottom: 15 })

      Button('开始扫描')
        .width('100%')
    }
    .padding(10)
  }
}