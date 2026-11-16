// The phone app's own version, for the About page. The bundle manager answers
// synchronously with the versionName of the installed HAP.

import { bundleManager } from '@kit.AbilityKit'

let cachedVersion: string = ''

export function readAppVersion(): string {
  if (cachedVersion !== '') {
    return cachedVersion
  }
  try {
    const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
    cachedVersion = info.versionName
  } catch {
    cachedVersion = '—'
  }
  return cachedVersion
}
