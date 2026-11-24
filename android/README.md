# Bushido Future for Android

The Android app for **Bushido Future**. It opens https://bushido-future.onrender.com full-screen,
with its own icon and splash screen.

| | |
|---|---|
| Package ID | `io.github.tgood91.bushidofuture` |
| Language | Kotlin 2.1 (Gradle Kotlin DSL) |
| Android | 7.1 and newer (min SDK 25), targets Android 16 (SDK 36) |
| Website | this repository's root (Vite + React), hosted on Render as the static site `bushido-future` |

It is the same Trusted Web Activity shell as
[Bushido-dApp-android](https://github.com/Tgood91/Bushido-dApp-android): the page runs in the
phone's Chrome with no address bar, so wallet links and email/social login work as on the website,
and every deploy of the site reaches the app without a new release. The app holds no keys or funds.

## How the app and the site vouch for each other

- App side: `app/src/main/res/values/strings.xml` (`asset_statements`) names the site.
- Site side: `public/.well-known/assetlinks.json` in the repository root names the package and the
  signing key's SHA-256 fingerprint. Vite copies it to `dist/`, so Render serves it at
  https://bushido-future.onrender.com/.well-known/assetlinks.json.

If they don't match (a different key, or the deploy isn't finished), the app still works but shows
an address bar. Chrome caches the check: reinstall the app after fixing it.

## Build

- **Debug:** CI (`.github/workflows/android.yml`) runs the unit tests, lint and a debug build on
  every change under `android/`, and uploads `bushido-future-debug`. Locally:
  `cd android && ./gradlew assembleDebug`.
- **Release:** signed with the same key as Bushido-dApp-android, which lives only on the owner's
  computer (`C:\Users\jessi\bushido-signing`). Put a git-ignored `keystore.properties` next to this
  README (see `keystore.properties.example`), then:
  ```
  cd android
  ./gradlew assembleRelease   # signed APK in app/build/outputs/apk/release/
  ./gradlew bundleRelease     # .aab for Google Play in app/build/outputs/bundle/release/
  ```
  Raise `versionCode` in `app/build.gradle.kts` for every release uploaded to Google Play.

## Changing the site address

Change all of these together: `SITE_HOST` and `manifestPlaceholders["siteHost"]` in
`app/build.gradle.kts`, the `site` inside `asset_statements` in `res/values/strings.xml`, and the
host in `app/src/test/.../LaunchUrlTest.kt`.
