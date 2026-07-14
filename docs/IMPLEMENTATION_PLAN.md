# 実装計画

実装は下記の順番を変えない。各 phase の exit criteria を満たしてから次へ進む。

## Phase 0: リポジトリ初期化と帰属表示

作業:

- `oonishidaichi/capsomnia` を独立 Git repository として初期化
- upstream の MIT `LICENSE` を維持
- `NOTICE.md` に upstream URL、元著作者、主な変更点を記載
- SwiftPM skeleton と最小 CI を作成
- macOS 14+、Swift 6、外部 dependency なしを固定

完了条件:

- `swift build` と空の `swift test` が成功
- Bundle ID と全 system path が `oonishidaichi` namespace
- upstream の `fuji-mak` identifier が実行コードと install script に残っていない

## Phase 1: Core と helper

作業:

- `ProductIdentity` と path derivation
- `SleepStateParser`
- helper command enum と固定 `pmset` mapping
- helper executable
- service protocols と fake
- `SleepController` state machine

テスト:

- `SleepDisabled 0|1`、欠落、異常値、余分な空白
- helper の on/off/display-sleep と全 invalid input
- 起動同期、Caps Lock 反転、helper 失敗、read 失敗、drift、retry
- generation が古い結果を破棄すること
- 蓋 close cycle ごとに display-sleep が一回だけであること

完了条件:

- Core test で状態遷移が完全に再現可能
- helper に shell/network/file write API がない
- helper の mapping がテスト以外から変更できない

## Phase 2: macOS adapter と最小 UI

作業:

- `CapsLockMonitor`
- `PmsetStateReader`
- `ClamshellStateReader`
- async `ProcessRunner`
- `HelperVerifier` と `HelperClient`
- `ApplicationController`
- status item、menu、settings window、初回画面
- preferences と log rotation
- duplicate instance handling
- SIGTERM と正常終了時の restore-off

完了条件:

- root helper 未設置の状態で安全に赤表示になる
- UI thread が `pmset`/sudo の終了待ちで block しない
- Input Monitoring を求めず Caps Lock 変化を検知
- menu icon を隠しても error 時は赤表示
- アプリ終了時に off を一度だけ要求

## Phase 3: ローカルインストール

作業:

- `build-app.sh`
- ad hoc signing
- `install-local.sh`
- digest 付き sudoers
- user LaunchAgent
- `uninstall.sh`
- upstream/conflicting install の検出
- installation verification command

重要:

- この phase の install 実行は、コードレビューとユーザーの明示承認後に行う。
- install 前に現在の `pmset -g` と既存 artifact を記録する。
- 元アプリの artifact は自動削除しない。

完了条件:

- helper が root:wheel 0755、sudoers が root:wheel 0440
- `visudo -cf` が成功
- `sudo -n -l` で3 command だけが許可
- helper digest が実ファイルと一致
- login item が起動し、Caps Lock ON/OFF が実状態に反映
- uninstall 後 `SleepDisabled=0`、app/helper/sudoers/LaunchAgent が残らない

ここまでで本人利用版を完成とする。

## Phase 4: package build の修正設計

作業:

- destination root に app/helper/LaunchAgent を配置
- app/helper を配置完了後に署名
- 署名直後に strict verify
- `pkgbuild --ownership recommended` で一度だけ package 化
- preinstall で異なる Bundle ID と upstream artifact を検出
- postinstall で owner/mode、digest sudoers、LaunchAgent を構成
- package 展開は read-only verification 用だけに使用
- `verify-artifacts.sh` を作る

禁止事項:

- package payload の展開後再圧縮
- `cpio` での payload 再生成
- signed app/helper に対する `xattr -cr`
- package 外から内部 executable を差し替える処理

完了条件:

- unsigned CI package を展開して app/helper の ad hoc signature が valid
- BOM owner が期待通り root:wheel
- AppleDouble、quarantine、不要 xattr が payload にない
- install scripts の shell syntax と固定 path test が成功

## Phase 5: Developer ID と notarization

作業:

- app/helper を同じ Developer ID Application で署名
- helper に明示 identifier を付与
- package を Developer ID Installer で署名
- notarization、staple、Gatekeeper 検査
- `SHA256SUMS.txt` 生成

完了条件:

- `codesign --verify --all-architectures --deep --strict` が app で成功
- `codesign --verify --all-architectures --strict` が helper で成功
- app/helper の Team ID 一致
- package 展開後も上記が成功
- `pkgutil --check-signature` が有効な Installer certificate を表示
- `spctl --assess --type install` が Notarized Developer ID として accepted
- notarization 後に再展開して内部署名が成功

## Phase 6: 実機回帰と release

実機シナリオ:

1. clean install
2. first launch
3. Caps Lock ON/OFF を各5回
4. lid close/open cycle
5. helper を一時的に利用不能にした error/recovery
6. app normal quit
7. app forced termination と LaunchAgent recovery
8. same-version reinstall
9. upgrade install
10. uninstall

完了条件:

- `docs/ACCEPTANCE_TESTS.md` の必須項目が全合格
- 既知の残余リスクを README に記載
- versioned pkg、stable pkg、checksums の3 asset が一致
- release tag と app version が一致

## 実装時に先送りしてよいもの

- UI の細かなブランド調整
- universal binary。最初は現在の Mac の native architecture でよい
- v2 の authenticated XPC/SMAppService daemon
- 自動アップデート

先送りしてはいけないもの:

- helper の path/owner/mode/signature 検証
- digest 付き sudoers
- verified state と requested state の分離
- uninstall 時の restore-off
- package 内 app/helper の署名検証
- upstream との衝突検出と MIT attribution

