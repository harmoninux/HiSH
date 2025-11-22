import { util } from "@kit.ArkTS"
import { CommonModifier, LoadingDialog } from "@kit.ArkUI"
import { http } from "@kit.NetworkKit"
import { Exception } from "@ohos/commons-compress"
import { BusinessError } from '@kit.BasicServicesKit';
import copyToClipboard from "../../lib/copyToClipboard";

const methods: SelectOption[] = [{
  value: 'GET'
}, {
  value: 'POST'
}, {
  value: 'PUT'
}, {
  value: 'DELETE'
}]

interface KvPair {
  id: string
  key: string
  value: string
}

@Component
struct ParamsList {
  @Prop params: KvPair[] = []
  @Require keyName: string
  @Require keyPlaceholder: string
  @Require valueName: string
  @Require valuePlaceholder: string
  @Require onChange: (params: KvPair[]) => void

  build() {
    Column() {
      Row() {
        Text(this.keyName)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(2)
        Text(this.valueName)
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .layoutWeight(3)
        Text('操作')
          .fontSize($r('sys.float.Body_M'))
          .fontColor($r('sys.color.font_secondary'))
          .width(30)
      }
      .margin({ bottom: 5 })

      ForEach(this.params, (item: KvPair, i: number) => {
        Row() {
          TextInput({ placeholder: this.keyPlaceholder, text: item.key })
            .margin({ right: 5 })
            .layoutWeight(2)
            .onChange((value) => this.onItemKeyUpdate(item.id, value))
          TextInput({ placeholder: this.valuePlaceholder, text: item.value })
            .layoutWeight(3)
            .onChange((value) => this.onItemValueUpdate(item.id, value))
          Row() {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontColor([$r('sys.color.alert')])
              .fontSize(18)
              .onClick(() => {
                this.onRemoveItem(item.id)
              })
          }
          .justifyContent(FlexAlign.Center)
          .width(30)
        }
        .margin({ bottom: 5 })
      }, (item: KvPair, i: number) => item.id)

      Button('添加', { buttonStyle: ButtonStyleMode.TEXTUAL })
        .width('100%')
        .onClick(() => this.onAddItem())
    }
  }

  private onItemValueUpdate(id: string, value: string): void {
    const i = this.params.findIndex(it => it.id === id)
    this.params[i].value = value
    this.onChange(this.params)
  }

  private onItemKeyUpdate(id: string, key: string): void {
    const i = this.params.findIndex(it => it.id === id)
    this.params[i].key = key
    this.onChange(this.params)
  }

  private onAddItem(): void {
    this.params.push({ id: util.generateRandomUUID(), key: '', value: '' })
    this.onChange(this.params)
  }

  private onRemoveItem(id: string) {
    const i = this.params.findIndex(it => it.id === id)
    this.params.splice(i, 1)
    this.onChange(this.params)
  }
}


@Component
export struct HttpRequestContent {
  @State method: http.RequestMethod = http.RequestMethod.GET
  @State url: string = ''
  @State timeout: number = 1000;
  @State params: KvPair[] = [{ id: '0', key: '', value: '' }]
  @State headers: KvPair[] = [{ id: '0', key: '', value: '' }]
  @State body: string = ''
  @State barModifier: CommonModifier = new CommonModifier()
  @State success: boolean = false
  @State status: string = ''
  @State resHeaders: string = ''
  @State resBody: string = ''

  aboutToAppear(): void {
    this.barModifier.align(Alignment.Start)
  }

  build() {
    Scroll() {
      Column() {

        Column() {
          Text('请求设置')
            .fontSize($r('sys.float.Body_L'))
            .fontColor($r('sys.color.font_primary'))
            .width('100%')
            .margin({ bottom: 10 })

          TextInput({ placeholder: 'URL', text: this.url })
            .margin({ bottom: 10 })
            .onChange((value) => this.url = value)

          Row() {
            Select(methods)
              .value(this.method)
              .width(100)
              .layoutWeight(2)
              .onSelect((i, value) => this.method = value as http.RequestMethod)
            Blank().width(10)
            Button('发起请求')
              .layoutWeight(3)
              .onClick(() => this.sendRequest())
          }

          Tabs({ barModifier: this.barModifier }) {
            TabContent() {
              Column() {
                ParamsList({
                  keyName: '参数名',
                  keyPlaceholder: 'id',
                  valueName: '参数值',
                  valuePlaceholder: '123',
                  params: this.params,
                  onChange: (params) => this.params = [...params]
                })
              }
            }.tabBar(SubTabBarStyle.of('参数'))

            TabContent() {
              Column() {
                ParamsList({
                  keyName: '请求头名称',
                  keyPlaceholder: 'Cookie',
                  valueName: '请求头值',
                  valuePlaceholder: 'abc',
                  params: this.headers,
                  onChange: (params) => this.headers = [...params]
                })
              }
            }.tabBar(SubTabBarStyle.of('请求头'))

            TabContent() {
              Column() {
                TextArea({ placeholder: '{\"key\": \"value\"}', text: this.body })
                  .height(120)
                  .onChange((value) => this.body = value)
              }
            }.tabBar(SubTabBarStyle.of('请求体'))

            TabContent() {
              Column() {
                Row() {
                  Text('超时时间（ms）')
                    .fontSize($r('sys.float.Body_L'))
                    .fontColor($r('sys.color.font_secondary'))
                  Blank().layoutWeight(1)
                  TextInput({ text: this.timeout.toString() })
                    .type(InputType.Number)
                    .width(120)
                    .onChange((value) => {
                      const timeout = parseInt(value)
                      if (!isNaN(timeout)) {
                        this.timeout = timeout
                      }
                    })
                }
              }
            }.tabBar(SubTabBarStyle.of('设置'))
          }
          .height('auto')
          .barMode(BarMode.Scrollable)
        }
        .borderRadius(10)
        .padding(10)
        .margin({ bottom: 15 })
        .backgroundColor($r('app.color.setting_block_background'))

        Column() {
          Row() {
            Text('响应结果')
              .fontSize($r('sys.float.Body_L'))
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)

            Text('状态码：' + this.status)
              .fontSize($r('sys.float.Body_M'))
              .fontColor($r('sys.color.font_primary'))
              .layoutWeight(1)
              .textAlign(TextAlign.End)
          }

          Tabs({ barModifier: this.barModifier }) {
            TabContent() {
              Column() {
                Text(this.resBody)
                  .width('100%')
                  .borderWidth(1)
                  .borderColor($r('app.color.setting_block_background_2'))
                  .borderRadius(5)
                  .padding(10)
                  .margin(5)
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor($r('sys.color.font_secondary'))
                Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .width('100%')
                  .onClick(async () => {
                    await copyToClipboard(this.resBody, this.getUIContext())
                  })
              }
            }.tabBar(SubTabBarStyle.of('响应体'))

            TabContent() {
              Column() {
                Text(this.resHeaders)
                  .width('100%')
                  .borderWidth(1)
                  .borderColor($r('app.color.setting_block_background_2'))
                  .borderRadius(5)
                  .padding(10)
                  .margin(5)
                  .fontSize($r('sys.float.Body_M'))
                  .fontColor($r('sys.color.font_secondary'))
                Button('复制', { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .width('100%')
                  .onClick(async () => {
                    await copyToClipboard(this.resHeaders, this.getUIContext())
                  })
              }
            }.tabBar(SubTabBarStyle.of('响应头'))
          }
          .height('auto')
          .barMode(BarMode.Scrollable)
        }
        .borderRadius(10)
        .padding(10)
        .margin({ bottom: 15 })
        .backgroundColor($r('app.color.setting_block_background'))
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  private async sendRequest() {
    const progress = new CustomDialogController({
      builder: LoadingDialog({
        content: '正在请求：' + this.url
      })
    })
    progress.open()

    const request = http.createHttp()
    const params = encodeURIComponent(
      this.params.filter(it => it.key.length > 0)
        .map(it => `${it.key}=${it.value}`)
        .join('&')
    )
    const paramSuffix = params.length > 0 ? ('?' + params) : ''
    try {
      const header: Object = makeObject(this.headers)
      const requestBody = this.body.length > 0 ? this.body : undefined
      const method = this.method
      const response = await request.request(this.url + paramSuffix, {
        method: method,
        header: header,
        extraData: requestBody,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.timeout
      })
      this.status = response.responseCode.toString()
      this.resHeaders = Object.keys(response.header)
        .map(key => `${key}: ${response.header[key]}`)
        .join('\n')
      this.resBody = response.result as string
    } catch (e) {
      const err = e as BusinessError
      this.status = err.code.toString()
      this.resBody = err.message
    } finally {
      request.destroy()
      progress.close()
    }
  }
}

function makeObject(pairs: KvPair[]): object {
  let dynamicObject: Record<string, string> = {};
  pairs.filter(it => it.key.length > 0)
    .forEach(it => dynamicObject[it.key] = it.value)
  return dynamicObject
}