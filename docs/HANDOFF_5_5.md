# 5.5 実装ハンドオフ

## あなたの役割

このフォルダの設計を、動作する macOS アプリとして段階的に実装する。設計の再検討より、
定義済みの境界と受け入れ条件を正確にコードへ移すことを優先する。

## 最初に読む順番

1. `README.md`
2. `docs/DESIGN.md`
3. `docs/SECURITY.md`
4. `docs/IMPLEMENTATION_PLAN.md`
5. `docs/ACCEPTANCE_TESTS.md`
6. upstream clone の `LICENSE` と必要な参照コード

## 実装開始時の指示

- 作業場所はこの `oonishidaichi/capsomnia` ディレクトリだけにする。
- upstream の clone は読み取り参照とし、直接変更しない。
- Phase 0 から順に進め、各 phase の exit criteria をテストしてから次へ進む。
- まず Phase 0 から Phase 2 まで実装し、root 変更を伴う install はまだ実行しない。
- Phase 3 の install 実行前に、変更ファイル、sudoers 内容、設置 path をユーザーへ提示し、
  明示承認を得る。
- Phase 5 は Developer ID certificate が利用可能な場合だけ行う。

## 変更してはいけない決定

- Bundle ID と system path の `oonishidaichi` namespace
- app は一般ユーザー、root は固定 helper だけという境界
- helper command が `on|off|display-sleep` の3つだけであること
- shell を介さないこと
- helper verifier と digest 付き sudoers
- requested state と verified state を分けること
- app/helper 署名後に package payload を再圧縮しないこと
- network、telemetry、Input Monitoring を入れないこと
- upstream の MIT attribution を残すこと

変更が必要になった場合は、コードで黙って逸脱せず、理由、脅威への影響、代案を設計書へ
追記してからユーザーに確認する。

## 実装品質

- Swift 6 concurrency warning を無視しない。
- UI actor で `Process.waitUntilExit()` を呼ばない。
- Core は macOS process/API から分離し、fake で deterministic にテストする。
- path、executable、helper argument は typed value にし、任意 String の伝播を避ける。
- root script は absolute command path、quoted variable、固定 destination を使う。
- unrelated なサイト、依存 package、auto updater を追加しない。
- コメントは安全性の理由や非自明な state rule にだけ付ける。

## 最初の成果物

最初の実装ターンでは、以下までを目標にする。

- Phase 0 の repository skeleton
- Phase 1 の Core、helper、unit test
- Phase 2 の最小 app が build し、helper 未設置を赤表示できること
- `swift test`、`swift build -c release` の結果
- Phase 3 で root に設置される予定の正確な path と sudoers preview

この時点では `sudo`、package install、LaunchAgent 登録を実行しない。

## 完了報告の形式

各 phase ごとに次を短く報告する。

- 実装した境界とユーザーに見える動作
- 変更した主要ファイル
- 実行したテストと結果
- 未実行の実機/root/release 検査
- 設計からの逸脱があればその理由

