# リリース手順

UsageBar は Developer ID署名・notarizationなしで配布します。`scripts/package_app.sh` で作成した `.app` をZIP化してGitHub Releaseへ添付します。

## 事前条件

- Xcode Command Line Tools
- GitHub Releaseを作成できるGitHubアカウント

Apple Developer Program、Developer ID証明書、notarization用認証情報は通常配布には不要です。

## 配布用ZIPの作成

```sh
scripts/package_app.sh
ditto -c -k --norsrc --keepParent .build/UsageBar.app .build/UsageBar-0.1.0.zip
shasum -a 256 .build/UsageBar-0.1.0.zip > .build/UsageBar-0.1.0.zip.sha256
shasum -a 256 -c .build/UsageBar-0.1.0.zip.sha256
```

チェックサムの照合が成功したZIPとSHA-256チェックサムをGitHub Releaseへ添付します。

## 利用者向けの初回起動案内

Developer ID署名・notarizationを行わないため、利用者のmacOSでは初回起動時にGatekeeperの警告が表示されることがあります。リリースノートには次の案内を記載してください。

1. ZIPを展開する
2. `UsageBar.app` をFinderでControlクリックする
3. 「開く」を選び、確認ダイアログでも「開く」を選ぶ
4. 上記で開けない場合は、システム設定の「プライバシーとセキュリティ」からUsageBarを明示的に許可する

Homebrew Cask経由でインストールした場合も、初回起動時のGatekeeper確認は同様です。

## GitHub Release

1. タグを作成してpushする
2. GitHubでReleaseを作成する
3. `UsageBar-<version>.zip` と `UsageBar-<version>.zip.sha256` を添付する
4. macOS 14以降が必要であること、非公式アプリであること、初回起動時にGatekeeperの許可が必要になる場合があることをリリースノートに記載する

## Homebrew Cask

GitHub Releaseで公開したZIPをCaskとして配布できます。CaskにはRelease ZIPの固定URLとSHA-256を指定します。Homebrew CaskはGatekeeperの確認を省略しないため、初回起動時の許可手順はGitHub Releaseからの配布と同じです。
