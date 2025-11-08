import { SharedFolderContent } from '../components/SharedFolderContent';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct SharedFolder {
  appContext: common.ApplicationContext = this.getUIContext().getHostContext()?.getApplicationContext()!!

  build() {
    Column() {
      SharedFolderContent({
        host: this.appContext.filesDir + '/share',
        guest: '/mnt/share'
      })
    }
  }
}