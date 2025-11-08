@Component
export struct RepeatGrid {
  @State @Require items: object[] = []
  @Require @BuilderParam contentBuilder: (item: object, index: number) => void
  @Require getKey: (item: object, index: number) => string
  @State private gridMargin: number = 24

  build() {
    GridRow({ gutter: 24 }) {
      ForEach(this.items, (item: object, index: number) => {
        GridCol({ span: { sm: 12, md: 6, lg: 6 } }) {
          Column() {
            this.contentBuilder(item, index)
          }
        }
      }, (item: object, index: number) => this.getKey(item, index))
    }
    .margin({ left: this.gridMargin, right: this.gridMargin })
    .onBreakpointChange((breakpoint: string) => {
      if (breakpoint === 'lg') {
        this.gridMargin = 48
      } else if (breakpoint === 'md') {
        this.gridMargin = 32
      } else {
        this.gridMargin = 24
      }
    })
  }
}