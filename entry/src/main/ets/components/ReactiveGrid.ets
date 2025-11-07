@Component
export default struct ReactiveGrid {
  @Require @BuilderParam contentBuilder: () => void
  @State private gridMargin: number = 24

  build() {
    Row() {
      GridRow({ columns: { sm: 4, md: 8, lg: 12 }, gutter: 24 }) {
        GridCol({ span: { sm: 4, md: 6, lg: 8 }, offset: { md: 1, lg: 2 } }) {
          this.contentBuilder()
        }
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
    .alignItems(VerticalAlign.Center)
  }
}
