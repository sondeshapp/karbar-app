# Android APK releases

The `Android APK Release` GitHub Actions workflow runs when code is pushed to
`main` (including merged pull requests) or when started manually. It builds a
release APK, increments Android's build number, and publishes the APK as a
GitHub Release with automatically generated notes.

## One-time signing setup

GitHub needs a persistent Android upload key so each APK can update the previous
one. Generate the key on a secure machine and keep a private backup:

```sh
keytool -genkeypair -v -keystore karbar-upload-key.jks -keyalg RSA \
  -keysize 2048 -validity 10000 -alias karbar
base64 -w 0 karbar-upload-key.jks
```

In the repository's **Settings → Secrets and variables → Actions**, add these
repository secrets:

- `ANDROID_KEYSTORE_BASE64`: the complete output from the `base64` command
- `ANDROID_KEY_ALIAS`: `karbar` (or the alias chosen when generating the key)
- `ANDROID_KEY_PASSWORD`: the key password
- `ANDROID_STORE_PASSWORD`: the keystore password

The workflow fails before building if any signing secret is missing. The
keystore and `android/key.properties` are ignored by Git and are created only
on the CI runner.

Each release tag has the form `v<pubspec version>-build.<GitHub run number>`;
for example, `v1.0.0-build.42`. Release notes are generated from commits since
the previous GitHub Release.
