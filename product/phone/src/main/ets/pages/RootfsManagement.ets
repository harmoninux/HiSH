import { RootfsManagement as Page } from 'hish_main';

@Entry
@Component
struct Wrapper {
  build() {
    Column() {
      Page()
    }.width('100%').height('100%')
  }
}
