import { common } from "@kit.AbilityKit"
import { fileIo as fs } from '@kit.CoreFileKit'

enum Type {
  Folder = 0,
  File = 1,
  Unknown = 2
}

interface Entry {
  name: string
  type: Type
}

function comparator(a: Entry, b: Entry): number {
  const ka = a.type + '-' + a.name;
  const kb = b.type + '-' + b.name;
  return ka.localeCompare(kb)
}

@Component
export struct SharedFolderContent {
  @State files: Entry[] = []
  @State current: string[] = []

  async aboutToAppear() {
    const appCtx = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext()
    this.current = [appCtx.filesDir + '/share']
    await this.refreshFileList();
  }

  build() {
    Column() {
      // 路径栏增强
      Text(['/mnt/host', ...this.current.slice(1)].join('/'))
        .fontSize(16)
        .padding({ left: 8, right: 8, bottom: 8 })
        .width('100%')

      // 文件列表区域
      List() {
        if (this.current.length > 1) {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })

              Text('..')
                .fontSize(16)
            }
            .height(48)
            .width('100%')
            .onClick(() => this.backToParent())
          }
        }

        ForEach(this.files, (item: Entry) => {
          ListItem() {
            Row() {
              SymbolGlyph(item.type === Type.Folder ?
                $r('sys.symbol.folder_fill') : $r('sys.symbol.doc'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })

              Text(item.name)
                .fontSize(16)
            }
            .height(48)
            .width('100%')
            .onClick(() => this.openFileEntry(item))
          }
        }, (item: Entry) => item.name)
      }
      .divider({
        strokeWidth: 0.1,
        color: $r('sys.color.icon_secondary'),
        startMargin: 5,
        endMargin: 5
      })
      .layoutWeight(1)
      .borderRadius(12)
      .margin({ left: 8, right: 8, bottom: 8 })

      // Column() {
      //   Button('Add New')
      //     .width('60%')
      // }
      // .width('100%')
    }
    .width('100%')
  }

  private async openFileEntry(e: Entry) {
    if (e.type === Type.Folder) {
      this.current.push(e.name)
      await this.refreshFileList()
    }
  }

  private async backToParent() {
    this.current.splice(this.current.length - 1, 1)
    this.refreshFileList()
  }

  private async refreshFileList() {
    const dir = this.current.join('/');
    const names = await fs.listFile(dir);
    this.files = names
      .filter(it => {
        return it !== '.virtfs_metadata' && it !== '.virtfs_metadata_root'
      })
      .map((it) => {
        const full = dir + '/' + it;
        const stat = fs.statSync(full);
        let type: Type;
        if (stat.isDirectory()) {
          type = Type.Folder
        } else if (stat.isFile()) {
          type = Type.File
        } else {
          type = Type.Unknown
        }
        return { name: it, type } as Entry;
      })
      .sort((a, b) => comparator(a, b));
  }
}