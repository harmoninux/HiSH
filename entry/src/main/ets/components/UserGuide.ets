import { BlockTitle, LinkItem, SettingBlockStyle } from "./SettingsBase"

interface GuidItem {
  title: string | Resource
  subTitle: string | Resource
  page: string
}

interface GuidBlock {
  title: string | Resource,
  pages: GuidItem[]
}

const blocks: GuidBlock[] = [{
  title: $r('app.string.guide_basic_title'),
  pages: [{
    title: $r('app.string.guide_linux_shell_title'),
    subTitle: $r('app.string.guide_linux_shell_desc'),
    page: 'guide/01_Linux_Shell.html'
  }, {
    title: $r('app.string.guide_pkg_manager_title'),
    subTitle: $r('app.string.guide_pkg_manager_desc'),
    page: 'guide/02_APK.html'
  }, {
    title: $r('app.string.guide_openrc_title'),
    subTitle: $r('app.string.guide_openrc_desc'),
    page: 'guide/03_OpenRC.html'
  }]
}, {
  title: $r('app.string.guide_management_title'),
  pages: [{
    title: $r('app.string.emulator_management_title'),
    subTitle: $r('app.string.guide_emulator_mgmt_desc'),
    page: 'guide/04_Emulator.html'
  }, {
    title: $r('app.string.image_management_title'),
    subTitle: $r('app.string.guide_image_mgmt_desc'),
    page: 'guide/05_Rootfs.html'
  }, {
    title: $r('app.string.guide_shared_folder_title'),
    subTitle: $r('app.string.guide_shared_folder_desc'),
    page: 'guide/06_Shared_Folder.html'
  }]
}, {
  title: $r('app.string.guide_examples_title'),
  pages: [{
    title: $r('app.string.guide_c_cpp_title'),
    subTitle: $r('app.string.guide_c_cpp_desc'),
    page: 'guide/07_C_Cpp.html'
  }, {
    title: $r('app.string.guide_docker_title'),
    subTitle: $r('app.string.guide_docker_desc'),
    page: 'guide/08_Docker.html'
  }]
}]

@Component
export default struct UserGuide {
  blockStyle: SettingBlockStyle = new SettingBlockStyle()
  guideBlocks: GuidBlock[] = [...blocks]
  @Require openPage: (title: string | Resource, url: string) => void

  build() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.guideBlocks, (block: GuidBlock, index: number) => {
            Column() {
              Column() {
                BlockTitle({ content: block.title })
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
          }, (it: GuidBlock, index: number) => index.toString())
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