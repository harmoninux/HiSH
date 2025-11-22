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
  @Prop icon: Resource
  @Prop title: string | Resource
  @Prop subTitle: string | Resource
  click?: () => void

  build() {
    Row() {
      Row() {
        Image($r('app.media.startIcon'))
          .width(28)
          .height(28)
          .margin({ right: 5 })
        Column() {
          Text(this.title)
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
          Text(this.subTitle)
            .fontSize($r('sys.float.Body_S'))
            .fontColor($r('sys.color.font_tertiary'))
            .margin({ top: 5 })
        }
        .flexGrow(1)
        .alignItems(HorizontalAlign.Start)
      }
      .onClick(() => {
        if (this.click) {
          this.click();
        }
      })
      .clickEffect({ level: ClickEffectLevel.MIDDLE })
      .alignItems(VerticalAlign.Center)
      .width('100%')
      .padding({
        left: 5,
        right: 5,
        top: 10,
        bottom: 10
      })
      .borderRadius(10)
      .backgroundColor($r('app.color.setting_block_background'))
    }
    .padding(5)
    .width(160)
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
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: 'DNS解析',
              subTitle: 'DNS解析工具',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/DnsResolvePage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.house'),
              title: '端口扫描',
              subTitle: '扫描开放端口',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/PortScannerPage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.house'),
              title: 'ping',
              subTitle: '检测网络延迟',
              click: () => {
              }
            })
            LinkItem({
              icon: $r('sys.symbol.house'),
              title: 'HTTP',
              subTitle: '测试HTTP请求',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HttpRequestPage'
                })
              }
            })
          }
          .margin({ bottom: 20 })

          BlockTitle({ content: '数据工具' })
          Flex({
            direction: FlexDirection.Row,
            wrap: FlexWrap.Wrap,
            justifyContent: FlexAlign.Start
          }) {
            LinkItem({
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: '哈希校验',
              subTitle: '验证文件完整性',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HashVerifyPage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: '哈希生成',
              subTitle: '生成哈希值',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/HashGeneratePage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: 'Base64',
              subTitle: '编码/解码',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/Base64EncodePage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: 'URL',
              subTitle: '编码/解码',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/UrlEncodePage'
                })
              }
            })
            LinkItem({
              icon: $r('sys.symbol.doc_text_badge_checkmark'),
              title: '正则验证',
              subTitle: '验证正则表达式',
              click: () => {
                this.getUIContext().getRouter().pushUrl({
                  url: 'pages/toolbox/RegexVerifyPage'
                })
              }
            })
          }
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