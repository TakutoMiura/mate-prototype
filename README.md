# MATE小隊RTS

Godotで開発する、小隊指揮型リアルタイム戦術ゲームのプロトタイプです。『フロントミッション オルタナティヴ』はプレイ感覚の参照であり、原作仕様の再現を目的としません。

## 開発環境

- Godot Engine 4.7 系
- プロジェクト設定: [`project.godot`](project.godot)

プロジェクトをGodotで開き、実行してください。現時点ではゲーム実装前の仕様整理段階です。

## Codex skills

プロジェクト用skillsは `.agents/skills/` にあります。実装時は `$godot-implementation`、仕様に沿ったロジック確認は `$godot-logic-review`、計測を含む性能確認は `$godot-performance-review`、レビュー後の振る舞いを保った整理は `$godot-refactor` を使います。

## 仕様書

`Documents/` にゲームデザイン、操作、小隊行動、移動、受け入れ条件をまとめています。読む順序と変更方針は [`Documents/DEVELOPMENT_WORKFLOW.md`](Documents/DEVELOPMENT_WORKFLOW.md) を参照してください。

仕様には草案・提案・未決定事項が含まれます。未決定事項を実装時に推測で確定せず、仕様書間の矛盾や不足は設計判断として記録してから更新します。
