# セキュリティ設計

## 1. 保護対象

- root 権限で実行される処理を固定された `pmset` 操作だけに限定すること
- app/helper/package の完全性
- 通常の macOS スリープ状態へ戻せること
- 入力内容とユーザーデータを収集しないこと
- リリース成果物がレビュー済みソースと対応していること

## 2. 信頼境界

| コンポーネント | 権限 | 信頼 |
|---|---|---|
| Capsomnia.app | ログインユーザー | UI、状態制御。root としては信頼しない |
| helper | root | 3つの固定 command mapping のみ信頼 |
| sudoers rule | root-owned 0440 | helper path、digest、引数を強制 |
| LaunchAgent | user session | app の起動と異常終了後の再起動 |
| agent reporter | ログインユーザー | Codex / Claude hook metadataを最小化して状態fileへ変換 |
| package scripts | Installer の root | 固定 path の設置と検証だけを行う |
| GitHub Actions | build verifier | secret を PR build に渡さない |

## 3. 想定脅威と対策

### 3.1 helper の置き換え

対策:

- helper file と親 directory は root:wheel
- helper mode は 0755、group/world write 禁止
- symlink を拒否し regular file のみ許可
- sudoers に helper の SHA-256 digest を記録
- app 側でも owner、mode、file type、signature、signing identifier を検証
- release build は app/helper の Team ID 一致を確認

### 3.2 任意引数・shell injection

対策:

- helper は引数数がちょうど1であることを要求
- `on|off|display-sleep` を enum として完全一致
- `/usr/bin/pmset` と引数配列を静的に構築
- app も `Process.executableURL=/usr/bin/sudo` と固定 arguments array を使う
- shell、`sh -c`、PATH lookup、環境変数展開を使わない
- sudoers も3つの完全一致 command line だけを許可

### 3.3 package は有効だが内部コード署名が壊れている

対策:

- app/helper の署名後に payload を変形しない
- package build 前、package 展開後、notarization 後の3地点で内部署名を検証
- `codesign --verify --all-architectures --deep --strict`
- `spctl --assess --type execute` を app と helper に実施
- `pkgutil --check-signature` と `spctl --assess --type install` を package に実施
- 一つでも失敗した release は公開不可

package の検査目的で展開すること自体は許可するが、展開内容から再梱包しない。

### 3.4 不正 app が正規 helper を呼ぶ

sudoers はユーザー単位なので、同じユーザーの別プロセスも許可された3 command を呼べる。
ただし実行できる効果はスリープ抑止 ON/OFF と画面スリープに限定される。これは採用方式の
既知の残余リスクである。任意 root code execution には拡大しない。

より強い caller authentication が必要になった場合は、v2 で authenticated XPC と
SMAppService daemon を検討する。v1 の途中で両方式を混在させない。

### 3.5 アプリ異常終了後に `SleepDisabled=1` が残る

対策:

- LaunchAgent は異常終了時のみ再起動
- 起動時に Caps Lock と実状態を再同期
- 正常終了、SIGTERM、アンインストールで `off` を要求
- README と設定画面に手動復旧コマンドを記載

残余リスク:

- helper、sudoers、LaunchAgent が同時に壊れた場合
- Mac の強制電源断直前など、復旧処理を実行できない場合
- LaunchAgent をユーザーが無効化した状態で app が強制終了した場合

手動復旧:

```sh
sudo /usr/bin/pmset -a disablesleep 0
```

### 3.6 ログからの情報漏えい

対策:

- 入力イベントやユーザーファイルを収集しない
- username、home path、environment を記録しない
- process output は 2 KiB に制限し制御文字を除去
- ローカル保存のみ、network upload なし
- 1 MiB、一世代 rotation

### 3.7 upstream との衝突

対策:

- helper、sudoers、LaunchAgent を独立 namespace にする
- 異なる Bundle ID の `/Applications/Capsomnia.app` を上書きしない
- upstream の既知 artifact を検出したら自動削除せず install を中止
- 同時実行をサポートしないことを README に記載

### 3.8 coding agent hookからの情報漏えい・設定破損

対策:

- hook payloadは最大1 MiBとし、JSON object以外を拒否
- prompt、response、tool名、tool input/output、error本文を保存しない
- session IDはSHA-256のみ、cwdは末尾のproject名だけを保存
- 状態directoryは0700、状態fileは0600、symlinkを拒否
- reporterのevent処理は失敗時も標準出力へ書かずexit 0とし、agent処理を妨げない
- `~/.codex/hooks.json` と `~/.claude/settings.json` はJSONとしてmergeし、既存hookを保持
- Capsomniaのhookは固有markerで識別し、OFF時は自身のentryだけを削除
- root object、`hooks` object、regular fileの検証に失敗した設定は変更しない
- app内の署名済みreporterを絶対pathで呼び、shellへpayloadを展開しない

残余リスク:

- project directoryの末尾名はローカル状態表示のため保存される
- provider側のhook仕様変更で状態が更新されなくなる可能性がある
- remote/cloud側だけで動くsessionは、ローカルhookが届かないため観測できない

## 4. HelperVerifier の必須検査

順序を固定する。

1. `lstat` で path が symlink ではないこと
2. regular file であること
3. owner UID が 0、group GID が 0 であること
4. mode に group/world write bit がないこと
5. 親 directory が root-owned かつ group/world writable でないこと
6. executable bit があること
7. static code signature が有効であること
8. signing identifier が期待値と一致すること
9. release flavor では Team ID が app と一致すること

いずれかが失敗したら helper を実行しない。検証失敗を自動修復しない。

development flavor の ad hoc signature では Team ID がないため 9 のみ省略する。省略可否は
debug flag や環境変数ではなく、署名前に Info.plist へ固定した `CapsomniaBuildFlavor` で決める。
未知の flavor は拒否し、release flavor での省略は禁止する。

## 5. sudoers rule

installer が helper 設置後に SHA-256 を計算し、次の意味を持つ3行を生成する。

```text
<user> ALL=(root) NOPASSWD: sha256:<digest> <helper-path> on
<user> ALL=(root) NOPASSWD: sha256:<digest> <helper-path> off
<user> ALL=(root) NOPASSWD: sha256:<digest> <helper-path> display-sleep
```

- username は `[A-Za-z0-9._-]+` だけを許可
- file は root:wheel 0440
- 一時ファイルで作り、`visudo -cf` 成功後に `install` で置換
- wildcard、directory command、`ALL` command、`SETENV` を使用しない
- helper 更新時は digest も同一 transaction で更新

## 6. ビルド・リリース supply chain

- GitHub Actions は action を full commit SHA で pin
- PR workflow に signing/notarization secret を渡さない
- dependency は Apple SDK と Swift toolchain のみ
- release は保護された tag から実行
- version と Git tag の一致を検証
- package の SHA-256 を release asset として公開
- release asset を差し替えず、修正は version increment
- build log に certificate、keychain profile の秘密情報を出さない

## 7. セキュリティ完了条件

- helper の全 invalid input test が exit 64
- app から任意文字列を helper argument に渡せない
- helper path の symlink、user owner、world writable、署名不正をそれぞれ拒否
- sudoers の許可 command が3つだけであることを自動検査
- app/helper の package 内署名が有効
- app と helper の Team ID が一致
- package が notarized Developer ID として Gatekeeper に受理される
- network API と telemetry SDK が source/dependency scan でゼロ
- Input Monitoring/Accessibility entitlement と利用説明 key がゼロ
- agent reporterが機密payloadを永続化せず、既存hookを保持してinstall/removeできる
