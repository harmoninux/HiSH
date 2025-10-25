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
    const appCtx = (this.getUIContext().getHostContext() as common.UIAbilityContext).getApplicationContext()
    this.current = [appCtx.filesDir + '/share']
    await this.refreshFileList();
  }

  build() {
    Column() {
      // 路径栏增强
      Row() {
        Text(['/mnt/share', ...this.current.slice(1)].join('/'))
          .fontSize(16)
          .padding({ left: 8, right: 8, bottom: 8 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(20)
          .fontColor([$r('sys.color.icon_secondary')])
          .margin({ right: 4 })
          .onClick(() => this.importFileToCurrent())
      }

      // 文件列表区域
      List() {
        if (this.current.length > 1) {
          ListItem() {
            Row() {
              SymbolGlyph($r('sys.symbol.arrowshape_turn_up_left'))
                .fontSize(20)
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
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })

              Text(item.name)
                .fontSize(16)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .ellipsisMode(EllipsisMode.END)
                .maxLines(1)
                .layoutWeight(1)

              if (item.type === Type.File) {
                SymbolGlyph($r('sys.symbol.save'))
                  .fontSize(20)
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
    .width('100%')
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
        return { name: it, type } as Entry;
      })
      .sort((a, b) => comparator(a, b));
  }
}

async function copyFile(srcPathOrUri: string, destPathOrUri: string) {

  const srcFile = await fs.open(srcPathOrUri, fs.OpenMode.READ_ONLY);
  const destFile = await fs.open(destPathOrUri, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);

  await fs.copyFile(srcFile.fd, destFile.fd)

  await fs.close(srcFile.fd);
  await fs.close(destFile.fd);
}
