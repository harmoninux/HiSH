import connection from '@ohos.net.connection'

@Component
export struct DnsResolveContent {
  @State domain: string = 'developer.huawei.com'
  @State address: string[] = []

  build() {
    Column() {
      TextInput({ text: this.domain, placeholder: '输入域名' })
        .margin({ bottom: 15 })
        .onChange((value) => {
          this.domain = value
          this.address = []
        })

      Button('查询')
        .width('100%')
        .enabled(this.domain.trim().length > 0)
        .onClick(() => this.queryDns())

      if (this.address.length > 0) {
        Column() {
          Text(this.domain + '的解析结果：').width('100%')
          ForEach(this.address, (a: string, i: number) => {
            Text(a).width('100%')
          }, (a: string, i: number) => a)
        }
        .margin({ top: 15 })
        .padding(10)
        .borderRadius(10)
        .backgroundColor($r('app.color.setting_block_background'))
      }
    }
    .padding(10)
  }

  async queryDns() {
    try {
      const handle = await connection.getDefaultNet()
      const data = await handle.getAddressesByName(this.domain)
      this.address = data.map(it => it.address)
    } catch (e) {
      this.address = []
    }
  }
}