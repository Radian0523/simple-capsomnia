# 受け入れテスト

2026-07-14の本人利用版の実測結果は `VERIFICATION_2026-07-14.md` を参照。物理Caps Lock、
実際の蓋閉じ、1 MiBログ回転は手動スモーク項目として残し、第三者配布用Release gateは未実施。

## 1. 自動テスト

### Core

- [ ] 起動時に現在の Caps Lock から desired state を作る
- [ ] ON は prevent、OFF は normal に対応する
- [ ] helper 成功だけでは verified にならず、`pmset` 一致が必要
- [ ] helper 失敗で degraded になり5秒後に retry
- [ ] `pmset` unknown で degraded
- [ ] 10秒 verification で drift を検出して再適用
- [ ] Caps Lock が連続反転しても古い generation の結果を破棄
- [ ] lid close の display-sleep は close cycle ごとに一回
- [ ] lid unknown では display-sleep を呼ばない

### Parser と helper

- [ ] `SleepDisabled 0` と `1` を解析
- [ ] 欠落、重複、2、文字列、空出力を unknown
- [ ] helper `on` が固定引数へ mapping
- [ ] helper `off` が固定引数へ mapping
- [ ] helper `display-sleep` が固定引数へ mapping
- [ ] 引数なし、複数、未知値が exit 64
- [ ] pmset 起動不能が exit 70
- [ ] pmset の non-zero exit を透過

### HelperVerifier

- [ ] 正常な root-owned regular file を受理
- [ ] symlink を拒否
- [ ] user-owned file を拒否
- [ ] group writable を拒否
- [ ] world writable を拒否
- [ ] non-executable を拒否
- [ ] 不正 signature を拒否
- [ ] 異なる signing identifier を拒否
- [ ] release で異なる Team ID を拒否
- [ ] development の ad hoc signature は Team ID 検査だけ省略
- [ ] 未知または欠落した build flavor では helper を拒否

### Script と package

- [ ] 全 zsh script が `zsh -n` 成功
- [ ] `visudo -cf` fixture が成功
- [ ] sudoers に wildcard と unrestricted command がない
- [ ] sudoers に同一 helper digest の3 command だけがある
- [ ] package script が `cpio` で signed payload を再生成しない
- [ ] `pkgbuild --ownership recommended` を使用
- [ ] package 展開後の app/helper signature が valid
- [ ] package BOM が root:wheel
- [ ] AppleDouble entry がない

## 2. 静的セキュリティ検査

- [ ] `URLSession`、socket、Network framework、telemetry SDK がない
- [ ] event tap、keyboard event callback、keycode 保存がない
- [ ] Accessibility/Input Monitoring の entitlement と説明 key がない
- [ ] helper 内に `/bin/sh`、`zsh`、`bash`、`system()`、`popen()` がない
- [ ] helper の executable path が `/usr/bin/pmset` 以外に分岐しない
- [ ] app の sudo executable path が `/usr/bin/sudo` に固定
- [ ] root path が user input、environment、current directory に依存しない
- [ ] `fuji-mak` の system identifier が残っていない
- [ ] upstream MIT license と NOTICE が存在

## 3. ローカル実機テスト

実行前に、長時間処理を止めても問題ない状態で行う。

### Install

- [ ] 既存 upstream install を検知すると中止し、自動削除しない
- [ ] app が `~/Applications/Capsomnia.app` に入る
- [ ] helper が期待 path に root:wheel 0755 で入る
- [ ] sudoers が root:wheel 0440 で入る
- [ ] sudoers digest と helper SHA-256 が一致
- [ ] LaunchAgent が現在ユーザーとして load される

### Runtime

- [ ] Input Monitoring の prompt が出ない
- [ ] Caps Lock ON 後1秒以内に `SleepDisabled=1`
- [ ] Caps Lock OFF 後1秒以内に `SleepDisabled=0`
- [ ] ON は緑、OFF はグレー
- [ ] helper を利用不能にすると赤になり、成功表示を維持しない
- [ ] helper 復旧後、再インストールまたは retry で回復
- [ ] 外部から state を変えると10秒程度で drift を検知
- [ ] lid close 時に process が継続し、設定 ON なら display が sleep
- [ ] app normal quit 後 `SleepDisabled=0`
- [ ] log にキー入力、username、home path、秘密情報がない
- [ ] log rotation が1 MiBで一世代だけ動く

### Recovery

- [ ] app 強制終了後に LaunchAgent が再起動
- [ ] 再起動後、現在の Caps Lock に同期
- [ ] LaunchAgent disabled 時の残余リスクと手動復旧手順が表示される

### Uninstall

- [ ] uninstall が最初に通常スリープへ復旧
- [ ] app/helper/sudoers/LaunchAgent を削除
- [ ] upstream や他アプリの artifact を削除しない
- [ ] 最終的に `SleepDisabled=0`

## 4. Release gate

次の一つでも失敗した場合は公開しない。

- [ ] clean checkout から build
- [ ] 全 test 成功
- [ ] app/helper の署名 valid
- [ ] app/helper の Team ID 一致
- [ ] package 展開後も内部署名 valid
- [ ] Installer signature valid
- [ ] notarization accepted、ticket stapled
- [ ] app と package が Gatekeeper accepted
- [ ] notarization 後 package 展開でも内部署名 valid
- [ ] SHA-256 checksum を別ファイルに出力
- [ ] release tag、Info.plist version、asset filename が一致

## 5. 合格判定

- Phase A 本人利用版: 自動テスト、静的検査、ローカル Install/Runtime/Uninstall が全合格
- Phase B 配布版: Phase A に加え Release gate が全合格

本人利用版の合格は、第三者へ未署名・ad hoc signed package を配布してよいという意味ではない。
