import { BlockTitle, LinkItem, SettingBlockStyle } from "./SettingsBase"

interface GuidItem {
  title: string
  subTitle: string
  page: string
}

interface GuidBlock {
  title: string,
  pages: GuidItem[]
}

const blocks: GuidBlock[] = [{
  title: '基本用法',
  pages: [{
    title: 'Linux Shell',
    subTitle: '基本功能介绍',
    page: 'guide/01_Linux_Shell.html'
  }, {
    title: '包管理器',
    subTitle: 'Alpine Linux 包管理器的基本用法',
    page: 'guide/02_APK.html'
  }, {
    title: 'OpenRC',
    subTitle: '使用 OpenRC 进行服务管理',
    page: 'guide/03_OpenRC.html'
  }]
}, {
  title: '管理',
  pages: [{
    title: '模拟器管理',
    subTitle: '管理模拟器实例和配置',
    page: 'guide/04_Emulator.html'
  }, {
    title: '镜像管理',
    subTitle: '添加、导出系统镜像',
    page: 'guide/05_Rootfs.html'
  }, {
    title: '共享文件夹',
    subTitle: '在Linux和设备之间传输文件',
    page: 'guide/06_Shared_Folder.html'
  }]
}, {
  title: '示例',
  pages: [{
    title: 'C/C++',
    subTitle: '在模拟器中使用gcc进行C语言编程',
    page: 'guide/07_C_Cpp.html'
  }, {
    title: 'Docker',
    subTitle: '在模拟器中使用 Docker 运行容器',
    page: 'guide/08_Docker.html'
  }]
}]

@Component
export default struct UserGuide {
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  guideBlocks: GuidBlock[] = [...blocks]
  @Prop toolBar: boolean = true
  @Require openPage: (title: string, url: string) => void

  build() {
    Column() {
      if (this.toolBar) {
        Row() {
          Text('使用指南')
            .fontSize(20)
            .padding({ left: 15 })
          Blank().layoutWeight(1)
        }
        .height(56)
      }
      Scroll() {
        Column() {
          ForEach(this.guideBlocks, (block: GuidBlock) => {
            Column() {
              Column() {
                BlockTitle({ content: '基本用法' })
                Column() {
                  ForEach(block.pages, (pg: GuidItem) => {
                    LinkItem({
                      title: pg.title,
                      subTitle: pg.subTitle,
                      click: () => {
                        this.openPage(pg.title, pg.page)
                      }
                    })
                  }, (pg: GuidItem) => pg.page)
                }
                .attributeModifier(this.blockStyle)
              }
              .margin({ left: 10, right: 10, bottom: 10 })
            }
          }, (it: GuidBlock) => it.title)
        }
      }
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)
      .scrollBarWidth(1)
      .layoutWeight(1)
      .align(Alignment.Top)
    }
  }
}