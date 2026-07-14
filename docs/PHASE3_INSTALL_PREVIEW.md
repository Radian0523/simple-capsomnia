# Phase 3 ローカルインストール事前確認

状態: 実行済み  
承認: 2026-07-14 取得済み

この文書は、Phase 3で予定した変更の事前確認記録です。ユーザーの明示承認後、以下の内容で
インストール、アンインストール、クリーン再インストールを実施しました。

## 設置予定

| 種類 | path | owner / mode |
|---|---|---|
| app | `/Users/oonishidaichi/Applications/Capsomnia.app` | `oonishidaichi` / bundle既定 |
| helper | `/Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper` | `root:wheel` / `0755` |
| sudoers | `/etc/sudoers.d/capsomnia_oonishidaichi` | `root:wheel` / `0440` |
| LaunchAgent | `/Users/oonishidaichi/Library/LaunchAgents/com.github.oonishidaichi.capsomnia.plist` | `oonishidaichi` / `0644` |
| log | `/Users/oonishidaichi/Library/Logs/Capsomnia/capsomnia.log` | `oonishidaichi` |

## sudoers preview

`<SIGNED_HELPER_SHA256>` は、ad hoc署名を完了してroot-owned pathへ配置したhelperから計算し、
3行すべてに同じ値を入れます。

```text
# Capsomnia: allow only the signed fixed pmset helper commands.
oonishidaichi ALL=(root) NOPASSWD: sha256:<SIGNED_HELPER_SHA256> /Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper on
oonishidaichi ALL=(root) NOPASSWD: sha256:<SIGNED_HELPER_SHA256> /Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper off
oonishidaichi ALL=(root) NOPASSWD: sha256:<SIGNED_HELPER_SHA256> /Library/PrivilegedHelperTools/com.github.oonishidaichi.capsomnia.pmset-helper display-sleep
```

wildcard、任意引数、任意command、`SETENV`、shellは許可しません。一時ファイルに生成して
`/usr/sbin/visudo -cf` が成功した場合だけ、`/usr/bin/install -o root -g wheel -m 0440` で
置換します。

## 実行前チェック

- `/Applications/Capsomnia.app` のBundle IDが異なる場合は中止
- upstreamのhelper、sudoers、LaunchAgentが存在する場合は中止し、自動削除しない
- 現在の `pmset -g` を記録
- app/helperをad hoc署名し、strict verificationを実行
- helperのsigning identifierが期待値と一致することを確認
- 生成予定のsudoers本文とhelper SHA-256を再提示

## 実行後チェック

- helperがroot:wheel 0755
- sudoersがroot:wheel 0440
- `visudo -cf` 成功
- sudoers digestとhelper SHA-256が一致
- 許可commandが3つだけ
- Caps Lock ON/OFFと`SleepDisabled`が一致
- 正常終了時に`SleepDisabled=0`
- uninstall後に全artifactが消え、`SleepDisabled=0`

実行結果は `VERIFICATION_2026-07-14.md` に記録しています。
