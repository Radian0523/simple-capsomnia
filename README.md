# Capsomnia (oonishidaichi版)

`fuji-mak/Capsomnia` を参考に、独立した権限namespaceと検証可能な状態機械で再実装している
macOSメニューバーアプリです。

本人利用向けのPhase 0〜3は完成し、2026-07-14にこのMacへ最終インストール済みです。
Core、固定helper、helper検証、macOSアダプタ、設定UI、LaunchAgent、インストール／
アンインストールを含みます。24件の自動テスト、実機の権限検証、終了時のスリープ復元、
アンインストール後のクリーン再インストールまで合格しています。

2026-07-14 の監査では、upstream の公開 package 自体は Developer ID 署名と公証を通過
していましたが、展開後の app/helper はローカルの厳格な code-signature 検証に失敗しました。
この設計は、その公開 package をそのまま利用せず、内部署名が最後まで維持される独立 build を
作ることを前提にしています。

## 設計の結論

- 製品名は当面 `Capsomnia` とする。
- Bundle ID は `com.github.oonishidaichi.capsomnia` とする。
- Caps Lock ON でシステムスリープを抑止し、OFF で通常状態へ戻す。
- アプリ本体は一般ユーザー権限で動かす。
- root 権限は、固定引数だけを受け付ける小さなネイティブ helper に限定する。
- sudoers は helper の絶対パス、引数、SHA-256 digest を固定する。
- 入力監視、キーボードイベント取得、ネットワーク通信、テレメトリは行わない。
- 個人利用できるローカル版を先に完成させ、署名済み配布パッケージは別フェーズにする。
- 署名後の app/helper を展開・再圧縮・xattr 削除しない。

## 文書

- [製品・技術設計](docs/DESIGN.md)
- [セキュリティ設計](docs/SECURITY.md)
- [実装計画](docs/IMPLEMENTATION_PLAN.md)
- [受け入れテスト](docs/ACCEPTANCE_TESTS.md)
- [5.5 実装ハンドオフ](docs/HANDOFF_5_5.md)
- [Phase 3 インストール事前確認](docs/PHASE3_INSTALL_PREVIEW.md)
- [2026-07-14 検証結果](docs/VERIFICATION_2026-07-14.md)

## 開発

```sh
swift test
swift build -c release
```

```sh
./scripts/install-local.sh
./scripts/verify-install.sh
./scripts/test-runtime.sh
./scripts/uninstall.sh
```

管理者処理はmacOS標準の認証ダイアログを使います。パスワードをスクリプトへ渡しません。
現在のビルドはDeveloper ID証明書がないためad hoc署名の本人利用版です。第三者配布用の署名・
公証済みpackageは作成していません。

## 参照元とライセンス

本設計は MIT License の `fuji-mak/Capsomnia` を参照しています。実装で元コードの
全部または実質的な一部を利用する場合、元の copyright notice と MIT License を
必ずリポジトリに残します。README にも upstream と変更点を明記します。
