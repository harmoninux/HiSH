import { SharedFolderController, SharedFolderContent } from '../components/SharedFolderContent';
import appOption from '../model/appOption';

@Entry
@Component
struct SharedFolderPage {
  @StorageProp(appOption.sharedHost) sharedHost?: string = undefined
  @StorageProp(appOption.sharedGuest) sharedGuest?: string = undefined
  controller: SharedFolderController = new SharedFolderController()

  build() {
    Column() {
      if (this.sharedHost) {
        SharedFolderContent({
          host: this.sharedHost,
          guest: this.sharedGuest,
          controller: this.controller
        })
      }
    }
  }

  onBackPress(): boolean | void {
    return this.controller.backToParent()
  }
}