@Component
export struct RepeatGrid {
  @Prop items: object[] = []
  @Prop specifiedBreak?: string = undefined
  @Require @BuilderParam contentBuilder: (item: object, index: number) => void
  @Require getKey: (item: object, index: number) => string
  @State private gridMargin: number = 24

  build() {
    GridRow({ gutter: 24 }) {
      ForEach(this.items, (item: object, index: number) => {
        GridCol({ span: this.span() }) {
          Column() {
            this.contentBuilder(item, index)
          }
        }
      }, (item: object, index: number) => this.getKey(item, index))
    }
    .margin({ left: this.gridMargin, right: this.gridMargin })
    .onBreakpointChange((breakpoint: string) => {
      const br = this.specifiedBreak || breakpoint
      if (br === 'lg') {
        this.gridMargin = 48
      } else if (br === 'md') {
        this.gridMargin = 32
      } else if (br === 'xs') {
        this.gridMargin = 18
      } else {
        this.gridMargin = 24
      }
    })
  }

  private span(): GridColColumnOption {
    const s: GridColColumnOption = {
      xs: 16,
      sm: 12,
      md: 6,
      lg: 6
    }
    if (this.specifiedBreak !== undefined) {
      return s[this.specifiedBreak]
    } else {
      return s
    }
  }
}