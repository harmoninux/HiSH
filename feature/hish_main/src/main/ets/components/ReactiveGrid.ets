@Component
export default struct ReactiveGrid {
  @Require @BuilderParam contentBuilder: () => void
  @State private gridMargin: number = 24
  @Prop specifiedBreak?: string = undefined

  build() {
    Row() {
      GridRow({ columns: this.columns(), gutter: 24 }) {
        GridCol({ span: this.span(), offset: this.getOffset() }) {
          this.contentBuilder()
        }
      }
      .margin({ left: this.gridMargin, right: this.gridMargin })
      .onBreakpointChange((breakpoint: string) => {
        breakpoint = this.specifiedBreak || breakpoint
        if (breakpoint === 'lg') {
          this.gridMargin = 48
        } else if (breakpoint === 'md') {
          this.gridMargin = 32
        } else if (breakpoint === 'xs') {
          this.gridMargin = 16
        } else {
          this.gridMargin = 24
        }
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  private getOffset(): number | GridColColumnOption {
    if (this.specifiedBreak === 'xs') {
      return 1
    }
    return { md: 1, lg: 2 }
  }

  private span(): number | GridColColumnOption {
    if (this.specifiedBreak === 'xs') {
      return 2
    }
    return { sm: 4, md: 6, lg: 8 }
  }

  private columns(): number | GridRowColumnOption {
    if (this.specifiedBreak === 'xs') {
      return 2
    }
    return { sm: 4, md: 8, lg: 12 }
  }
}
