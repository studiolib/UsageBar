# UsageBar

UsageBar は、Claude と Codex の利用制限残量を macOS のメニューバーから確認する日本語UIのネイティブアプリです。

メニューバーの小さなアイコンとポップオーバーで、各サービスの残量、リセット時刻、リセットまでの残り時間を確認できます。

## 主な機能

- Swift / SwiftUI / AppKit で実装した macOS メニューバーアプリ
- 2本バーのメニューバーアイコン
  - 上: Claude の週間残量
  - 下: Codex の週間残量
- ポップオーバー表示
  - Claude / Codex の利用制限カード
  - 残量パーセント
  - リセット日時とリセットまでの残り時間
  - 最終取得時刻
  - 公式の使用量確認ページへのリンク
- macOS のライト / ダークモードに追従
- 取り込んだ資格情報は UsageBar 自身の Keychain 項目に保存

## 動作環境

- macOS 14 以降
- Swift 6.1 に対応した Xcode / Swift toolchain
- 同じMac上で Claude Code または Codex CLI の認証が済んでいること

## ソースから起動

```sh
swift run UsageBar
```

## .app を作成

```sh
scripts/package_app.sh
```

作成されたアプリは `.build/UsageBar.app` に配置されます。

UsageBar は Developer ID署名・notarizationなしで配布する方針です。配布元をmacOSが確認できないため、初回起動時にGatekeeperの警告が表示されることがあります。その場合はFinderでアプリをControlクリックして「開く」を選ぶか、システム設定の「プライバシーとセキュリティ」から明示的に許可してください。手順は [リリース手順](docs/release.md) を参照してください。

## 認証の扱い

UsageBar は Claude Code と Codex CLI が作成したローカル認証状態を利用します。ユーザーにAPIキーの貼り付けを求める設計ではありません。

Claude:

- まず UsageBar 自身の Keychain 項目を読みます
- ユーザーが明示的に再認証を実行した場合のみ、既存の Claude Code 資格情報を UsageBar の Keychain に取り込みます
- 取り込み後の通常更新では UsageBar 自身の Keychain だけを利用します

Codex:

- 通常更新では UsageBar 自身の Keychain 項目だけを読みます
- ユーザーが明示的に再認証を実行した場合のみ、既存の Codex CLI 資格情報を UsageBar の Keychain に取り込みます
- 取り込んだ資格情報と更新後の資格情報は UsageBar 自身の Keychain に保存します
- 更新後のトークンを Codex CLI の認証ファイルへ書き戻しません

## プライバシー

UsageBar は利用制限の確認だけを目的にしています。

- ポップオーバーにアカウントのメールアドレスやアカウントIDを意図的に表示しません
- アナリティクスを収集しません
- このプロジェクトが管理する外部サーバーへ使用量データを送信しません
- 利用量取得とトークン更新に必要な範囲で、Claude、ChatGPT/OpenAI、および各認証エンドポイントへ通信します

## 注意事項

UsageBar は非公式のサードパーティアプリです。Anthropic、OpenAI、Claude、ChatGPT、Codex とは提携、承認、後援関係にありません。

UsageBar は Claude Code / Codex CLI が作成したローカル認証状態と、各サービスの利用量エンドポイントに依存しています。これらの認証方式やAPIが変更された場合、アプリが動作しなくなる可能性があります。

利用量の取得とトークン更新には、各サービスの公開クライアント互換の認証フローと、安定版の公開APIとして保証されていないエンドポイントを利用する場合があります。ここで使うクライアント識別子は秘密情報ではありませんが、提供元の仕様・利用規約・運用方針の変更によって利用できなくなる可能性があります。

UsageBar は公式クライアントの代替や、各サービスの動作を保証するものではありません。利用前に、各サービスの最新の利用規約とポリシーを利用者自身で確認してください。

## 既知の制限

- Claude / Codex の利用量APIは安定した公開APIであることが保証されていません
- アカウントやプランによって、週間制限だけが返る場合と短時間制限も返る場合があります
- Codex CLI と UsageBar を同時に使う場合、サービス側のトークン更新仕様によっては、どちらかで再認証が必要になることがあります
- GitHub ReleaseやHomebrew Caskから入手したアプリも、初回起動時にmacOSの明示的な許可が必要になることがあります
- Homebrew 配布は、GitHub ReleaseのZIPとSHA-256を用意したあと Cask として対応する想定です

## ドキュメント

- [アーキテクチャ](docs/architecture.md)
- [リリース手順](docs/release.md)

## 開発

テスト:

```sh
swift test
```

構成:

```text
Sources/
  UsageBar/       macOSアプリ、メニューバー、ポップオーバーUI
  UsageBarCore/   ドメインモデル、設定、プロバイダ、パーサ、永続化ヘルパー
Tests/
  UsageBarCoreTests/
Packaging/
  Info.plist とアプリアイコン
scripts/
  ローカルパッケージ作成スクリプト
```

## ライセンス

MIT License です。詳細は [LICENSE](LICENSE) を参照してください。
