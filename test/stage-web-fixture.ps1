<# Creates an unsigned, isolated ArkWeb UI fixture. Does not build or install. #>
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$taskRepo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $taskOutput) { throw 'Choose a new output directory.' }
$taskSource = Join-Path $taskRepo 'feature/hish_main/src/main'
function Write-FixtureFile([string]$Path, [string]$Content) {
  $taskTarget = Join-Path $taskOutput $Path
  New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($taskTarget)) | Out-Null
  [IO.File]::WriteAllText($taskTarget, $Content)
}
function Copy-FixtureFile([string]$From, [string]$To) {
  $taskTarget = Join-Path $taskOutput $To
  New-Item -ItemType Directory -Force ([IO.Path]::GetDirectoryName($taskTarget)) | Out-Null
  Copy-Item -LiteralPath $From -Destination $taskTarget
}
Write-FixtureFile 'build-profile.json5' @'
{
  "app": { "signingConfigs": [], "products": [{ "name": "default",
    "targetSdkVersion": "5.0.0(12)", "compatibleSdkVersion": "5.0.0(12)", "runtimeOS": "HarmonyOS" }],
    "buildModeSet": [{ "name": "debug" }, { "name": "release" }] },
  "modules": [{ "name": "entry", "srcPath": "./entry", "targets": [{ "name": "default", "applyToProducts": ["default"] }] }]
}
'@
Write-FixtureFile 'oh-package.json5' '{"modelVersion":"6.1.1","dependencies":{}}'
Write-FixtureFile 'hvigor/hvigor-config.json5' '{"modelVersion":"6.1.1","dependencies":{}}'
Write-FixtureFile 'hvigorfile.ts' "import { appTasks } from '@ohos/hvigor-ohos-plugin'; export default { system: appTasks };"
Write-FixtureFile 'entry/hvigorfile.ts' "import { hapTasks } from '@ohos/hvigor-ohos-plugin'; export default { system: hapTasks };"
Write-FixtureFile 'entry/build-profile.json5' '{"apiType":"stageMode","targets":[{"name":"default"}]}'
Write-FixtureFile 'entry/oh-package.json5' '{"name":"entry","version":"1.0.0","dependencies":{}}'
Write-FixtureFile 'AppScope/app.json5' @'
{"app":{"bundleName":"com.hreyulog.hish.webpreviewtest","vendor":"hreyulog","versionCode":1000002,
"versionName":"1.0.2","icon":"$media:icon","label":"$string:EntryAbility_label"}}
'@
Write-FixtureFile 'entry/src/main/module.json5' @'
{"module":{"name":"entry","type":"entry","mainElement":"EntryAbility","deviceTypes":["phone","tablet"],
"deliveryWithInstall":true,"installationFree":false,"pages":"$profile:main_pages",
"requestPermissions":[{"name":"ohos.permission.INTERNET"}],"abilities":[{"name":"EntryAbility",
"srcEntry":"./ets/entryability/EntryAbility.ets","icon":"$media:icon","label":"$string:EntryAbility_label",
"startWindowIcon":"$media:icon","startWindowBackground":"$color:start_window_background","exported":true}]}}
'@
Write-FixtureFile 'entry/src/main/resources/base/element/color.json' '{"color":[{"name":"start_window_background","value":"#FFFFFF"}]}'
Write-FixtureFile 'entry/src/main/resources/base/profile/main_pages.json' '{"src":["pages/Index","pages/WebPreviewPage"]}'
Write-FixtureFile 'entry/src/main/ets/entryability/EntryAbility.ets' @'
import UIAbility from '@ohos.app.ability.UIAbility';
import window from '@ohos.window';
import appOption from '../model/appOption';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void {
    // Fixture metadata only: this test does not launch QEMU.
    AppStorage.setOrCreate(appOption.currentRunningEmulator, 'fixture');
    AppStorage.setOrCreate(appOption.emulators, [{ id: 'fixture', portMapping: [{ host: 8000, guest: 3080 }] }]);
    AppStorage.setOrCreate(appOption.portUsedByOthers, []);
    stage.loadContent('pages/Index');
  }
}
'@
Write-FixtureFile 'entry/src/main/ets/pages/Index.ets' @'
@Entry
@Component
struct Index {
  build() {
    Column() {
      Text('HiSH Web preview fixture')
      Button('Open preview').onClick(() => this.getUIContext().getRouter().pushUrl({ url: 'pages/WebPreviewPage' }))
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
  }
}
'@
Copy-FixtureFile (Join-Path $taskSource 'ets/pages/WebPreviewPage.ets') 'entry/src/main/ets/components/WebPreviewPage.ets'
Copy-FixtureFile (Join-Path $taskSource 'ets/components/BackButton.ets') 'entry/src/main/ets/components/BackButton.ets'
Copy-FixtureFile (Join-Path $taskSource 'ets/lib/webPreviewUrl.ets') 'entry/src/main/ets/lib/webPreviewUrl.ets'
Copy-FixtureFile (Join-Path $taskSource 'ets/model/appOption.ets') 'entry/src/main/ets/model/appOption.ets'
Copy-FixtureFile (Join-Path $taskSource 'ets/model/Emulator.ets') 'entry/src/main/ets/model/Emulator.ets'
Copy-FixtureFile (Join-Path $taskSource 'resources/base/element/string.json') 'entry/src/main/resources/base/element/string.json'
Copy-FixtureFile (Join-Path $taskSource 'resources/base/element/string.json') 'AppScope/resources/base/element/string.json'
Copy-FixtureFile (Join-Path $taskSource 'resources/zh_CN/element/string.json') 'entry/src/main/resources/zh_CN/element/string.json'
$taskWrapper = [IO.File]::ReadAllText((Join-Path $taskRepo 'product/phone/src/main/ets/pages/WebPreviewPage.ets'))
Write-FixtureFile 'entry/src/main/ets/pages/WebPreviewPage.ets' ($taskWrapper.Replace("from 'hish_main'", "from '../components/WebPreviewPage'"))
$taskIcon = Get-ChildItem (Join-Path $taskRepo 'AppScope/resources/base/media') -Filter *.png | Select-Object -First 1
if (!$taskIcon) { throw 'Missing fixture icon source.' }
Copy-FixtureFile $taskIcon.FullName 'entry/src/main/resources/base/media/icon.png'
Copy-FixtureFile $taskIcon.FullName 'AppScope/resources/base/media/icon.png'
Write-Output 'Unsigned fixture staged; add your own signing identity before device installation.'
