import { BusinessError } from '@kit.BasicServicesKit';
import { Want, common, wantConstant } from "@kit.AbilityKit"
import { fileUri, picker } from '@kit.CoreFileKit';
import { fileIo as fs } from '@kit.CoreFileKit'
import { CustomContentDialog, LoadingDialog, PromptAction } from "@kit.ArkUI";
import { pasteboard } from '@kit.BasicServicesKit'
import validateFolderName from '../lib/validateFolderName'
import { util } from "@kit.ArkTS";
import copyFile from '../lib/copyFile';
import deleteDirectoryRecursive from '../lib/deleteDirectoryRecursive';
import { hilog } from '@kit.PerformanceAnalysisKit';

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


type PasteAction = 'copy' | 'move'

interface PasteContent {
  action: PasteAction
  dir: string
  name: string
  type: Type
}

@Component
export struct SharedFolderContent {
  @Require @Prop host: string
  @Require @Prop guest: string
  @State files: Entry[] = []
  @State current: string[] = []
  @State tempFolderName: string = ''
  @State tempClipboard?: PasteContent = undefined
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
  deletingProgress: CustomDialogController = new CustomDialogController({
    builder: LoadingDialog({
      content: '正在删除',
    }),
  })
  createFolderController = new CustomDialogController({
    builder: CustomContentDialog({
      primaryTitle: $r('app.string.create_folder'),
      contentBuilder: () => {
        this.buildNewFolderContent()
      }
    })
  })
  scroller: Scroller = new ListScroller()
  private uiContext: UIContext = this.getUIContext();
  private promptAction: PromptAction = this.uiContext.getPromptAction();

  async aboutToAppear() {
    this.current = [this.host];
    await this.refreshFileList();
  }

  @Builder
  buildNewFolderContent() {
    Column() {
      TextInput({
        text: this.tempFolderName,
        placeholder: $r('app.string.input_folder_name')
      })
        .onChange((value) => {
          this.tempFolderName = value;
        })
      Button($r('app.string.SettingComplete_label'))
        .margin({ top: 10 })
        .width('100%')
        .enabled(validateFolderName(this.tempFolderName))
        .onClick(async () => {
          await this.createFolderToCurrent()
        })
    }
  }

  @Builder
  buildFileList() {
    List({ scroller: this.scroller }) {
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
          .height(56)
          .width('100%')
          .clickEffect({ level: ClickEffectLevel.MIDDLE })
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
              SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
                .fontSize(24)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
                .bindMenu([{
                  value: $r('app.string.open_file'),
                  action: () => this.openFile(item.name)
                }, {
                  value: $r('app.string.export_file_from_shared_folder'),
                  action: () => this.saveFile(item.name)
                }, {
                  value: $r('app.string.copy_guest_path'),
                  action: () => this.copyGuestPath(item.name)
                }, {
                  value: $r('app.string.delete_this'),
                  action: () => this.askForDeleteCurrent(item)
                }, {
                  value: $r('app.string.copy_this'),
                  action: () => this.prepareToCopy(item)
                }, {
                  value: $r('app.string.move_this'),
                  action: () => this.prepareToMove(item)
                }])
            } else if (item.type == Type.Folder) {
              SymbolGlyph($r('sys.symbol.dot_grid_1x2'))
                .fontSize(24)
                .fontColor([$r('sys.color.icon_secondary')])
                .margin({ right: 8 })
                .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
                .bindMenu([{
                  value: $r('app.string.copy_guest_path'),
                  action: () => this.copyGuestPath(item.name)
                }, {
                  value: $r('app.string.delete_this'),
                  action: () => this.askForDeleteCurrent(item)
                }, {
                  value: $r('app.string.copy_this'),
                  action: () => this.prepareToCopy(item)
                }, {
                  value: $r('app.string.move_this'),
                  action: () => this.prepareToMove(item)
                }])
            }
          }
          .height(56)
          .width('100%')
          .clickEffect({ level: ClickEffectLevel.MIDDLE })
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

  prepareToMove(item: Entry): void {
    this.tempClipboard = {
      action: 'move',
      dir: this.current.join('/'),
      name: item.name,
      type: item.type
    }
  }

  prepareToCopy(item: Entry): void {
    this.tempClipboard = {
      action: 'copy',
      dir: this.current.join('/'),
      name: item.name,
      type: item.type
    }
  }

  async askForDeleteCurrent(item: Entry): Promise<void> {

    this.getUIContext().showAlertDialog({
      title: '确定删除',
      message: '您正在操作删除文件，删除后不可恢复，确定删除？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      buttons: [
        {
          value: $r('app.string.setting_generic_cancel'),
          action: () => {
          }
        },
        {
          enabled: true,
          style: DialogButtonStyle.HIGHLIGHT,
          backgroundColor: $r('sys.color.warning'),
          value: $r('app.string.confirm_remove'),
          action: async () => {
            await this.deleteCurrent(item);
          }
        }
      ],
    });
  }

  async deleteCurrent(item: Entry) {
    const hostPath = [this.current, item.name].join('/')
    this.deletingProgress.open()
    try {
      if (item.type === Type.File) {
        fs.unlinkSync(hostPath)
      } else {
        await deleteDirectoryRecursive(hostPath)
      }
    } catch (e) {
      hilog.info(1, "SharedFolderContent", "failed to delete %{public}s", hostPath)
    } finally {
      this.deletingProgress.close()
      this.refreshFileList()
    }
  }

  openFile(name: string): void {
    const srcPath = [...this.current, decodeURI(name)].join('/')
    const uri = fileUri.getUriFromPath(srcPath)
    let want: Want = {
      action: 'ohos.want.action.viewData',
      uri: uri,
      flags: wantConstant.Flags.FLAG_AUTH_WRITE_URI_PERMISSION
    }
    let context = this.getUIContext().getHostContext() as common.UIAbilityContext
    context.startAbility(want)
      .then(() => {
        console.info('Succeed to invoke startAbility.');
      })
      .catch((err: BusinessError) => {
        console.error(`Failed to invoke startAbility, code: ${err.code}, message: ${err.message}`);
      });
  }

  async copyGuestPath(name: string): Promise<void> {
    const guest = [this.guest, ...this.current.slice(1), name].join('/')
    try {
      const board = pasteboard.getSystemPasteboard()
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, guest)
      await board.setData(pasteData)

      const promptFormat = this.uiContext
        .getHostContext()?.resourceManager.getStringByNameSync('guest_path_copied_prompt')
      const prompt = util.format(promptFormat, guest)
      this.promptAction.showToast({
        message: prompt,
        duration: 4000
      })
    } catch (e) {
      console.log('error copy to clipboard ' + guest, e)
    }
  }

  build() {
    Column() {
      // 路径栏增强
      Row() {
        SymbolGlyph($r('sys.symbol.externaldrive_fill'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .margin({ left: 4 })

        Text(this.getGuestPath())
          .fontSize(16)
          .padding({ left: 4, right: 8 })
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.END)
          .maxLines(1)
          .layoutWeight(1)

        if (this.tempClipboard) {
          Button($r('app.string.paste_here'), { buttonStyle: ButtonStyleMode.TEXTUAL })
            .onClick(() => this.onPasteToHere())
        }

        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding(4)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .margin({ right: 5 })
          .onClick(() => this.refreshFileList())

        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(24)
          .fontColor([$r('sys.color.icon_secondary')])
          .padding(4)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.8 })
          .margin({ right: 5 })
          .bindMenu([{
            value: $r('app.string.create_folder'),
            action: () => {
              this.tempFolderName = ''
              this.createFolderController.open()
            }
          }, {
            value: $r('app.string.import_file_to_shared_folder'),
            action: () => {
              this.importFileToCurrent()
            }
          }])
      }
      .height(56)

      // 文件列表区域
      if (this.current.length === 1 && this.files.length === 0) {
        Column() {
          Text($r('app.string.empty_shared_folder_prompt'))
            .textAlign(TextAlign.Center)
            .fontColor($r('sys.color.icon_secondary'))
            .fontSize($r('sys.float.Body_M'))
            .height('100%')
        }
        .layoutWeight(1)
      } else {
        this.buildFileList()
      }
    }
    .margin({ left: 5, right: 5 })
  }

  async onPasteToHere(): Promise<void> {

    const board = this.tempClipboard!!
    this.tempClipboard = undefined

    const dir = this.current.join('/')
    if (board.dir === dir) {
      this.getUIContext().getPromptAction().showToast({
        message: '不能粘贴到同一个位置',
        duration: 3000
      })
    } else {
      const target = [...this.current, board.name].join('/')
      if (fs.accessSync(target, fs.AccessModeType.EXIST)) {
        this.getUIContext().getPromptAction().showToast({
          message: '目标文件已存在',
          duration: 3000
        })
      } else {

        const title = board.action === 'move' ? '正在移动' : '正在复制'
        const progress = new CustomDialogController({
          builder: LoadingDialog({
            content: title,
          })
        })
        progress.open()

        const src = [board.dir, board.name].join('/')
        try {
          if (board.action === 'move') {
            fs.renameSync(src, target)
          } else if (board.action === 'copy') {
            if (board.type === Type.Folder) {
              const to: string = [...this.current].join('/');
              await fs.copyDir(src, to)
            } else if (board.type === Type.File) {
              await fs.copyFile(src, target)
            }
          }
        } catch (e) {
          hilog.info(1, 'SharedFolderContent', 'failed to execute paste action %{public}s', e)
        } finally {
          progress.close()
          this.refreshFileList()
        }
      }
    }
  }

  private getGuestPath() {
    let parts = [this.guest, ...this.current.slice(1)];
    let path = parts.join('/');
    if (path.startsWith('//')) {
      return path.substring(1)
    } else {
      return path
    }
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

  async createFolderToCurrent() {
    const name = this.tempFolderName
    const destPath = [...this.current, name].join('/')
    try {
      fs.mkdirSync(destPath)
    } catch (e) {
      console.log('error creating folder ' + destPath, e)
    }
    this.tempFolderName = ''
    this.createFolderController.close()
    this.refreshFileList()
  }

  private async openFileEntry(e: Entry) {
    if (e.type === Type.Folder) {
      this.current.push(e.name)
      await this.refreshFileList()
    } else if (e.type == Type.File) {
      this.openFile(e.name)
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
    this.scroller.scrollTo({ yOffset: 0, xOffset: 0 })
  }
}

function formatSize(entry: Entry) {
  let size: string;
  if (entry.size > 1024 * 1024 * 1024) {
    size = (entry.size / 1024 / 1024 / 1024).toFixed(1) + 'GB';
  } else if (entry.size > 1024 * 1024) {
    size = (entry.size / 1024 / 1024).toFixed(1) + 'MB';
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
