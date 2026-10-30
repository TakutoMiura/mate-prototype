# MATE小隊RTS

Godotで開発する、小隊指揮型リアルタイム戦術ゲームのプロトタイプです。『フロントミッション オルタナティヴ』はプレイ感覚の参照であり、原作仕様の再現を目的としません。

## 開発環境

- Godot Engine 4.7 系
- プロジェクト設定: [`project.godot`](project.godot)

プロジェクトをGodotで開き、実行してください。現在はサンプルデータを使ったMATE運用画面と、各小隊3機・計9機をResource定義から組み立てた3Dテストフィールドを表示します。小隊を選択し、地面を左クリックするとウェイポイントを設定、Shift＋左クリックで経路末尾へ追加して、平面移動と進行方向への旋回を確認できます。HUDと3Dプレビューは同じ機体状態を参照し、HP・盾HP・バックユニット弾数は各定義の最大値で初期化します。障害物・ジャンプ・戦闘シミュレーションはまだ接続していません。サンプル機体・装備の性能値は表示用の暫定値です。

## Codex skills

プロジェクト用skillsは `.agents/skills/` にあります。実装時は `$godot-implementation`、仕様に沿ったロジック確認は `$godot-logic-review`、計測を含む性能確認は `$godot-performance-review`、レビュー後の振る舞いを保った整理は `$godot-refactor` を使います。

## 仕様書

`Documents/` にゲームデザイン、操作、小隊行動、移動、UI、MATE・装備データモデル、受け入れ条件をまとめています。MATE運用画面の暫定UI方針は [`Documents/UI_DESIGN.md`](Documents/UI_DESIGN.md)、MATEと装備のデータ項目は [`Documents/EQUIPMENT_DATA_MODEL.md`](Documents/EQUIPMENT_DATA_MODEL.md)、読む順序と変更方針は [`Documents/DEVELOPMENT_WORKFLOW.md`](Documents/DEVELOPMENT_WORKFLOW.md) を参照してください。

仕様には草案・提案・未決定事項が含まれます。未決定事項を実装時に推測で確定せず、仕様書間の矛盾や不足は設計判断として記録してから更新します。
