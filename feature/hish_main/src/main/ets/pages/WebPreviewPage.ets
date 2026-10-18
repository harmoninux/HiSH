import { webview } from '@kit.ArkWeb'
import { BackButton } from '../components/BackButton'
import appOption from '../model/appOption'
import { Emulator } from '../model/Emulator'
import { normalizeWebPreviewUrl } from '../lib/webPreviewUrl'

@Component
export struct WebPreviewPage {
  @Require controller: webview.WebviewController
  @State address: string = ''
  @State errorMessage: string = ''
  @State loading: boolean = false
  @State hasAddress: boolean = false
  private initialNavigation: boolean = true

  private openAddress(input: string) {
    const address = normalizeWebPreviewUrl(input)
    if (!address) {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.web_preview_invalid_url') })
      return
    }
    try {
      this.errorMessage = ''
      this.address = address
      this.controller.loadUrl(address)
      this.hasAddress = true
    } catch (_) {
      this.errorMessage = this.getUIContext().getHostContext()!!.resourceManager
        .getStringByNameSync('web_preview_load_failed')
    }
  }

  private mappedPorts(): MenuElement[] {
    const currentId = AppStorage.get<string>(appOption.currentRunningEmulator)
    const emulators = AppStorage.get<Emulator[]>(appOption.emulators) ?? []
    const skipped = AppStorage.get<number[]>(appOption.portUsedByOthers) ?? []
    const current = emulators.find(item => item.id === currentId)
    if (!current) {
      return []
    }
    return current.portMapping
      .filter(item => item.host !== undefined && item.host >= 1 && item.host <= 65535 &&
        !skipped.includes(item.host))
      .map(item => ({
        value: `127.0.0.1:${item.host} → ${item.guest}`,
        action: () => this.openAddress(`http://127.0.0.1:${item.host}`)
      } as MenuElement))
  }

  build() {
    Column() {
      Row() {
        BackButton()
        Text($r('app.string.web_preview_title')).fontSize($r('sys.float.Title_S'))
        Button($r('app.string.web_preview_ports'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .margin({ left: 8 })
          .bindMenu(this.mappedPorts())
          .enabled(this.mappedPorts().length > 0)
        Blank()
      }.padding(8).width('100%')
      Row() {
        TextInput({ text: this.address, placeholder: 'http://127.0.0.1:8000' })
          .layoutWeight(1)
          .enterKeyType(EnterKeyType.Go)
          .onChange(value => this.address = value)
          .onSubmit(() => this.openAddress(this.address))
        Button($r('app.string.web_preview_open'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .onClick(() => this.openAddress(this.address))
        Button($r('app.string.web_preview_refresh'), { buttonStyle: ButtonStyleMode.TEXTUAL })
          .enabled(this.hasAddress)
          .onClick(() => {
            this.errorMessage = ''
            this.controller.refresh()
          })
      }.padding({ left: 8, right: 8 }).width('100%')
      if (!this.hasAddress) {
        Text($r('app.string.web_preview_help')).padding(12).width('100%')
      }
      if (this.loading) {
        LoadingProgress().width(24).height(24)
      }
      if (this.errorMessage) {
        Text(this.errorMessage).padding(12).fontColor($r('sys.color.alert')).width('100%')
      }
      Web({ src: 'about:blank', controller: this.controller })
        .layoutWeight(1)
        .width('100%')
        .onOverrideUrlLoading(request => {
          const address = request.getRequestUrl()
          return address !== 'about:blank' && normalizeWebPreviewUrl(address) === undefined
        })
        .onPageBegin(event => {
          if (event && event.url !== 'about:blank') {
            this.loading = true
            this.address = event.url
          }
        })
        .onPageEnd(event => {
          this.loading = false
          if (event && event.url !== 'about:blank' && this.initialNavigation) {
            // The initial placeholder must not become a blank history entry.
            this.controller.clearHistory()
            this.initialNavigation = false
          }
        })
        .onErrorReceive(event => {
          if (event && event.request.isMainFrame()) {
            this.loading = false
            this.errorMessage = this.getUIContext().getHostContext()!!.resourceManager
              .getStringByNameSync('web_preview_load_failed')
          }
        })
    }.width('100%').height('100%')
  }
}
