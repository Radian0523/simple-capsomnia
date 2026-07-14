# 本人利用版 検証結果（2026-07-14）

## 結論

本人利用向けPhase 0〜3は合格。完成版をこのMacへクリーンインストール済み。
Developer ID証明書がないため、第三者配布用の署名・公証済みpackageは対象外。

## 自動検証

- `swift test`: 24 tests、0 failures
- release build: 成功
- app/helper: ad hoc + hardened runtime、`codesign --strict` 成功
- helper未知引数: exit 64
- 全zsh script: `zsh -n` 成功
- sudoers fixture: `visudo -cf` 成功
- 静的走査: network、telemetry、Input Monitoring、event tap、shell実行APIなし
- runtime依存: Apple system frameworksとSwift runtimeのみ

## 権限境界

- app: `~/Applications/Capsomnia.app`
- helper: `/Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper`
  (`root:wheel`, `0755`)
- sudoers: `/etc/sudoers.d/capsomnia_oonishidaichi` (`root:wheel`, `0440`)
- helper SHA-256: `30d2f413e35263118037c29bf6051a76ea1c81516af611fc2371ce447c30baf3`
- passwordless許可: 同一digestのhelperに対する `on`、`off`、`display-sleep` の3つだけ
- LaunchAgent: `com.github.oonishidaichi.capsomnia`、現在ユーザーとして稼働

sudoのincludedirはピリオドを含むファイル名を無視するため、sudoersファイル名にはBundle IDを
直接使わず `capsomnia_oonishidaichi` を使用する。旧名はインストール時に削除する。

## 実機検証

- helper `on`: `SleepDisabled=1`
- SIGTERM: 署名検証付き同期 `off`、成功ログ後に終了
- 終了後: `SleepDisabled=0`
- LaunchAgent: 終了試験後に再起動成功
- install verification: app/helper署名、所有権、mode、sudoers 3 command、plist、load状態が合格
- uninstall: app/helper/sudoers/LaunchAgentと旧sudoers名が消去され、`SleepDisabled=0`
- clean reinstall: 成功し、同じ検証と終了復元試験に再合格
- UI: 日本語設定画面を実表示し、文字切れ、重なり、操作不能なし
- 初回セットアップ: 既定値で完了し、メニューバー常駐へ移行

物理HIDのCaps Lock反転は自動化ツールから再現できなかったため、実キーによるON/OFFだけは手動
スモーク項目として残す。ON/OFF状態機械、helper、`pmset`、終了復元の各経路は自動・実機試験済み。
