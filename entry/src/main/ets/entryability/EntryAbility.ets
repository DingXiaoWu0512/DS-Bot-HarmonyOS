// The app's entry ability: installs the platform bindings, opens the window,
// and forwards dsbot://pair links (cold start through onCreate, warm through
// onNewWant) the way Linking did on RN.
import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { window, display, KeyboardAvoidMode } from '@kit.ArkUI'

import { installPlatform, handleWant, setMainWindow, applySystemBar } from '../platform/Platform'
import { appStore } from '../appstate/AppStore'

const DOMAIN = 0x0000

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'DSBot', 'onCreate')
    installPlatform(this.context)
    handleWant(want)
    void launchParam
  }

  onNewWant(want: Want): void {
    hilog.info(DOMAIN, 'DSBot', 'onNewWant')
    handleWant(want)
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'DSBot', 'onDestroy')
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'DSBot', 'onWindowStageCreate')
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code !== 0) {
        hilog.error(DOMAIN, 'DSBot', 'loadContent failed: %{public}s', JSON.stringify(err))
        return
      }
      // Immersive: the page draws under the status bar and the gesture
      // indicator; the shell pads its content by the avoid areas and paints
      // them with the page color.
      try {
        const win = windowStage.getMainWindowSync()
        setMainWindow(win)
        win.setWindowLayoutFullScreen(true)
        // The default avoid mode is OFFSET — the whole page translates up
        // when the keyboard shows, which lifted the header off-screen on top
        // of our own handling. RESIZE instead shrinks the page to the space
        // above the keyboard, so the floating composer rides the bottom edge
        // and the header stays put; the shell only pads the safe insets.
        win.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE)
        const systemArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        const navArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR)
        const density = display.getDefaultDisplaySync().densityPixels
        appStore.setSafeInsets(systemArea.topRect.height / density, navArea.bottomRect.height / density)
        applySystemBar(appStore.isDark())
        win.on('avoidAreaChange', (event) => {
          if (event.type === window.AvoidAreaType.TYPE_KEYBOARD) {
            appStore.setKeyboard(event.area.bottomRect.height / density)
          }
        })
      } catch (failure) {
        hilog.warn(DOMAIN, 'DSBot', 'immersive setup failed: %{public}s', failure instanceof Error ? failure.message : String(failure))
      }
    })
  }

  onWindowStageDestroy(): void {}

  onForeground(): void {
    // Waking is the common half-open case: the link probes first so a dead
    // socket declares itself (RN: AppState 'active').
    appStore.link.onForeground()
  }

  onBackground(): void {
    appStore.link.onBackground()
  }
}
