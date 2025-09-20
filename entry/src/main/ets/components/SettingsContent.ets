import { LinkItem } from "./LinkItem"

@Component
export default struct SettingsContent {
  build() {
    Scroll() {
      Column() {

        Text('HiSH v0.0.1')
          .fontSize(12)
          .fontColor('#cccccc')
          .padding({ top: 60, bottom: 20 })
      }
    }
    .scrollable(ScrollDirection.Vertical)
    .scrollBar(BarState.Auto)
    .scrollBarWidth(1)
  }
}