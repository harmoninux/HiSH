import { Emulator } from "../model/Emulator"
import ReactiveGrid from "./ReactiveGrid"
import { RepeatGrid } from "./RepeatGrid"

@Component
export default struct EditEmulatorContent {
  @Require emulator: Emulator

  @Builder
  buildEmulatorEdit() {
    Column() {
      TextInput({ placeholder: '名称', text: this.emulator.name })
        .margin(5)
    }
    .margin(5)
    .width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('编辑模拟器')
          .fontSize(16)
          .padding({ left: 15 })

        Blank().layoutWeight(1)

        Button('完成', { buttonStyle: ButtonStyleMode.TEXTUAL })
      }
      .height(56)

      Scroll() {
        ReactiveGrid({
          contentBuilder: () => {
            this.buildEmulatorEdit()
          }
        })
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }
}
