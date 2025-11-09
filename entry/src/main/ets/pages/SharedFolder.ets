import { Controller, SharedFolderContent } from '../components/SharedFolderContent';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct SharedFolder {
  appContext: common.ApplicationContext = this.getUIContext().getHostContext()?.getApplicationContext()!!
  controller: Controller = new Controller()

  build() {
    Column() {
      SharedFolderContent({
        host: this.appContext.filesDir + '/share',
        guest: '/mnt/share',
        controller: this.controller
      })
    }
  }

  onBackPress(): boolean | void {
    return this.controller.backToParent()
  }
}