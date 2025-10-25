import { common } from "@kit.AbilityKit"
import { picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit'
import { LoadingDialog } from "@kit.ArkUI";

enum Type {
  Folder = 0,
  File = 1,
  Unknown = 2
}

interface Entry {
  name: string
  type: Type
  size: number
  mtime: number
  detail: string
}

@Component
export struct SharedFolderContent {
  @Require @Prop host: string
  @Require @Prop guest: string
  @State files: Entry[] = []
  @State current: string[] = []
  importProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.importing_file_to_shared_folder'),
    }),
  })
  exportProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: $r('app.string.exporting_file_to_shared_folder'),
    }),
  })

  async aboutToAppear() {
    this.current = [this.host];
    await this.refreshFileList();
  }

  build() {
    Column() {
      // 路径栏增强
      Row() {
        SymbolGlyph($r('sys.symbol.externaldrive_fill'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .margin({ left: 4 })

        Text([this.guest, ...this.current.slice(1)].join('/'))
          .fontSize(16)
          .padding({ left: 4, right: 8 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding(4)
          .margin({ right: 5 })
          .onClick(() => this.refreshFileList())

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding(4)
          .margin({ right: 5 })
          .onClick(() => this.importFileToCurrent())
      }
      .margin({ top: 5 })

      // 文件列表区域
      List() {
        if (this.current.length > 1) {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
                .fontSize(24)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 4 })

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
                .fontSize(24)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })

              Column() {
                Text(item.name)
                  .fontSize(16)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .ellipsisMode(EllipsisMode.END)
                  .maxLines(1)
                Text(item.detail)
                  .fontSize(11)
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (item.type === Type.File) {
                SymbolGlyph($r('sys.symbol.save'))
                  .fontSize(24)
                  .fontColor([$r('sys.color.icon_secondary')])
                  .margin({ right: 8 })
                  .onClick(() => this.saveFile(item.name))
              }
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
      .margin({ left: 8, right: 4, bottom: 8 })
      .scrollBarWidth(1)
    }
    .margin({ left: 5, right: 5 })
  }

  private async saveFile(name: string) {

    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    const options = new picker.DocumentSaveOptions()
    options.newFileNames = [name];

    const savePicker = new picker.DocumentViewPicker(context)
    const uris = await savePicker.save(options)

    if (uris.length == 0) {
      return
    }

    const srcPath = [...this.current, decodeURI(name)].join('/')
    const destUri = uris[0]
    this.exportProgress.open()
    try {
      await copyFile(srcPath, destUri);
    } catch (e) {
      console.log('error copy file', srcPath, destUri, e)
    } finally {
      this.exportProgress.close()
    }
  }

  async importFileToCurrent() {
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext;

    let options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;

    let documentPicker = new picker.DocumentViewPicker(context);
    let uris = await documentPicker.select(options);

    if (uris.length == 0) {
      return
    }

    const srcUri = uris[0]
    const destPath = [...this.current, decodeURI(srcUri.split('/').reverse()[0])].join('/')

    this.importProgress.open()
    try {
      await copyFile(srcUri, destPath);
      this.refreshFileList()
    } catch (e) {
      console.log('error copy file', srcUri, destPath, e)
    } finally {
      this.importProgress.close()
    }
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
        const e = {
          name: it,
          type,
          size: stat.size,
          mtime: stat.mtime
        } as Entry;
        e.detail = formatDetail(e)
        return e
      })
      .sort((a, b) => comparator(a, b));
  }
}

function formatSize(entry: Entry) {
  let size: string;
  if (entry.size > 1024 * 1024 * 1024) {
    size = (entry.size / 1024 * 1024 * 1024).toFixed(1) + 'GB';
  } else if (entry.size > 1024 * 1024) {
    size = (entry.size / 1024 * 1024).toFixed(1) + 'MB';
  } else if (entry.size > 1024) {
    size = (entry.size / 1024).toFixed(1) + 'KB';
  } else {
    size = entry.size.toString() + 'B';
  }
  return size;
}

function comparator(a: Entry, b: Entry): number {
  const ka = a.type + '-' + a.name;
  const kb = b.type + '-' + b.name;
  return ka.localeCompare(kb)
}

function formatTimestamp(timestamp: number) {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');
  const seconds = String(date.getSeconds()).padStart(2, '0');
  return `${year}/${month}/${day} ${hours}:${minutes}:${seconds}`;
}

function formatDetail(entry: Entry): string {
  try {
    let size: string = formatSize(entry);
    let mtime = formatTimestamp(entry.mtime * 1000)
    return `${mtime} - ${size}`
  } catch (e) {
    return '--'
  }
}

async function copyFile(srcPathOrUri: string, destPathOrUri: string) {

  const srcFile = await fs.open(srcPathOrUri, fs.OpenMode.READ_ONLY);
  const destFile = await fs.open(destPathOrUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

  await fs.copyFile(srcFile.fd, destFile.fd)

  await fs.close(srcFile.fd);
  await fs.close(destFile.fd);
}
