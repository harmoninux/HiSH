import { Index as MainPage } from 'hish_main';

@Entry
@Component
struct Index {
  build() {
    Column() {
      MainPage()
    }.width('100%').height('100%')
  }
}
