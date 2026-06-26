import { Snippet, DEFAULT_SNIPPETS } from '../model/Emulator'

/**
 * Snippets 命令面板
 * 半屏弹出面板，显示常用命令，点击发送到终端
 * 支持编辑模式：添加/编辑/删除命令
 */
@Component
export struct SnippetsPanel {
  @Prop snippets: Snippet[] = []
  @Prop showPanel: boolean = false
  @State searchText: string = ''
  @State isEditMode: boolean = false
  @State editingSnippet: Snippet | null = null
  @State showEditDialog: boolean = false
  @State editLabel: string = ''
  @State editCommand: string = ''
  onSend: (command: string) => void = () => {}
  onDismiss: () => void = () => {}
  onToggleStar: (id: string) => void = () => {}
  onAdd: (label: string, command: string) => void = () => {}
  onEdit: (id: string, label: string, command: string) => void = () => {}
  onDelete: (id: string) => void = () => {}

  getFilteredSnippets(): Snippet[] {
    let list = this.snippets
      .filter(s => !this.searchText ||
        s.label.toLowerCase().includes(this.searchText.toLowerCase()) ||
        s.command.toLowerCase().includes(this.searchText.toLowerCase()))
    list.sort((a, b) => {
      if (a.starred !== b.starred) return a.starred ? -1 : 1
      return a.sortOrder - b.sortOrder
    })
    return list
  }

  openAddDialog(): void {
    this.editingSnippet = null
    this.editLabel = ''
    this.editCommand = ''
    this.showEditDialog = true
  }

  openEditDialog(snippet: Snippet): void {
    this.editingSnippet = snippet
    this.editLabel = snippet.label
    this.editCommand = snippet.command.replace(/\n$/, '')
    this.showEditDialog = true
  }

  saveEdit(): void {
    if (!this.editLabel.trim() || !this.editCommand.trim()) return
    if (this.editingSnippet) {
      this.onEdit(this.editingSnippet.id, this.editLabel.trim(), this.editCommand.trim() + '\n')
    } else {
      this.onAdd(this.editLabel.trim(), this.editCommand.trim() + '\n')
    }
    this.showEditDialog = false
  }

  build() {
    if (this.showPanel) {
      Stack({ alignContent: Alignment.Center }) {
        Column() {
          // 下拉把手
          Row() {
            Column()
              .width(40)
              .height(4)
              .borderRadius(2)
              .backgroundColor('#555555')
          }
          .width('100%')
          .height(20)
          .justifyContent(FlexAlign.Center)
          .gesture(
            PanGesture({ direction: PanDirection.Down })
              .onActionEnd(() => {
                this.searchText = ''
                this.isEditMode = false
                this.onDismiss()
              })
          )

          // 标题栏
          Row() {
            Text(this.isEditMode ? '📋 编辑命令' : '📋 命令面板')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#ffffff')
            Blank()
            // 编辑/完成按钮
            Button(this.isEditMode ? '完成' : '编辑')
              .fontSize(13)
              .fontColor(this.isEditMode ? '#4FC3F7' : '#aaaaaa')
              .backgroundColor('#333333')
              .height(30)
              .padding({ left: 12, right: 12 })
              .borderRadius(15)
              .onClick(() => {
                this.isEditMode = !this.isEditMode
              })
            // 关闭按钮
            Button('✕')
              .fontSize(18)
              .fontColor('#aaaaaa')
              .backgroundColor('#333333')
              .width(34)
              .height(34)
              .borderRadius(17)
              .margin({ left: 8 })
              .onClick(() => {
                this.searchText = ''
                this.isEditMode = false
                this.onDismiss()
              })
          }
          .width('100%')
          .padding({ left: 16, right: 12, top: 4, bottom: 8 })

          // 搜索框
          Row() {
            Text('🔍')
              .fontSize(14)
              .margin({ right: 8 })
            TextInput({ placeholder: '搜索命令...' })
              .layoutWeight(1)
              .fontSize(14)
              .fontColor('#ffffff')
              .placeholderColor('#666666')
              .backgroundColor(Color.Transparent)
              .onChange((value: string) => {
                this.searchText = value
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor('#1a1a2e')
          .borderRadius(8)
          .margin({ left: 16, right: 16, bottom: 8 })

          // 命令列表
          List() {
            ForEach(this.getFilteredSnippets(), (item: Snippet) => {
              ListItem() {
                Row() {
                  if (this.isEditMode) {
                    // 编辑模式：删除按钮
                    Button('✕')
                      .fontSize(12)
                      .fontColor('#ff5555')
                      .backgroundColor('#331111')
                      .width(28)
                      .height(28)
                      .borderRadius(14)
                      .onClick(() => {
                        this.onDelete(item.id)
                      })
                      .margin({ right: 8 })
                  } else {
                    // 正常模式：收藏图标
                    Text(item.starred ? '⭐' : '☆')
                      .fontSize(16)
                      .width(28)
                      .onClick(() => {
                        this.onToggleStar(item.id)
                      })
                  }

                  // 命令内容
                  Column() {
                    Text(item.label)
                      .fontSize(14)
                      .fontColor('#ffffff')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(item.command.replace(/\n/g, ''))
                      .fontSize(11)
                      .fontColor('#888888')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 2 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  .margin({ left: 8 })

                  // 编辑模式：编辑按钮
                  if (this.isEditMode) {
                    Button('✎')
                      .fontSize(14)
                      .fontColor('#4FC3F7')
                      .backgroundColor('#112233')
                      .width(28)
                      .height(28)
                      .borderRadius(14)
                      .onClick(() => {
                        this.openEditDialog(item)
                      })
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .onClick(() => {
                  if (this.isEditMode) {
                    this.openEditDialog(item)
                  } else {
                    this.onSend(item.command)
                    this.searchText = ''
                    this.onDismiss()
                  }
                })
              }
            }, (item: Snippet) => item.id)
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0.5, color: '#333333', startMargin: 48, endMargin: 12 })

          // 底部添加按钮
          Button('+ 添加命令')
            .fontSize(14)
            .fontColor('#4FC3F7')
            .backgroundColor('#112233')
            .width('90%')
            .height(38)
            .borderRadius(19)
            .margin({ top: 8, bottom: 12 })
            .onClick(() => {
              this.openAddDialog()
            })
        }
        .width('100%')
        .height('50%')
        .backgroundColor('#0d0d1a')
        .borderRadius({ topLeft: 16, topRight: 16 })
        .shadow({ radius: 16, color: '#00000088', offsetY: -4 })
        .transition(TransitionEffect.translate({ y: '100%' }).combine(TransitionEffect.OPACITY))
        .animation({ duration: 250, curve: Curve.EaseOut })

        // 编辑对话框
        if (this.showEditDialog) {
          Column() {
            Text(this.editingSnippet ? '编辑命令' : '添加命令')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#ffffff')
              .margin({ bottom: 16 })

            TextInput({ placeholder: '命令名称', text: this.editLabel })
              .fontSize(14)
              .fontColor('#ffffff')
              .placeholderColor('#666666')
              .backgroundColor('#1a1a2e')
              .borderRadius(8)
              .height(40)
              .margin({ bottom: 12 })
              .onChange((value: string) => {
                this.editLabel = value
              })

            TextArea({ placeholder: '命令内容（如 apt update）', text: this.editCommand })
              .fontSize(13)
              .fontColor('#ffffff')
              .placeholderColor('#666666')
              .backgroundColor('#1a1a2e')
              .borderRadius(8)
              .height(80)
              .fontFamily('monospace')
              .margin({ bottom: 16 })
              .onChange((value: string) => {
                this.editCommand = value
              })

            Row() {
              Button('取消')
                .fontSize(14)
                .fontColor('#aaaaaa')
                .backgroundColor('#333333')
                .height(36)
                .layoutWeight(1)
                .margin({ right: 8 })
                .onClick(() => {
                  this.showEditDialog = false
                })
              Button('保存')
                .fontSize(14)
                .fontColor('#ffffff')
                .backgroundColor('#4FC3F7')
                .height(36)
                .layoutWeight(1)
                .margin({ left: 8 })
                .enabled(this.editLabel.trim().length > 0 && this.editCommand.trim().length > 0)
                .onClick(() => {
                  this.saveEdit()
                })
            }
            .width('100%')
          }
          .width('80%')
          .padding(20)
          .backgroundColor('#1a1a2e')
          .borderRadius(16)
          .shadow({ radius: 20, color: '#000000aa', offsetY: 4 })
        }
      }
    }
  }
}
