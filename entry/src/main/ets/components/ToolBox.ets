@Component
struct BlockTitle {
  content?: string | Resource

  build() {
    Text(this.content)
      .margin({ bottom: 10, left: 20 })
      .width('100%')
  }
}

@Component
export struct LinkItem {
  @Require icon: Resource
  @Require title: string | Resource
  @Require subTitle: string | Resource
  click?: () => void

  build() {
    Row() {
      Column() {
        Image(this.icon)
          .width(28)
          .height(28)
        Text(this.title)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .margin({ top: 10 })
        Text(this.subTitle)
          .fontSize(11)
          .fontColor($r('sys.color.font_tertiary'))
          .margin({ top: 5 })
      }
      .onClick(() => {
        if (this.click) {
          this.click();
        }
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding({
        left: 5,
        right: 5,
        top: 10,
        bottom: 10
      })
      .borderRadius(10)
    }
    .padding(5)
    .width(110)
  }
}

@Component
export struct ToolBox {
  build() {
    Column() {
      Scroll() {
        Column() {

          BlockTitle({ content: '网络工具' })
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start
          }) {
            LinkItem({
              icon: $r('app.media.http'),
              title: 'HTTP',
              subTitle: '测试HTTP请求',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HttpRequestPage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.dns'),
              title: 'DNS解析',
              subTitle: 'DNS解析工具',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/DnsResolvePage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.port_scan'),
              title: '端口扫描',
              subTitle: '扫描开放端口',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/PortScannerPage'
                })
              }
            })
          }
          .backgroundColor($r('app.color.setting_block_background'))
          .borderRadius(10)
          .padding(10)
          .margin({ bottom: 20 })

          BlockTitle({ content: '数据工具' })
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start
          }) {
            LinkItem({
              icon: $r('app.media.hash_check'),
              title: '哈希校验',
              subTitle: '验证文件完整性',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HashVerifyPage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.hash'),
              title: '哈希生成',
              subTitle: '生成哈希值',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HashGeneratePage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.base64'),
              title: 'Base64',
              subTitle: '编码/解码',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/Base64EncodePage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.url_codec'),
              title: 'URLEncode',
              subTitle: '编码/解码',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/UrlEncodePage'
                })
              }
            })
            LinkItem({
              icon: $r('app.media.regex'),
              title: '正则验证',
              subTitle: '验证正则表达式',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/RegexVerifyPage'
                })
              }
            })
          }
          .borderRadius(10)
          .backgroundColor($r('app.color.setting_block_background'))
          .padding(10)
          .margin({ bottom: 20 })
        }
        .margin(10)
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }
}