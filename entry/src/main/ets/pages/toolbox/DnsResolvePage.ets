import { DnsResolveContent } from '../../components/toolbox/DnsResolveContent'
import { ComposeTitleBar } from '@kit.ArkUI'

@Entry
@Component
struct DnsResolvePage {
  build() {
    Column() {
      ComposeTitleBar({
        title: 'DNS解析'
      })
      DnsResolveContent()
    }
  }
}