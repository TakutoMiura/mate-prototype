# MATE小隊RTS

Godotで開発する、小隊指揮型リアルタイム戦術ゲームのプロトタイプです。『フロントミッション オルタナティヴ』はプレイ感覚の参照であり、原作仕様の再現を目的としません。

## 開発環境

- Godot Engine 4.7 系
- プロジェクト設定: [`project.godot`](project.godot)

プロジェクトをGodotで開き、実行してください。Windowsでリポジトリ直下の `Godot_v4.7.2-stable_win64.exe.lnk` を使う場合は、PowerShellからショートカット先を解決して起動できます。Codexの制限環境ではユーザー設定先に書き込めないため、`APPDATA` をプロジェクト内へ向けます。

```powershell
$godotShortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path (Get-Location) 'Godot_v4.7.2-stable_win64.exe.lnk'))
$env:APPDATA = Join-Path (Get-Location).Path '.godot-user-data'
& $godotShortcut.TargetPath --path (Get-Location).Path --editor
```

スクリプトやシーンの読み込み確認はエディタを開かずに実行できます。Windowsでは終了コードとログを待ち受けるため、ショートカット先と同じ場所にあるコンソール版を使います。

```powershell
$godotShortcut = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path (Get-Location) 'Godot_v4.7.2-stable_win64.exe.lnk'))
$godotConsole = Join-Path (Split-Path -Parent $godotShortcut.TargetPath) 'Godot_v4.7.2-stable_win64_console.exe'
$env:APPDATA = Join-Path (Get-Location).Path '.godot-user-data'
& $godotConsole --headless --path (Get-Location).Path --scene res://Scenes/test_field.tscn --quit-after 2
& $godotConsole --headless --path (Get-Location).Path --script res://tests/jump_movement_regression.gd
```

通常はサンプルデータを使ったMATE運用画面と、各小隊3機・計9機をResource定義から組み立てた3Dテストフィールドを表示します。小隊を選択し、地面を左クリックするとウェイポイントを設定、Shift＋左クリックで経路末尾へ追加して、平面移動・停止旋回と機械的な歩行モーションを確認できます。ジャンプ接続の試験場には、地上から乗れる踏み台と、その奥に踏み台経由でのみ乗り降りできる高台があります。高台を目的地にすると、踏み台から高台へ順次ジャンプする経路表示・移動を確認できます。踏み台の左右から試す場合は、左右端の着地領域を最初のウェイポイントにし、踏み台奥側中央を経由してから高台を目的地にしてください。高台から地上へ戻す場合は、高台のウェイポイントの後ろに地上のウェイポイントを追加します。停止旋回中はルート位置を保ち、接地足の誤差に応じて片脚ずつ踏み替えます。旋回モーションの基準値はTestFieldのInspectorから調整でき、Standing Turnのデバッグ表示も切り替えられます。歩行中は脚に対する腰の逆捻り、上半身のカウンター回旋、支持脚側への荷重移動を表示します。第一小隊は棒人間モデル、第二小隊は胸部を前へ張り出した簡易箱メカモデルで、両者は同じ歩行ロジックを使います。ウェイポイント命令は小隊ごとに独立しており、比較時は各小隊へ個別に同等の移動指示を出してください。HUDと3Dプレビューは同じ機体状態を参照し、HP・盾HP・バックユニット弾数は各定義の最大値で初期化します。障害物経路計画と戦闘シミュレーションはまだ接続していません。サンプル機体・装備の性能値は表示用の暫定値です。

## Codex skills

性能の目標は同時30機・60fpsです。評価に使う対象ハードウェア、解像度、画質設定、機体の動作負荷は未決です。

プロジェクト用skillsは `.agents/skills/` にあります。実装時は `$godot-implementation`、仕様に沿ったロジック確認は `$godot-logic-review`、計測を含む性能確認は `$godot-performance-review`、レビュー後の振る舞いを保った整理は `$godot-refactor` を使います。

## 仕様書

`Documents/` にゲームデザイン、操作、小隊行動、移動、UI、MATE・装備データモデル、受け入れ条件をまとめています。MATE運用画面の暫定UI方針は [`Documents/UI_DESIGN.md`](Documents/UI_DESIGN.md)、MATEと装備のデータ項目は [`Documents/EQUIPMENT_DATA_MODEL.md`](Documents/EQUIPMENT_DATA_MODEL.md)、読む順序と変更方針は [`Documents/DEVELOPMENT_WORKFLOW.md`](Documents/DEVELOPMENT_WORKFLOW.md) を参照してください。

仕様には草案・提案・未決定事項が含まれます。未決定事項を実装時に推測で確定せず、仕様書間の矛盾や不足は設計判断として記録してから更新します。
