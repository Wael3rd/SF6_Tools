# REFrameworkでStreet Fighter 6のネイティブなインゲームメニューとHUDを構築する

> **TL;DR** -- REFrameworkのLuaだけを使って、完全にネイティブな設定ウィンドウ、ポーズメニューの行やタブ、HUDパネルのテキスト、画面上のポップアップをSF6のトレーニングモードに注入できます -- DLLパッチ不要、独自レンダリング不要、ImGui不要です。行の構築、フォーカス/ナビゲーションの処理、すべての描画（フォント、スプライト、九分割フレーム）はゲーム自身が行います。本ガイドでは、私たちが実際にリリースしたすべてのテクニック、ルールを教えてくれたすべてのクラッシュ、そしてエントリーポイントを見つけた探査ワークフローを記録しています。

| | |
|---|---|
| **読了時間** | 約45分（全体）／約15分（テクニック1-2のみ） |
| **スキルレベル** | REFramework Luaの中級者向け（`sdk.hook`、`sdk.find_type_definition`、`sdk.get_managed_singleton`を理解していること） |
| **ゲームバージョン** | Street Fighter 6、RE Engine（REFramework-Websockets build LL5271でテスト済み。メニュー系のテクニックはすべて素のREFrameworkでも動作します） |
| **最終更新日** | 2026-09-03 |

[![戦闘画面の上に表示されたネイティブウィンドウ](img/native_window_hitconfirm.png)](img/native_window_hitconfirm.png)
*ゲーム自身のOptionsダイアログUIだけで構築された「Hit Confirm」設定ウィンドウ。戦闘を一時停止した状態で、進行中の対戦画面の上に表示されている。*

---

## 目次

1.  [対象読者](#1-対象読者)
2.  [前提条件](#2-前提条件)
3.  [ゲームUIの仕組み](#3-ゲームuiの仕組み)
4.  [黄金律（クラッシュで実証済み）](#4-黄金律クラッシュで実証済み)
5.  [テクニック1 -- オプションダイアログの行 (NativeOptions)](#5-テクニック1----オプションダイアログの行-nativeoptions)
6.  [テクニック2 -- ポーズメニューの行とタブ (NativePauseMenu)](#6-テクニック2----ポーズメニューの行とタブ-nativepausemenu)
7.  [テクニック3 -- ゲームのHUDを操作する (NativeHud)](#7-テクニック3----ゲームのhudを操作する-nativehud)
8.  [テクニック4 -- GUI要素の借用 (NativePopup)](#8-テクニック4----gui要素の借用-nativepopup)
9.  [テクニック5 -- ゲームメニュー全体の再利用 (NativeShortcuts, NativeDialog)](#9-テクニック5----ゲームメニュー全体の再利用-nativeshortcuts-nativedialog)
10. [ケーススタディ -- カラーエディター](#10-ケーススタディ----カラーエディター)
11. [ケーススタディ -- Drive Impactの配色メニュー](#11-ケーススタディ----drive-impactの配色メニュー)
12. [自分でゲームメニューを解剖する](#12-自分でゲームメニューを解剖する)
13. [トラブルシューティング](#13-トラブルシューティング)
14. [付録 -- 型と列挙型リファレンス](#14-付録----型と列挙型リファレンス)
15. [クレジット](#15-クレジット)

---

## 1. 対象読者

あなたはREFrameworkのLuaモッダーで、ImGuiウィンドウやD2Dオーバーレイを**使わずに**、SF6のトレーニングモードに設定・オーバーレイ・コントロールを追加したいと考えています。自分のMODの設定画面をゲーム本来のもののように見せたいのかもしれません。ユーザーの環境によってはImGuiが不安定なのかもしれません。あるいは、コントローラーで操作できるメニューが欲しいのかもしれません。

本ガイドでは、最も実用的なもの（Optionsダイアログの行）から最も実験的なもの（ゲームの2カラムControl Settingsダイアログの乗っ取り）まで、互いに補完し合う5つのテクニックを扱います。各セクションは独立して読めるように構成されているので、必要な部分だけを読んでいただいて構いません。

**このガイドで得られるもの:**
- 戦闘画面の上に開き、アクションを一時停止し、ゲーム本来のOptionsパネル（スライダー、トグル、スピンテキスト、ボタン）とまったく同じ見た目の設定ウィンドウ。
- トレーニングのポーズメニュー内に追加できる行やタブ全体（スピン、ボタン、アクションコールバック）。
- 自分のスクリプトから操作できる、ゲーム本来のDamage / Combo Damage / Attack Typeパネルとラウンドタイマーの数字。
- 借用したGUI要素（「Match Found」のネオンフレームなど）から組み立てたポップアップフレームやテキスト。
- フックすべき新しいメニューやコントロールを発見するためのワークフロー。

---

## 2. 前提条件

### REFramework

SF6向けの比較的新しいREFrameworkビルドであれば、どれでもメニュー系のテクニック（1〜5）は動作します。[REFramework-Websockets build (LL5271)](https://github.com/praydog/REFramework)は、ポート8080でLua websocketサーバーを追加し、スクリプト経由のリモート探査（10章）を可能にしますが、UIインジェクション自体には必須ではありません。

### Luaの基礎知識

以下の内容に抵抗がないことが前提です:
- `sdk.find_type_definition`, `sdk.get_managed_singleton`, `sdk.create_instance`
- `sdk.hook(method, pre_fn, post_fn)`と`PreHookResult.SKIP_ORIGINAL`パターン
- `re.on_pre_application_entry("LateUpdateBehavior", fn)`（ゲームスレッドのコールバック）
- `re.on_frame`（レンダースレッド）とゲームスレッドの違い -- この区別は非常に重要です（ルール1）
- 永続化のための`json.load_file` / `json.dump_file`

### クラッシュログの読み方

REFramework読み込み状態でSF6がクラッシュした場合、再起動前に**2つのファイル**を確認してください（ログは再起動時に上書きされます）:
1. `reframework/re2_framework_log.txt` -- 「Exception occurred」セクションまでスクロールし、スタックトレースと例外発生アドレスを確認します。
2. `reframework/reframework_crash.dmp` -- タイムスタンプから、どのクラッシュに対応するdmpかが分かります。

---

## 3. ゲームUIの仕組み

MOD制作に関係する範囲で、ゲームのUIアーキテクチャを簡単にまとめます。ここに書かれている内容はすべて、公式ドキュメントではなく探査（10章）によって判明したものです。

### コントロールとエージェント

SF6のUIは、RE Engineの`via.gui`コントロールツリーの上に構築されています。コントロール（`via.gui.Control`とそのサブタイプ -- `Rect`、`Text`、`Scale9Grid`、`Panel`）は親子階層を形成します。各メニュー画面は、コントロールツリーを保持する**UIAgent**（`app.UIAgent`）を持っており、そのツリーには`agent.get_ControlMain()`でアクセスできます。生きているエージェントはすべて`app.UIAgentManager._Entries`に一覧されています。

トレーニングモードにおける主要なエージェント名:
| エージェント名 | 内容 |
|---|---|
| `ui11200` | トレーニングのポーズメニュー（タブ、行、フォーカス管理） |
| `OptionDialog` | Options / Settingsダイアログ（戦闘画面上、またはポーズメニューから表示される） |
| `KeyConfigBattleMenuFG` | 「Control Settings」の2カラムダイアログ |
| `BattleHud_Timer` | ラウンドタイマー（要素の借用先となる`c_main`コントロールを保持） |
| `Resident_Cmn_MatchingStandby` | マッチメイキングのポップアップ（ネオンフレームやテキストの供給元） |

### UIFlowとParam

メニュー画面は**UIFlow**（`app.UIFlowManager`）によって管理されています。フローは静的な`Start(...)`呼び出しで開始され、`IUIFlowHandle`を返します。フローは`Param`オブジェクト（その動作状態）を生成し、`Init` -> `ShowedObject` -> ユーザー操作 -> `OnEnd`という流れで画面を駆動します。フローが終了したかどうかは、ハンドルの`get_IsEnd()`で分かります。

主なフロー:
| フロークラス | Paramクラス | 駆動する内容 |
|---|---|---|
| `app.UIFlowOptionBGDialog` | `app.UIFlowOptionBGDialog.Param` | 暗い背景の「BattleHud」オプションウィンドウ（本ガイドの主軸となる手段） |
| `app.UIFlowKeyConfig.Menu` | `app.UIFlowKeyConfig.Menu.Param` | 2カラムのControl Settingsダイアログ |
| `app.UIFlowShortcutSetting` | (`app.ShortcutSetting`が管理) | Shortcut Settingsメニュー |

### UIParts

メニュー内の行は`UIParts`オブジェクト（`UIPartsSpin`、`UIPartsButton`、`UIPartsScrollList`、`UIPartsGroupScroll`）です。ゲームはプールからこれらをインスタンス化し、データオブジェクトにバインドします。UIPartsを直接生成することはほとんどなく、代わりにデータオブジェクト（`OptionSettingUnit`、`TrainingMenuData`）を作成し、パーツの構築はゲームに任せます。

### メッセージGUID（hMsg）

SF6のメニューに表示されるテキストは、すべて`app.helper.hMsg.GetMessage(Guid)`によるGUID検索から来ています。ゲームはテキストをGUIDで索引付けされたメッセージテーブルに保存しています。私たちはそのテーブルにエントリーを追加することはできないため、`GetMessage`をフックして自前の偽GUIDを横取りし、好きな文字列を返すようにします。これが本ガイドのすべてのテクニックの土台となっています。

```lua
-- Create a GUID and register its text
local guid_text = {}   -- GUID string -> our text
local function message_guid(str)
    local g = sdk.find_type_definition("System.Guid"):get_field("Empty"):get_data(nil):NewGuid()
    guid_text[g:call("ToString()")] = str
    return g
end

-- Hook the message resolver
sdk.hook(
    sdk.find_type_definition("app.helper.hMsg"):get_method("GetMessage(System.Guid)"),
    function(args)
        local s = guid_text[sdk.to_valuetype(args[2], "System.Guid"):call("ToString()")]
        if s then
            thread.get_hook_storage()[1] = s
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,
    function(retval)
        local s = thread.get_hook_storage()[1]
        if s then return sdk.to_ptr(sdk.create_managed_string(s)) end
        return retval
    end
)
```

### オブジェクトへのGUIDの書き込み

このREFrameworkビルドでは、`obj.GuidField = guid`のようなネストされた`ValueType`フィールドへの直接代入が拒否されます。16バイトの生データを直接書き込む必要があります:

```lua
local function set_guid(obj, field_name, guid)
    local off = obj:get_type_definition():get_field(field_name):get_offset_from_base()
    obj:write_qword(off, guid:read_qword(0))
    obj:write_qword(off + 8, guid:read_qword(8))
end
```

---

## 4. 黄金律（クラッシュで実証済み）

以下のルールはすべて、実際のクラッシュから学んだものです -- そのほとんどは、回復不能なエラーでゲームを落とすアクセス違反によるものでした。深刻度が高い順に並んでいます。

### ルール1: メインスレッド以外でLuaを実行しない

**症状:** 読み込みから1〜3分後、エンジンのランダムな関数で間欠的にAV（アクセス違反）が発生する。REFrameworkメニューを開いた状態だとバグが隠れてしまう（Luaの実行がシリアライズされるため）。

**原因:** ゲームの入力スレッド、UIジョブスレッド、あるいはレンダースレッドで実行されるメソッドに対する`sdk.hook`コールバック。具体的には、`InputState`のセッター、`UIWidget_TMAttackInfo.SetXText`、`UIBattleHud_Timer.UpdateBattleHud`へのフックはいずれもメインスレッド外でLuaを実行してしまい、非決定的なクラッシュを引き起こしていました（`soak.py`によるビセクトで確認: フックなしでは0/3回、フックありでは3/3回クラッシュ）。

**ルール:** すべてのGUI書き込みと、些細でないすべてのLuaコールバックは、ゲームのメインスレッド、すなわち`re.on_pre_application_entry("LateUpdateBehavior", fn)`上で行う必要があります。レンダースレッド（`re.on_frame`）での読み取り専用フックはデータ収集用途では問題ありませんが、そこから**ゲームオブジェクトへの書き込みは絶対に行わないでください**。

### ルール2: キャッシュ済みオブジェクトへの書き込み前に生存確認を行う

**症状:** 数フレーム前までは有効だった`via.gui.Text`や`via.gui.Control`に対する`set_Message`、`set_Color`、`set_Visible`でAVが発生する。

**原因:** ゲームは`PauseManager._CurrentPauseTypeBit`が変化するたび（自分のウィンドウのポーズタイプ8、実際のポーズメニュー、オプションダイアログなど）にバトルHUDを再構築します。キャッシュしていたコントロールはいずれも解放され得るうえ、`sdk.is_managed_object`は**再割り当てされた**チャンクに対して`true`を返すことがあります（8月31日の計測: ガードを入れていてもクラッシュを確認）。ポーズ/HUDの遷移中は、キャッシュ済みコントロールは単に無効になるだけでなく、そのメモリが別のオブジェクトのために再利用されている可能性があります。

**ルール:**
1. 毎回の書き込み前に`sdk.is_managed_object(control:get_address())`を呼ぶ -- ただし、これは完璧ではないことを理解しておく。
2. `TrainingGamePaused`または`NativeOptionsWindowOpen`が`true`になった瞬間に、**すべてのキャッシュ**（パネル、タイマー、テキスト）を破棄する。「最後の書き込み」を試みてはいけない -- コントロールがすでに解放されている可能性がある。
3. `_CurrentPauseTypeBit`を監視する: 変化があればすべてのキャッシュを破棄し、新しいコントロールを解決するまで20ティック待つ。
4. すべてのGUI書き込みを`pcall`で包む。保護されていないAVが1件でもあれば致命的になる。

### ルール3: 開いているダイアログページを再構築しない

**症状:** 現在表示中のダイアログページに属するユニットの`ChildUnitList`を変更した数フレーム後、UIパーツプール内でRIP 0（nullな関数ポインタの参照）が発生する。

**原因:** `SetupDispUnits`はプールからUIPartsを取り出し、データにバインドします。ページが表示されている間にデータ型を変更すると（例: スライダーをボタンに置き換えるなど）、プールが誤った型のパーツを再バインドしてしまい、次のレイアウト呼び出しがnullなvtableエントリーを経由してジャンプしてしまいます。

**ルール:** ダイアログページが開いている間は、`SetupDispUnits`を呼んだり`ChildUnitList`を変更したりしないこと。代わりに、ダイアログを`End()`し、エージェントが消えるのを待ち、データツリーを`rebuild()`してから新しいダイアログを`Start()`します。`ImmediateFade = true`（5章）を使えば、この遷移はポーズを保持したままでも見た目上は瞬時に行われます。

### ルール4: エンジンが完全な構築を期待するゲームデータオブジェクトを、中途半端に自作しない

**症状:** `SetSettingParams`または`MakeListIndexToParamIndex`内で`NullReferenceException`が発生し、続いて`UpdateListSetting`で`IndexOutOfRangeException`が発生、数フレーム後にゲームが落ちる。

**原因:** `sdk.create_instance`で`app.UIKeyConfig.SettingParam`を生成し、整数フィールドだけを埋めていた。エンジン側のメソッドは、`Name`、`Icon`、`Comment`の文字列プロパティと`GamePadButton`列挙型が完全に初期化されていることを前提としています。中途半端に構築されたparamはリスト構築時にクラッシュを引き起こします。

**ルール:** ゲーム側の型が複雑な初期化を要求する場合は、自作するのではなく既存インスタンスを**クローン**する（`CloneSettingParams`、`MemberwiseClone`）。テキストのgetterだけをフックでオーバーライドする。`NativeDialog`（9章）はこの方式で動作しています。

### ルール5: pcall(function() ... end)ではなくpcall(func, args)を使う

**症状:** メモリ使用量が徐々に増加し（1分あたり1〜3MB）、最終的にスタッターを引き起こす。

**原因:** `pcall(function() ... end)`は呼び出しのたびに新しいクロージャを確保します。ホットパス（1秒間に60回の呼び出し）では、これらのクロージャがGCによる回収よりも速く蓄積してしまいます。

**ルール:** あらかじめ定義した関数を使って`pcall(func, arg1, arg2)`とする。SF6 Toolsのコードベースでは、この方式で一度に89件のホットパスクロージャ呼び出しを修正しました。

### ルール6: io.openはreframework/data/からの相対パス、".."は絶対に使わない

**症状:** `io.open`が無言で失敗する、あるいは意図しない場所に書き込んでしまう。

**原因:** REFrameworkは`io.open`を`reframework/data/`にサンドボックス化しています。`..`を含むパスは拒否されます。`io.popen`と`os.execute`は完全にブロックされています。

**ルール:** JSONには`json.dump_file`を使う（Windowsのファイルロックを処理してくれる）。`io.open`はテキストファイル専用とし、常に`reframework/data/`からの相対パスを使う（パスに`data/`というプレフィックスを付けない）。

### ルール7: fs.globは重い -- タイマーで呼ばない

**症状:** N秒ごとに約260msのフレームタイムスパイクが発生する。

**原因:** `fs.glob`は`reframework/data/`ツリー全体（約2200ファイル）を走査します。これを定期的に呼び出す（例: ファイル一覧を更新するため）と、一定間隔でカクつきが発生します。

**ルール:** `fs.glob`はメニューが開こうとしているタイミングでのみ呼ぶ（ユーザーは一瞬の間を想定している）。結果はキャッシュする。`NativeOptions`では、`lists_changed()`のチェックと`rebuild()`はタイマーではなく`open_request`のパスで行われます。

### ルール8: GUI書き込みはLateUpdateBehaviorからのみ行う

**症状:** `re.on_frame`から呼び出した`set_Message`でAVが発生する。

**原因:** `re.on_frame`は**レンダースレッド**で実行されます。そこから`via.gui.Text.set_Message`に書き込むと、メインスレッド上で行われるゲーム自身のレイアウト処理と競合します。

**ルール:** `set_Message`、`set_Color`、`set_Visible`、`set_Position`、`set_Size` -- これらはすべて、`re.on_pre_application_entry("LateUpdateBehavior", ...)`から、あるいはメインスレッドで実行されることが分かっているメソッド（例: `TrainingManager.OpenMenu`）への`sdk.hook`コールバックから呼び出す必要があります。

### ルール9: ゲームのテキストを元データの時点で書き換えない

**症状:** トレーニングのリセット後にクラッシュする、あるいはテキストが恒久的に壊れる。

**原因:** ゲームが所有しているコントロールの`Message`フィールドを上書きすると、ゲーム自身の更新処理がこちらのテキストを読み戻し、それを元データとして扱ってしまいます。

**ルール:** 書き込みは自分が**占有権を得た**コントロールに対してのみ行い、解放するときは元のテキストに戻す。元データはディスクに保存しておく（スクリプトの再読み込みをまたいで保持される）。HUDパネルについては、「サイド」テキスト（`LeftText`、`RightText`）はウィジェットによって毎フレーム書き換えられるため、これらは非表示にしてセンターテキストのみを使うこと。

---

## 5. テクニック1 -- オプションダイアログの行 (NativeOptions)

これが主軸となるテクニックです。ゲーム自身のOptionsシステムに設定行を注入し、進行中の対戦画面の上に単独のウィンドウとして開きます。トグル、スライダー、スピンテキスト、ボタンの構築、十字キー/スティックによるナビゲーションの処理、そしてすべての描画は、ゲーム自身のスタイルで行われます。

[![Optionsメニュー内のSF6 Tools](img/options_sf6tools_submenu.png)](img/options_sf6tools_submenu.png)
*「SF6 Tools」はOptions > Generalの一番下に表示される。展開するとサブグループ（Hit Confirm、Script Manager）が現れ、それぞれが戦闘画面の上にBattleHud風のウィンドウを開く。*

[![戦闘画面上に表示されたOptionsウィンドウ](img/native_window_hitconfirm.png)](img/native_window_hitconfirm.png)
*スライダー、トグル、ボタンを備えた「Hit Confirm」ウィンドウ。一時停止した戦闘画面の上に開いている。*

### 仕組み

1. **`OptionSettingUnit`エントリーを作成**し、`app.OptionManager.UnitLists[General]`にアタッチする。ゲームのOptions画面はこのリストを読み取って「General」タブを構築する。`EventType.OpenSubMenu`を持つユニットはクリック可能なグループになり、`EventType.OpenBattleHudSetting`を持つユニットは「BattleHud」風の暗いウィンドウを開く。
2. **偽GUID経由でテキストを解決する**: すべての`TitleMessage`と`DescriptionMessage`はGUIDである。ランダムなGUIDを生成し、`hMsg.GetMessage`をフックして自前の文字列を返すようにする。
3. **ゲームのLoad/Resetをスキップする**: `OptionValueUnit.LoadValueEvent`と`ResetEvent`をフックし、自分のTypeIdについてはスキップする（ゲームは自分が所有していない値をロード/リセットしようとしてはいけない）。
4. **戦闘画面の上にウィンドウを開く**: `LateUpdateBehavior`から`UIFlowOptionBGDialog.Start(SettingData, false)`を呼ぶ。`SettingData.TopUnit`は自分のグループユニットのいずれかを指す。
5. **戦闘を一時停止する**: `PauseManager.requestPause(true, 8)`（タイプ8 = `BATTLE_MENU_PAUSE`、実際のポーズメニューが使うものと同じタイプ）。ウィンドウが閉じたら解放する。

### ステップバイステップ: 設定グループの追加

#### ステップ1: TypeIdの割り当て

すべての`OptionSettingUnit`には一意な`TypeId`が必要です。ゲームはウィジェットの種類をTypeId単位でスクリプトの再読み込みをまたいでキャッシュするため、スクリプトが読み込まれるたびに新しいIDを使う必要があります:

```lua
local next_id = nil
local function new_id()
    if not next_id then
        -- Find the highest existing TypeId in the game's ValueType enum
        local max = 0
        for _, f in ipairs(sdk.find_type_definition("app.Option.ValueType"):get_fields()) do
            if f:is_static() then
                local ok, v = pcall(f.get_data, f, nil)
                if ok and type(v) == "number" and v > max and v < 2100000000 then max = v end
            end
        end
        next_id = math.ceil((max + 1) / 10) * 10 + 100000
        next_id = next_id + (os.time() % 5000) * 100   -- fresh per load
    end
    next_id = next_id + 1
    return next_id
end
```

#### ステップ2: ユニットツリーの構築

```lua
local InputType = enum("app.Option.UnitInputType")     -- SpinText, Slider, Button_Type1, Button_Type2
local EventType = enum("app.Option.DecideEventType")   -- OpenSubMenu, OpenBattleHudSetting, SettingReset, ...
local DataType  = enum("app.Option.SettingDataType")   -- Value
local TabType   = enum("app.Option.TabType")           -- General

local mgr = sdk.get_managed_singleton("app.OptionManager")
local parent_list = mgr.UnitLists:call("get_Item", TabType.General)

-- Get empty typed lists from an existing unit (for MemberwiseClone)
local first_setting = parent_list:call("get_Item", 0):call("get_Setting")
local empty_guids    = first_setting.ValueMessageList:call("GetRange", 0, 0)
local empty_settings = first_setting.ChildUnitList:call("GetRange", 0, 0)
```

#### ステップ3: ルートグループの作成

```lua
local function new_setting()
    local d = sdk.create_instance("app.Option.OptionSettingUnit")
    d.TypeId = new_id()
    return d
end

local function make_unit(desc, description, value_messages)
    local unit = desc:call("MakeUnitData")
    local s = unit:call("get_Setting")
    set_guid(s, "DescriptionMessage", message_guid(description or ""))
    s.ValueMessageList = empty_guids:call("MemberwiseClone")
    s.ChildUnitList    = empty_settings:call("MemberwiseClone")
    for _, msg in ipairs(value_messages or {}) do
        s.ValueMessageList:call("Add", message_guid(msg))
    end
    return unit
end

-- Root: "My Mod" -> opens a sub-menu
local root_desc = new_setting()
set_guid(root_desc, "TitleMessage", message_guid("My Mod"))
root_desc.InputType = InputType.Button_Type1
root_desc.EventType = EventType.OpenSubMenu
local root_unit = make_unit(root_desc, "Settings for My Mod.")
parent_list:call("Add", root_unit)
```

#### ステップ4: 設定サブグループの追加（ウィンドウを開く）

```lua
local group_desc = new_setting()
set_guid(group_desc, "TitleMessage", message_guid("My Settings"))
group_desc.InputType = InputType.Button_Type1
group_desc.EventType = EventType.OpenBattleHudSetting   -- opens a window over the fight
local group_unit = make_unit(group_desc, "Adjust my mod's parameters.")

-- Attach to root
local function attach(parent, child)
    parent:call("get_ChildUnits"):call("Add", child)
    parent:call("get_Setting").ChildUnitList:call("Add", child:call("get_Setting"))
end
attach(root_unit, group_unit)
```

#### ステップ5: トグルの追加（Off/OnのSpinText）

```lua
local toggle_desc = new_setting()
set_guid(toggle_desc, "TitleMessage", message_guid("Enable Feature"))
toggle_desc._DataType   = DataType.Value
toggle_desc.InputType   = InputType.SpinText
local toggle_type_id = toggle_desc.TypeId

local toggle_unit = make_unit(toggle_desc, "Turn the feature on or off.", {"Off", "On"})
attach(group_unit, toggle_unit)

-- Value setting (min/max/initial)
local vs = sdk.create_instance("app.Option.OptionValueSetting")
vs.TypeId = toggle_type_id
vs.MinValue = 0; vs.MaxValue = 1; vs.InitValue = 1   -- default "On"
toggle_unit:call("set_PrevValue", 1)
toggle_unit:call("set_ValueSetting", vs)
toggle_unit.ValueData = vs:call("MakeValueData")
```

#### ステップ6: スライダーの追加

```lua
local slider_desc = new_setting()
set_guid(slider_desc, "TitleMessage", message_guid("Block Rate"))
slider_desc._DataType = DataType.Value
slider_desc.InputType = InputType.Slider

local slider_unit = make_unit(slider_desc, "Chance (%) that the dummy blocks.")
attach(group_unit, slider_unit)

local svs = sdk.create_instance("app.Option.OptionValueSetting")
svs.TypeId = slider_desc.TypeId
svs.MinValue = 0; svs.MaxValue = 100; svs.InitValue = 50
slider_unit:call("set_PrevValue", 50)
slider_unit:call("set_ValueSetting", svs)
slider_unit.ValueData = svs:call("MakeValueData")
```

#### ステップ7: ボタンの追加（Restore行パターン）

ボタンは`InputType.Button_Type2`と`EventType.SettingReset`を使います -- これはゲームの「Restore Default Settings」行とまったく同じパターンです。これは横幅いっぱいの中央揃えボタンとして描画されます。

```lua
local btn_desc = new_setting()
set_guid(btn_desc, "TitleMessage", message_guid("START SESSION"))
btn_desc.InputType = InputType.Button_Type2
btn_desc.EventType = EventType.SettingReset
local btn_unit = make_unit(btn_desc, "Start the training session.")
attach(group_unit, btn_unit)
```

> **メモ:** `Button_Type1`はフォーカス時にタイトルを左揃えで描画します（サブメニューへのナビゲーションに使用）。`Button_Type2`はタイトルを常に中央揃えのままにします（アクションボタンに使用）。設定ウィンドウ内のボタンには常に`Type2`を使ってください。

ボタン押下を処理するには、`Param.GetFocusDecideEventType`と`Param.FlowEvent_ResetCurrentUnits`をフックします:

```lua
local bg_param_td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")

-- Intercept the decide: return Invalid (0) for our buttons so no "Revert?" popup appears
sdk.hook(bg_param_td:get_method("GetFocusDecideEventType"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    if (sdk.to_int64(rv) & 0xFF) == 1 then   -- SettingReset
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local u = param:call("GetFocusUnit")
        local tid = u and u:call("get_Setting").TypeId
        if tid == btn_desc.TypeId then
            -- Queue your callback here
            my_button_callback()
            return sdk.to_ptr(0)   -- DecideEventType.Invalid: no popup
        end
    end
    return rv
end)
```

#### ステップ8: 自分のIDについてLoad/Resetをスキップする

```lua
local known_ids = { [toggle_type_id] = true, [slider_desc.TypeId] = true, [btn_desc.TypeId] = true }

local function skip_ours(args)
    local ok, id = pcall(function()
        return sdk.to_managed_object(args[2]):call("get_Setting").TypeId
    end)
    if ok and known_ids[id] then return sdk.PreHookResult.SKIP_ORIGINAL end
end

local vu = sdk.find_type_definition("app.Option.OptionValueUnit")
sdk.hook(vu:get_method("LoadValueEvent"), skip_ours)
sdk.hook(vu:get_method("ResetEvent"), skip_ours)
```

#### ステップ9: 戦闘画面の上にウィンドウを開く

```lua
local dialog_handle = nil

local function open_window()
    -- Close any existing dialog first (they stack)
    if dialog_handle then
        pcall(function()
            if not dialog_handle:call("get_IsEnd") then dialog_handle:call("End") end
        end)
    end

    local sd = sdk.create_instance("app.UIFlowOptionBGDialog.SettingData")
    sd.TopUnit = group_unit
    sd.SupportMode = 32
    sd.UseBattleHudBG = false
    sd.PlayerIndex = 0

    local m = sdk.find_type_definition("app.UIFlowOptionBGDialog")
        :get_method("Start(app.UIFlowOptionBGDialog.SettingData, System.Boolean)")
    dialog_handle = m:call(nil, sd, false)
end
```

ホットキーが押されたとき、あるいはポーズメニューのボタンが押されたときに、`LateUpdateBehavior`から`open_window()`を呼びます。**`re.on_frame`から呼んではいけません**（ルール8）。

#### ステップ10: 戦闘の一時停止

```lua
local PAUSE_TYPE = 8   -- BATTLE_MENU_PAUSE
local pause_held = false

local function hold_pause(on)
    if on == pause_held then return end
    local mgr = sdk.get_managed_singleton("app.PauseManager")
    if mgr and pcall(function() mgr:call("requestPause", on, PAUSE_TYPE) end) then
        pause_held = on
    end
end
```

`open_window()`の直後に`hold_pause(true)`を呼びます。ダイアログが閉じたとき（`dialog_handle:call("get_IsEnd")`、または`OptionDialog`エージェントの消失で検出）には`hold_pause(false)`を呼びます。

#### ステップ11: クローズの検出

`LateUpdateBehavior`から約10ティックごとにポーリングします:

```lua
if dialog_handle then
    local ended = pcall(function() return dialog_handle:call("get_IsEnd") end)
        and dialog_handle:call("get_IsEnd")
    if ended then
        dialog_handle = nil
        hold_pause(false)
    end
end
```

#### ステップ12: 値の変化をポーリングする

```lua
-- In LateUpdateBehavior, every ~10 ticks:
local ok, n = pcall(function() return toggle_unit:call("get_Value") end)
if ok and n ~= last_toggle_value then
    last_toggle_value = n
    local is_on = (n ~= 0)
    -- Act on the change
end
```

### ポーズメニューとの排他制御

ウィンドウを閉じるEsc/Startボタンは、`TrainingManager.OpenMenu`経由でトレーニングのポーズメニューにも届いてしまいます。ウィンドウが開いている間（およびその後約20フレーム）はスキップするようフックします:

```lua
local tm_td = sdk.find_type_definition("app.training.TrainingManager")
local open_menu = tm_td:get_method("OpenMenu(app.training.TrainingManager.MenuType, app.training.BaseParam)")
sdk.hook(open_menu, function(args)
    if my_window_open or (tick - closed_tick) < 20 then
        return sdk.PreHookResult.SKIP_ORIGINAL
    end
end, function(rv) return rv end)
```

### 画面フェードのスキップ（ImmediateFade）

ダイアログを閉じて再度開く場合（例: モード変更後に内容を更新するため）、デフォルトの遷移には画面フェードが含まれます。ポーズを保持したままだと、そのフェードはフリーズしてしまいます（フェードアニメーションにはポーズされていないフレームが必要なため）。これをスキップするには:

```lua
sdk.hook(bg_param_td:get_method("CreatedObject"), function(args)
    if my_window_open then
        pcall(function()
            local param = sdk.to_managed_object(args[2])
            param:set_field("<ImmediateFade>k__BackingField", true)
        end)
    end
end, function(rv) return rv end)
```

### ゲームの「Restore Default Settings」行を隠す

ウィンドウを開くと、ゲームは自動的に「Restore Default Settings」行を追加します。自分のページ（何もリセットする対象がない）ではこれを隠します:

```lua
sdk.hook(bg_param_td:get_method("SetupDispUnits"), function(args)
    thread.get_hook_storage()["param"] = args[2]
end, function(rv)
    pcall(function()
        local param = sdk.to_managed_object(thread.get_hook_storage()["param"])
        local parts = param:get_field("OptionUnits")
        if not parts then return end
        local ours = false
        local reset_parts = {}
        for i = 0, parts:call("get_Length") - 1 do
            local part = parts:call("GetValue", i)
            local ud = part and part:get_field("UnitData")
            if ud then
                local s = ud:call("get_Setting")
                if known_ids[s.TypeId] then
                    ours = true
                elseif s.EventType == 1 then   -- SettingReset (the game's own)
                    reset_parts[#reset_parts + 1] = part
                end
            end
        end
        if ours then
            for _, part in ipairs(reset_parts) do
                local c = part:call("get_Control")
                if c then c:call("set_ForceInvisible", true) end
                pcall(function() part:call("SetDisable", true) end)
            end
        end
    end)
    return rv
end)
```

### 動的リストと再読み込み

オプションにファイル一覧（例: 録画スロット）が含まれる場合は、ウィンドウが開こうとしているときにのみ再読み込みしてください -- タイマーでは絶対に行いません（ルール7）。パターンは以下の通りです:

1. 開く前に、`options_fn`（リストを返す関数）に変化がないかを確認する。
2. 変化があれば、ユニットツリーを解体し（`parent_list:Remove(root_unit)`）、再構築する。
3. 新しいウィンドウを開く。

### スクリプトリセット時のクリーンアップ

```lua
re.on_script_reset(function()
    if root_unit and parent_list then
        pcall(function() parent_list:call("Remove", root_unit) end)
    end
end)
```

### NativeOptions APIリファレンス

`NativeOptions.lua`モジュールは、これまでの内容をすべて簡潔なAPIとしてラップしています:

| 関数 | 説明 |
|---|---|
| `Opt.group(title, desc, {mode=id, key=key})` | 名前付きの設定グループを作成する。`mode`はトレーナーモードIDに紐づく。 |
| `g:toggle(key, title, desc, default, cb, opts)` | 真偽値のトグル（Off/Onのスピン）。変化時に`cb(value)`が発火する。 |
| `g:choice(key, title, desc, options, default, cb, opts)` | 名前付きの選択肢を持つスピン。`default`と`cb`の値は1始まり。`options`は関数でもよい。 |
| `g:slider(key, title, desc, min, max, default, cb, opts)` | 整数値スライダー。 |
| `g:button(key, title, desc, cb, refresh)` | アクションボタン。`cb()`が`"close"`を返すとウィンドウを閉じる。`refresh=true`にすると押下後にウィンドウを再構築する（動的なタイトル用）。 |
| `g:get(key)` / `g:set(key, v)` | エントリーの値をプログラムから読み書きする。 |
| `Opt.open(title)` | 指定した名前のグループのウィンドウを、戦闘画面の上に開く（ポーズしていない場合）。 |
| `Opt.open_after_unpause(title)` | 戦闘が5ティック安定して復帰するのを待ってから開く処理をキューに入れる。 |
| `Opt.close()` | 現在のウィンドウを閉じる。 |
| `Opt.set_mode_selector(names, ids, get, set)` | 複合ウィンドウ「SF6 Tools」の先頭に「Training mode」スピンを設置する。 |
| `Opt.rebuild()` | ユニットツリーを解体して再構築する（動的なコンテンツ用）。 |
| `Opt.message_guid(str)` | `str`に解決される偽GUIDを作成する（他のモジュールからも再利用可能）。 |

エントリー用のオプション（`opts`テーブル）:
- `deferred = true` -- ウィンドウが閉じて戦闘が再開した後にのみコールバックが発火する（録画インポートのような重い処理向け）。
- `getter = function()` -- ウィンドウが開くときに呼ばれ、外部の状態からエントリーの値を更新する。

---

## 6. テクニック2 -- ポーズメニューの行とタブ (NativePauseMenu)

トレーニングのポーズメニューにある「Basic Settings」タブに行を注入し、まったく新しいタブを追加します。

[![行が注入されたポーズメニュー](img/pause_menu_injected_row.png)](img/pause_menu_injected_row.png)
*Basic Settingsの一番下にある「SF6 Tools Shortcut Settings」行とスクロールインジケーター。上部には追加のタブドットが見える（自分たちの「SF6 Tools」タブ）。*

### 仕組み

トレーニングのポーズメニューは`TrainingManager._UIData._MenuData`、すなわち`TrainingMenuData[8]`配列（タブごとに1要素）によって駆動されています。各タブの行は`_ChildData`（静的）と`DynamicChildData`（動的、実行時に追加）に格納されています。ゲームは行を追加するための`AddDynamicMenu(funcType, data, action)`を提供しています。

自分たちの行は`FuncType = 345`（自分たちで選んだ`DYNAMIC`の値。ゲーム自身のタブは1〜8を使う）を使用します。ゲームは`TrainingMenuFunc`のメソッドを呼び出して、これらの描画とやり取りを行います:

| メソッド | タイミング | 行う内容 |
|---|---|---|
| `ViewUpdate(param, data, i)` | 毎フレーム、行ごとに | 現在処理中の自分の行を記憶する（`current = item`） |
| `GetIsActive(ftype)` | 行ごとに | `1`（アクティブ）を返す |
| `GetOptionText(ftype)` | スピン行ごとに | 現在の選択肢のテキストを返す |
| `GetOptionIndex(ftype, wanted, ftype)` | スピン変化時 | `item.set(wanted)`を呼び、`wanted`を返す |
| `Function(ftype, param, viewData, value)` | 確定/決定時 | ボタンの場合: `item.on_decide()`を呼び、0（そのまま）または1（メニューを閉じる）を返す |

行は`_MessageID`のGUIDを介して`TrainingMenuData`のアドレスで識別されます（`AddDynamicMenu`はデータをクローンするため、元のアドレスは失われてしまうからです）。

### スピン行の追加

```lua
local PM = require("func/NativePauseMenu")

PM.spin(
    "Training mode",                           -- title
    "Which training script drives the dummy.", -- guide text (bottom of screen)
    { "DISABLED", "HIT CONFIRM", "REACTION DRILLS" },  -- options
    function() return current_mode_index end,  -- getter (0-based)
    function(i) set_mode(i) end                -- setter (0-based)
)
```

### ボタン行の追加

```lua
PM.button(
    "SF6 Tools Shortcut Settings",
    "Open the shortcut configuration menu.",
    function() NativeShortcuts.open() end,   -- on_decide
    true,   -- keep_open: the pause menu stays up
    true    -- in_tab: also appears in our "SF6 Tools" tab
)
```

### タブ（ページ）全体の追加

```lua
local pg = PM.page("Distance Viewer", "Distance Viewer settings.")

pg:toggle("Display P1", "Show P1 distance overlay.",
    function() return config.p1_enabled end,
    function(v) config.p1_enabled = v; save() end)

pg:spin("Red Zone", "Attack used for the red zone.",
    function() return get_move_names() end,   -- options (function = dynamic list)
    function() return selected_move_index end,
    function(i) select_move(i) end,
    20)  -- capacity: max option count (row built once, options filled live)

pg:button("TELEPORT", "Move both players to this distance.",
    function() teleport() end,
    false)  -- keep_open = false: closes the pause menu after the action

pg:value("Distance", "Current distance between players.",
    function() return string.format("%.1f", current_distance) end)

pg:label("Press L1+R1 to toggle overlay.", "Keyboard: F5.")
```

### タブのインストール

タブは、`_MenuData`をより長い配列（ゲーム本来の8個+自分たちのタブ）に置き換えることでインストールされます。自分たちの各タブは、`_FuncType = 345`と自分たちの行オブジェクトからなる`_ChildData`を持つ`TrainingMenuData`です。タブストリップへの描画、ページドットの表示、フォーカス/ナビゲーションの処理はすべてゲームが行います。

インストールはメニューが**閉じている**状態で行います（ルール3）。`NativePauseMenu`は60ティックごとに`tabs_present`をチェックし、ゲームがメニューデータを再構築した場合（キャラクター変更など）には再インストールします。

### 14行目のスクロールバグ

Basic Settingsタブには標準で13行あります。1行追加すると14行になり、これはスクロールビューの一番下に**ちょうど**到達します（`_ViewTop 37.5 + _ViewSize.h 805 = 842.5 = 13行目の下端`）。しかし、実際の表示マスクはそれより20px高い位置にあるため、ゲームは決してスクロールせず、最後の行が見切れてしまいます。

**修正方法:** ポーズ中に`UIPartsGroupScroll`（`ui11200`エージェントのルートアイテム）へ`_ViewSize.h = 745`を書き込みます。ビュー内の行が1つ減ることで、ゲーム自身の`ScrollFocusItem`がそこまでスクロールしてくれます。13行のタブはそれでも収まります（等しい場合=表示される）。

```lua
-- In LateUpdateBehavior, while paused:
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    if go and tostring(go:call("get_Name")) == "ui11200" then
        local root = agent:get_field("_RootItem")
        if root then
            local off = root:get_type_definition():get_field("_ViewSize"):get_offset_from_base()
            if root:read_float(off + 4) > 745 then
                root:write_float(off + 4, 745)
            end
        end
        break
    end
end
```

### 動的なタイトル

**関数**として与えられたタイトルやガイドテキストは、`TrainingManager.OpenMenu`（ポーズメニューの唯一のエントリーポイントで、ゲームスレッド上で実行される）へのプリフックの中で再評価されます。その後、hMsgフックがGUIDを最新のテキストに解決します。

### NativePauseMenu APIリファレンス

| 関数 | 説明 |
|---|---|
| `PM.spin(title, guide, options, get, set)` | Basic Settingsにスピン行を追加する。`get`/`set`は0始まり。 |
| `PM.button(title, guide, on_decide, keep_open, in_tab)` | ボタン行を追加する。`in_tab=true`にすると「SF6 Tools」タブにも複製される。 |
| `PM.page(title, guide, opts)` | 新しいタブページを作成する。`Page`オブジェクトを返す。`opts.tab=false`の場合はコンテナのみで、タブはインストールされない。 |
| `pg:spin(title, guide, options, get, set, capacity)` | ページ上のスピン行。`options`は関数でもよい。 |
| `pg:toggle(title, guide, get, set)` | ページ上のOff/Onトグル。 |
| `pg:number(title, guide, min, max, step, get, set, fmt)` | 離散ステップを持つ数値行。 |
| `pg:button(title, guide, on_decide, keep_open)` | ページ上のボタン行。 |
| `pg:value(title, guide, fn)` | テキストが`fn()`から得られる読み取り専用行。 |
| `pg:label(title, guide)` | 静的なテキスト行。 |
| `PM.tab_button(title, guide, on_decide, keep_open)` | 「SF6 Tools」タブにのみ表示されるボタン。 |

### 制限

- **行プール:** ゲームはタブごとに約20個のUIPartsを生成します。プールが扱える数を超える行は描画されません。ページは**13行以下**に抑えてください（ゲーム自身のタブも13行を超えることはありません）。
- **タブストリップ:** ゲームのタブストリップは見た目上8タブ用に設計されています。1〜2個の追加は問題なく動作します（ドット、フォーカス、ナビゲーションすべて機能します）が、追加が約3個を超えるとストリップが窮屈になる可能性があります。

---

## 7. テクニック3 -- ゲームのHUDを操作する (NativeHud)

トレーニングHUDの「Damage / Combo Damage / Attack Type」パネルのテキストと、ラウンドタイマーの数字を、ゲーム自身のフォント・スプライト・レイアウトを使いながら、自分のコンテンツに置き換えます。

[![ネイティブHUDパネル](img/native_hud_panel.png)](img/native_hud_panel.png)
*「Damage」「Combo Damage」「Attack Type」のラベルを表示するネイティブなダメージパネル（画面上部中央）を備えたトレーニングHUD。ラウンドタイマーはネイティブの数字スプライトで「99」を表示している。*

### ダメージパネル

ウィジェット`app.training.UIWidget_TMAttackInfo`（`TrainingManager._ViewUIWigetDict`経由で見つかる）は、3行分の`AttackInfos`配列を持っています。各行には`LeftText`、`CenterText`、`RightText`（いずれも`via.gui.Text`コントロール）があります。

**重要な発見:** ゲームは**サイド**のテキスト（`LeftText`、`RightText`）を毎フレーム書き換えます。これに逆らうことはできません。代わりに、サイドテキストを**非表示**にし（`set_Visible(false)`）、**センター**テキストのみに書き込みます -- こちらはヒット/ガードイベント時にのみゲームが触れるためです（そのため、次のティックで自分のテキストを再度アサートします）。

```lua
local NativeHud = require("func/NativeHud")

-- Take ownership
NativeHud.claim("my_mod")

-- Write three rows (l/c/r parts are joined into the centre text with spacing)
NativeHud.set(0, "l", "SCORE: 3")
NativeHud.set(0, "c", "HIT CONFIRM")
NativeHud.set(0, "r", "TOTAL: 10")
NativeHud.set(0, "c", nil, 0xFF00FF00)   -- green colour (ABGR)

NativeHud.set(1, "l", "HIT: 80%")
NativeHud.set(1, "r", "BLOCK: 20%")

NativeHud.set(2, "c", "WAITING")

-- Give it back when done
NativeHud.release("my_mod")
```

### ラウンドタイマー

`app.UIBattleHud_Timer`は、`set_UVPatternNo(digit)`で駆動される数字スプライトのコントロール（`e_texture_number_001`、`010`、`100`）を持っています。無限マークは`c_infinite`です（数字を自分で駆動している間は`set_ForceInvisible`で非表示にします）。

```lua
NativeHud.set_timer(29, 0xFF0000FF)   -- show "29" in red
NativeHud.set_timer(nil)               -- give the timer back
```

100以上の数値では、モジュールがスプライトの位置とスケールを調整します（ゲームは通常2桁しか使わないため）。

### 重要な安全対策（4つのAVルール）

以下の4つのルールは、それぞれ8月30〜31日にビセクトで特定されたクラッシュに対応しています:

1. **ポーズ中はGUI書き込みを行わない** -- `TrainingGamePaused`または`NativeOptionsWindowOpen`が`true`になったら、静かにすべてのキャッシュを破棄する。「最後の書き込み」を試みてはいけない。
2. **テキストの復元は`OpenMenu`のプリフックでのみ行う** -- ここが、その後に続く解体処理の前で、HUDコントロールの生存が保証されている唯一のタイミングである。
3. **`_CurrentPauseTypeBit`を監視する** -- 変化があればHUDの再構築がトリガーされる。すべてのキャッシュを破棄し、20ティック待つ。
4. **`sdk.is_managed_object`だけでは不十分** -- 再割り当てされたメモリチャンクに対しても通ってしまう。GUI書き込みは常に`pcall`で包むこと。

### NativeHud APIリファレンス

| 関数 | 説明 |
|---|---|
| `NativeHud.claim(name)` | HUDを占有する。一度に1つの所有者のみ。 |
| `NativeHud.release(name)` | すべてを返却する（元のテキストが復元される）。 |
| `NativeHud.set(row, col, text, color)` | テキスト/色を設定する。`row`は0〜2、`col`は"l"/"c"/"r"、`color`はABGR。 |
| `NativeHud.clear()` | 保留中のテキストをすべてクリアする。 |
| `NativeHud.set_timer(n, color)` | タイマーの数字を駆動する（0〜999）。`nil`でゲームのタイマーに戻す。 |
| `NativeHud.request_text_visible(bool)` | パネルテキストの表示/非表示を切り替える（HUDを使わないモード向け）。 |
| `NativeHud.available()` | パネルのコントロールが解決済みのときに`true`。 |

---

## 8. テクニック4 -- GUI要素の借用 (NativePopup)

ゲーム自身の`via.gui`要素から、何も新規作成することなく、画面上のポップアップ・バー・フレームを組み立てます。このテクニックは、NativeTopBar（上部に並ぶモードボタン）、NativeBottomBar（下部のアクションボタン、現在は無効化）、NativePopup（通知フレーム）で使われています。

[![借用要素によるポップアップ](img/borrowed_popup.png)](img/borrowed_popup.png)
*借用したGUI要素から組み立てたポップアップ: 「Match Found」のネオンフレーム（Scale9Grid）、暗いRectの本体、そして休眠中のエージェントから取ったテキスト要素。*

### なぜ要素を新規作成しないのか?

- `sdk.create_instance("via.gui.Text")`は正しい親・ルートの下で描画されるが、**スクリプトリセットを生き延びられない**（REFrameworkが管理下のインスタンスを解放してしまい、ダングリングな子要素が残って`set_Message`でクラッシュする）。
- `Panel:call("create_instance", ...)`や`control:call("duplicate")`はLuaからでは描画されない（エンジンが要求する登録ステップをこちらからトリガーできないため）。
- 描画に必要な内部状態をすべて備えているのは、**エンジン自身が構築した**要素（プレハブから、エージェント初期化時に）のみである。

### 手順

1. **エンジンが構築したものの、自分のゲームモードでは表示されない予備の要素を探す**。常駐マッチメイキングエージェント（`Resident_Cmn_MatchingStandby`、`Resident_Cmn_MatchingSelect`など）には、ロード済みだがFighting Groundでは非表示な子要素（Battle Hubスキン、オンライン待機スキン）が存在する。
2. **見た目を可視のソースからコピーする**: `source:call("copyProperties", spare)`。これにより、九分割アトラス、フォントスロット、グロー設定、色設定がコピーされる。
   > **警告:** 方向は`ソース -> ターゲット`である（ソースのプロパティが予備要素に**上書きコピー**される）。これを逆にすると、無言でソースが破損する。
3. **生きているホストの下に付け替える**: `host:call("addChild", spare)`。ホストは可視であり、レンダーツリーに属している必要がある。`BattleHud_Timer`の`c_main`は良い選択肢である（トレーニングモードでは常に存在し、フォントスロット8が利用可能）。
4. **位置・サイズ・色・優先度を駆動する**のは`LateUpdateBehavior`から。

### 何ができて、何ができないか

| 操作 | 結果 |
|---|---|
| 一方のエージェントから他方へRectを`addChild`する | 動作する（他の場所で既に子になっていない場合。必要なら`remove()` + `addChild`） |
| Textを`addChild`する | **一度だけ**動作する。Textに対する`remove()`はフォント登録を恒久的に失わせる -- 空白の矩形になってしまう。Textの移動は一度だけにすること。 |
| Scale9Gridを`addChild`する | 動作する。`remove()`はアトラスを失わせる。移動は一度だけ。 |
| Scale9Grid -> Scale9Gridの`copyProperties` | 動作する。九分割アトラス、境界矩形、描画モードをコピーする。 |
| Text -> Textの`copyProperties` | 動作する。フォントスロット、アウトライン、グロー設定をコピーする。 |
| `MaskType = 0`の設定 | 必須。借用したコントロールは元の親からマスクを引き継いでいる場合があり、それがホスト全体をクリップしてしまう。 |
| `ControlPoint = 5`の設定 | 中央アンカー（位置決めが簡単になる）。 |

### ボトムバーの失敗と教訓

NativeBottomBar（画面下部のアクションボタン）は実装され、動作もしましたが、**無効化されています**（有効にするには`NativeBottomBar_Experimental = true`）。問題点は以下の通りです:

1. **テキストプールが小さすぎる。** すべての常駐エージェントを合わせても、`set_Message`でクラッシュせずに借用に耐えられるTextは約4個しかない。ボトムバーはボタンごとに1つのテキストを必要とする。
2. **テキストが元のウィジェットによって書き換えられてしまう。** `BattleHud_HitCount/e_txt_score`は借用後も問題なく描画されるが、`set_Message`はAVを投げる。`BattleHud_MatchWonNumber`のテキストはコンボ中に上書きされる（回避策: 60ティックごとにラベルを再アサートする）。
3. **スクリプトリセットでsdk.create_instanceのテキストが解放されてしまう。** `add_ref()`を使っていても、エンジンのGCまたはREFrameworkのクリーンアップによって生成済みのテキストインスタンスが解放され、ホストの下にダングリングな子要素が残ってしまう。

**教訓:** 借用要素によるUIは、小規模な部品（1〜3行のポップアップ、固定ラベルのトップバーなど）には有効ですが、動的なマルチボタンバーにはスケールしません。設定用のUIには、代わりにテクニック1と2を使ってください。

---

## 9. テクニック5 -- ゲームメニュー全体の再利用 (NativeShortcuts, NativeDialog)

### A. Shortcut Settingsメニューの差し替え (NativeShortcuts)

ゲームのShortcut Settingsメニュー（`app.ShortcutSetting`）は、2つのデータリスト、`_SettingUserData.Data`（定義）と`SettingSaveData.ItemDataList`（状態）からコントローラー/キーボードのバインディングを表示します。メニューが開いている間、この両方のリストを自分のものに**差し替える**ことで、自分の行を持つ、完全に機能するキーバインドメニューが得られます。

**仕組み:**
1. 自分たちのアクション用に`ShortcutSettingData`と`ShortcutSettingItemSaveData`の配列を構築する。
2. `ShortcutSetting.Start(0)`の前に、エンジンのリストを自分たちのものに差し替える。
3. 差し替えている間は`ShortcutSaveData.Save`と`ShortcutSetting.Save`をブロックする（ゲームが自分たちの行を本物のショートカットとして永続化してはいけない）。
4. メニューが閉じたら（`get_IsOpening() == false`）、元のリストを復元し、バインディングを自分たちのホットキーフレームワークに反映する。

### B. 2カラムダイアログの乗っ取り (NativeDialog)

> **ステータス:** 実装済みで動作もするが、NativeOptionsウィンドウ（テクニック1）を採用したため**プロジェクトとしては不採用**となった。テクニックとその落とし穴の参考として、ここに記録している。`NativeDialog.lua`はリポジトリ内に未使用のまま残っている。

「P1 Control Settings」ダイアログ（`app.UIFlowKeyConfig.Menu`）は、左側にカテゴリースピン、右側にスクロール可能な行のリストを持っています。自分たちのダイアログがアクティブな間に`Param`のメソッドをフックすることで、自分たちのカテゴリーと行を表示させることができます。

**重要な教訓 -- ルール4の実例:** 最初のバージョンでは、`sdk.create_instance`で`SettingParam`インスタンスを作成し、整数フィールドだけを埋めていました。エンジンの`MakeListIndexToParamIndex`が`Name`（文字列プロパティ）を読もうとしてnullを取得し、`NullReferenceException`を投げてしまいました。修正方法: ゲーム自身の配列を`Param.CloneSettingParams(sourceArray)`で**クローン**し、テキストのgetter（`GetName`、`GetIcon`、`GetInputIcon`、`GetComment`）だけをフックでオーバーライドする。

**主要なフック:**
- `GetBattleSettingParams`（ポストフック）: ゲームの配列をクローン元として捕捉し、現在のカテゴリー用のクローンを返す。
- `SpinPresetChanged`（プリフック、SKIP）: 自分たちのカテゴリーを設定し、`SetSettingParams(clone)`、`UpdateListSetting()`、`UpdateTextSpinPreset()`を呼ぶ。
- `SettingParam.GetName/GetIcon/GetInputIcon/GetComment`: マッピング済みの行には自分たちのテキストを、マッピングされていないクローンのスロットには`""`を返す。
- `UIAgent.InputDecide`: 右カラムのリストでの確定操作を横取りする。スピン項目の場合: 次の選択肢へ切り替える。ボタンの場合: アクションを実行する。
- アクティブな間は、すべての永続化処理（`SaveSettingParams`、`SaveOther`、`RevertSettings`など）と変更検出（`CheckChanges` -> 0、`EqualSettings` -> true）をブロックする。

**テクニック1ではなくこちらを使うべき場面:** 本当に2カラムレイアウト（左にカテゴリー、右に項目）が必要な場合に限られます。ほとんどの設定用途では、テクニック1の方がシンプルで信頼性も高くなります。

---

## 10. ケーススタディ -- カラーエディター

テクニック1（NativeOptions）を、実践投入レベルの本格的な設定UIにまで押し上げた実例です。ゲーム自身のEdit Character画面から直接開く、キャラクターコスチュームのスロットごとのHSVカラー・マテリアルエディターです。上のテクニック1がメカニズムを示したのに対し、このセクションはそれがどこまでスケールするかを示します。

### 開き方

Edit Character画面（Fighter Settings）では、Colorの行の下部ガイドに「Edit Color」のヒントが表示されます。F（キーボード）/ A（パッド）を押すか、行を左クリックすると開きます。エディターにはQUICK EDIT、EDIT COLORS、EDIT MATERIALS、EDIT SQUARES、SAVE、SAVE AS、RESETの7ページ（「MC」カラーを選択している場合はRESET / ERASE）があります。ページ切り替えはA / E（L1 / R1）、またはタイトル横の矢印をクリックします。

### スライダーと数値

スライダーはRGBではなくHSV -- Hue、Saturation、Brightnessで、それぞれ0-255スケールです（Hueの0-255は0-360度に対応）。マテリアルはBlend / Rough / Metalで、それぞれ0-1000です。Backspace（R3）はフォーカス中の行を**保存済みの**値に戻します（デフォルト値ではありません）。C / V（Square / Triangle）は行の数値をコピー・ペーストします。

### 未保存インジケーター

行の左上に赤い点が表示されている場合、その下のツリー内のどこかが保存済みの状態と異なっていることを意味します -- まず変更されたスライダー自体、次にそのクラスター、そしてルートの行、という順で表示されるため、未保存の変更がどこにあるか常に一目でわかります。SAVEすると消えるか、値を保存済みの位置に戻した瞬間に消えます。

### Save / Save As / Reset / Erase

SAVEは現在の値を書き込み、ウィンドウは開いたままでタイトルが確認として「SAVE OK!」に変わります。SAVE AS は新しい「MC n」スロットを作成し、そのスロットでエディターを再度開きます。RESET は初期状態 -- ゲーム本来のカラー、またはインストール済みのカラーパック -- に戻すか、「MC」カラーの場合は直近のSAVEに戻します。ERASEは「MC」スロットを完全に削除します。

### クイック編集

カラーファミリーごとに絶対Hueスライダーが1つあります。ゲーム本来のコスチュームクラスターは7つのファミリーにグループ化され、それぞれ最大のクラスターにちなんで名付けられています: SKIN、HAIR、FACE、そしてアウトフィット固有のクラスターです。各行の下にあるガイド行が、そのスライダーが実際に動かすクラスターを正確に示します（「Changes: ...」）。

### テクスチャスロット

一部のスロットは、現在表示しているカラーではテクスチャのままですが、ゲームは同じコスチュームの別のカラーではそのスロットにフラットカラーを使うことがあります。そうしたスロットはスロット一覧で「(texture)」と表示されます。スライダーを動かすとそのスロット専用のカラーが割り当てられます（Backspaceでテクスチャに戻ります）。Generate Randomはテクスチャスロットにも作用します。

### カラーリスト

ゲーム本来の番号付きカラーに加えて、リストには以下が含まれることがあります: **RW n** -- モッダーが`data/SF6_ColorSpinExtra_data/colors/<Fighter>/`に配置するカラーパック、**MC n** -- 自分で保存したカラー、そして3つの巡回エントリ: **LL1** -- 服とアクセサリーだけがランダムに巡回（髪・肌・顔はそのまま）、**LL2** -- 服・アクセサリー・髪（眉・ひげ含む）、**LL3** -- すべて。

### プレビューカメラ

エディターが開いている間、プレビューカメラは自由に操作できます: 左ドラッグで回転、中ドラッグでパン、ホイール（またはPage Up / Page Down）でズームします。パッドでは右スティックで回転、L3 + 右スティックでパン、R2 / L2でズームします。ズームとMoveのヒントブロックが、ゲーム本来のRotationブロックの隣に表示されるため、その場で操作方法がわかります。

### ローカライズ

メニューテキストはゲーム自身の言語設定 -- en、fr、ja、zh-Hans、さらにit、de、es、es-419、ru、pl、pt-BR、ko、zh-Hant、arに追従し、ゲーム本来のOptions画面で言語を変更した瞬間にリアルタイムで更新されます。

### ソースファイル

| モジュール | パス | 役割 |
|---|---|---|
| SF6_ColorSpinExtra | `autorun/SF6_ColorSpinExtra.lua` | カラーリストへの注入（RW/MC/LLエントリー）とネイティブHSVカラー・マテリアルエディター |
| NativeLocale | [`autorun/func/NativeLocale.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeLocale.lua) | メニューテキストのローカライズ。ゲームの言語設定に追従する |

---

## 11. ケーススタディ -- Drive Impactの配色メニュー

テクニック1の2つ目の実例です。今回は3つの異なる画面で再利用され、メニューの深さも2種類あります。

### どこで開くか

下部ガイドに「X Edit Drive Impact Color」（キーボードはX、パッドはSquare）が3か所に表示されます: Edit Character画面、トレーニングのポーズメニューの「Character Settings」ポップアップ、そしてVS / トレーニングのキャラクターセレクトのカラーパネルです。2つのポップアップでは**簡略版**メニュー（EnabledとPresetのみ）が表示され、Edit Characterでは以下で説明するフルメニューが表示されます。

### 行

- **Enabled** -- Off / On / Follow。Followは、キャラクターが対戦中に現在着用しているカラーの2つのSquareをそのまま使い、他に設定する項目はありません。ゲーム標準のカラーの場合、このペアはゲーム自身のデータから読み取ります（`app.helper.hGUI.GetFighterCostumeColorData(fighter, costume, colour)`が`Color00` / `Color01`を持つ`app.FighterColorData`を返し、これはセレクト画面が描くチップそのものです）。保存済みカラーの場合は、そのカラーの2つのSquareです。着用中のコスチュームはカラーコントローラーのファイルパス（`esf027_003_CCVD.user` = テリー、コスチューム3）から取得します。
- **Preset** -- 全キャラクター共通のプリセットに続いて、このキャラクター自身の保存済みカラー（「MC n」、その2つのSquareがインラインで表示される）、そして巡回パレット用の**LL**が並ぶスピンです。
- **Color 1**（メインカラー -- インパクトの飛沫やトレイル）と**Color 2**（アクセントカラー）は、それぞれカラーエディター（10章）と同じBackspace-to-saved、コピー/ペースト、赤い点の挙動を持つHSVページを開きます。
- **SAVE**は選択中のプリセットを上書きします -- 代わりに「MC n」カラーが選択されている場合は、Color 1 / Color 2をそのカラーの2つのSquareに直接書き込みます。**SAVE AS**は新しいプリセット（「DI n」）を作成します。**RESET**は選択中の項目のカラーに戻します。保存済みのプリセットの場合、ページの代わりにRESET / DELETEが表示されます。

### Edit Characterではプレビューされない

Drive Impact自体は実際の対戦中でしかトリガーできないため、ここで選んだカラーはEdit Characterのプレビューモデルには反映されません -- 対戦中に表示されます。LLを選択している場合、パレットはその対戦が終わるまで巡回し続けます。

### プレイヤーごと

設定はキャラクターごと**かつサイドごと**です。メニューは開かれたサイドの設定を編集し（タイトルに「LUKE - P2」のように表示されます）、`<Fighter>.json`は`p1`と`p2`の2つの設定を保持します。異なる2キャラクターの場合、各サイドは自分のエフェクトプロバイダーに書き込むため、P1 Off / P2 Onはそのまま機能します。ミラーマッチでは両方のDrive Impactが**同じ**プロバイダーを読むため、あるサイドのDrive Impactが始まった瞬間（`nAction.Engine.SetActionData`のポストフック、アクションID 855 / 857。ポーリングより1フレーム早く、開始時のトレイルが生成される前）に、そのサイドの設定でカラーが書き込まれます -- そのサイドのカラー、またはOffならゲーム標準のパレットです。

### データ

`data/SF6_DIRecolor_data/<Fighter>.json`（`{ p1 = ..., p2 = ... }`）と`_presets.json`が、このメニューで編集するすべてのデータを保持します。同じファイルはImGuiの「DI Recolor (P1 / P2)」パネルからも編集でき、そのDebugノードにはセレクト画面で選択中のペア（「colour to apply」）が、対戦で最後に適用されたペアの隣に表示されます。

### ソースファイル

| モジュール | パス | 役割 |
|---|---|---|
| DIColorMenu | `autorun/func/DIColorMenu.lua` | 本セクションで説明したネイティブなDrive Impactカラーメニュー |
| SF6_DIRecolor | `autorun/SF6_DIRecolor.lua` | Drive Impactのカラーエンジンとキャラクターごとのデータ。メニューが読み書きできるよう`_G.SF6_DIRecolor`を公開する |

---

## 12. 自分でゲームメニューを解剖する

本ガイドで紹介したテクニックは、使い捨てのLuaスクリプトで実行中のゲームUIを探査することで見つかったものです。以下はそのワークフローです。

### ツール

- **`sf6.py`**（`agent/sf6.py`内）: REFrameworkのwebsocketサーバーと通信するPythonスクリプト。主なコマンド:
  - `sf6.py run agent/tmp/my_probe.lua --wait my_probe` -- プローブスクリプトをデプロイし、`data/my_probe.json`が書き込まれるのを待つ。
  - `sf6.py shot` -- スクリーンショットを撮影する（`agent/shots/`に保存される）。
  - `sf6.py reset` -- すべてのスクリプトをリセットする（プローブのフックをクリアする）。
  - `sf6.py logs` -- `re2_framework_log.txt`を読んでエラーを確認する。
  - `sf6.py state` -- 現在のゲーム状態（フロー、モード、キャラクター、位置、HP）をダンプする。
  - `sf6.py tap ESC` / `sf6.py tap E` / `sf6.py tap A` -- メニュー操作用のキータップを送る。
- **プローブスクリプト**（`agent/tmp/`内）: データをJSONにダンプして終了する、短いLuaファイル。

### 探査ワークフロー

1. **調べたいメニューまで移動する**: `sf6.py nav training`を実行し、`sf6.py tap ESC`でポーズメニューを開き、`sf6.py tap E`/`sf6.py tap A`でタブを切り替える。

2. **UIAgentを列挙**して、そのメニューを誰が所有しているかを見つける:

```lua
-- agent/tmp/probe_agents.lua
local out = {}
local mgr = sdk.get_managed_singleton("app.UIAgentManager")
local list = mgr:get_field("_Entries")
for i = 0, list:call("get_Count") - 1 do
    local agent = list:call("get_Item", i).Agent
    local go = agent and agent:call("get_GameObject")
    out[#out + 1] = {
        name = go and tostring(go:call("get_Name")) or "?",
        type = agent and agent:get_type_definition():get_full_name() or "?"
    }
end
json.dump_file("__OUT__.json", out)
```

3. エージェントが分かったら、**コントロールツリーをダンプする**:

```lua
-- agent/tmp/probe_ctrl_tree.lua
local function dump(ctrl, depth)
    if not ctrl or depth > 20 then return nil end
    local r = {
        name = tostring(ctrl:call("get_Name")),
        type = ctrl:get_type_definition():get_name(),
        visible = ctrl:call("get_Visible"),
        size = { w = ctrl:call("get_Size").w, h = ctrl:call("get_Size").h }
    }
    local children = {}
    local c = ctrl:call("get_Child")
    while c do
        children[#children + 1] = dump(c, depth + 1)
        c = c:call("get_Next")
    end
    if #children > 0 then r.children = children end
    return r
end
-- ... find the agent, get_ControlMain(), dump(main, 0) ...
json.dump_file("__OUT__.json", tree)
```

4. 興味のあるオブジェクトの**型定義（フィールドとメソッド）をダンプする**:

```lua
local function dump_type(td)
    local fields, methods = {}, {}
    for _, f in ipairs(td:get_fields()) do
        fields[#fields + 1] = { name = f:get_name(), type = f:get_type():get_full_name() }
    end
    for _, m in ipairs(td:get_methods()) do
        local params = {}
        for _, p in ipairs(m:get_param_types()) do params[#params + 1] = p:get_full_name() end
        methods[#methods + 1] = { name = m:get_name(), params = params, ret = m:get_return_type():get_full_name() }
    end
    return { name = td:get_full_name(), fields = fields, methods = methods }
end
```

5. **プロトコルをフックトレースし**、ゲームが自身のフローで何を呼び出しているかを確認する:

```lua
-- Hook every method of a Param type, log which ones fire
local td = sdk.find_type_definition("app.UIFlowOptionBGDialog.Param")
for _, m in ipairs(td:get_methods()) do
    pcall(function()
        sdk.hook(m, function(args)
            log.info("PARAM CALL: " .. m:get_name())
        end, function(rv) return rv end)
    end)
end
```

> **警告:** フックを使ったプローブの間は、スクリプトをリセットしてください（`sf6.py reset`）。応答しなくなった以前のプローブのフックが残っていると、空白の行、死んだコールバック、あるいはクラッシュの原因になります。

### 落とし穴

- `System.Int32[].GetValue(i)`は一部のREFrameworkビルド（LL5271のwebsocketビルド）で`nil`を返します。`get_element(i)`、生メモリ読み取り（`read_dword(0x20 + 4*i)`）、あるいはインデックス演算子`array[i]`を試してください。
- 前回のスクリプト読み込みで登録された`hMsg`のGUIDテキストは、Reset Scriptsで失われます。偽GUIDでプローブしている場合、プローブが再登録するまでリセット後は空白になります。
- プローブスクリプトは`agent/tmp/`に置き、`autorun/`には絶対に置かないでください。`autorun/`内のスクリプトは起動時に自動読み込みされ、`sf6.py reset`ではリセットされません。また、`autorun/`のサブディレクトリ内のスクリプトは、Reset Scriptsでは一切再読み込みされません。

---

## 13. トラブルシューティング

| 症状 | 原因 | 対処法 |
|---|---|---|
| ウィンドウの開閉後に**画面が黒くなる** | ポーズ保持中にフェードアニメーションがフリーズしている | `CreatedObject`で`<ImmediateFade>k__BackingField = true`を設定する（5章）。30ティック経ってもダイアログが消えていなければポーズを解放する。 |
| ウィンドウの内容変更後に**RIP 0**（nullポインタクラッシュ） | 開いているダイアログページを再構築してしまった（ルール3） | ダイアログを`End()`し、`OptionDialog`エージェントが消えるのを待ち、新しく`Start()`する。 |
| **set_MessageでAV** | 解放済みの`via.gui.Text`コントロールへの書き込み | ポーズ/ウィンドウが開いたときはすべてのキャッシュを破棄する（ルール2）。ポーズの遷移中は絶対に書き込まない。 |
| **禁止マークアイコン**付きの空白行 | 自分の`FuncType`に対して`GetIsActive`が応答していない | `TrainingMenuFunc.GetIsActive`をフックし、自分のFuncTypeには`1`を返す。 |
| ポーズメニューで**行にフォーカスできない** | `_FuncType`がゲームの想定する列挙型に含まれていない | 一貫して`345`（DYNAMIC）を使う。`TrainingMenuData`の`IsEnabled = true`を確認する。 |
| メニュー行の**テキストが空白** | GUIDが未登録（初回読み込み）、またはReset Scriptsで失われた | `re.on_script_reset`内、あるいは構築時にGUIDを再登録する。ユニット作成前に`message_guid()`が呼ばれているか確認する。 |
| ボタン押下時に**「Restore Default Settings?」ポップアップ**が出る | decideの横取りをせずに`EventType.SettingReset`を使っている | `GetFocusDecideEventType`をフックし、自分のボタンのTypeIdには`Invalid (0)`を返す。 |
| Basic Settingsで**14行目が見切れる** | スクロールビューの`_ViewSize.h`が大きすぎる | メニューが開いている間に`UIPartsGroupScroll`へ`_ViewSize.h = 745`を書き込む。 |
| ウィンドウを開くと**値がデフォルトにリセットされる** | 自分のTypeIdに対してゲームの`LoadValueEvent`が発火している | `OptionValueUnit.LoadValueEvent`をフックし、自分のTypeIdはスキップする。 |
| ウィンドウは開くが**戦闘が一時停止しない** | `PauseType`が間違っている、またはポーズが拒否されている | タイプ`8`（`BATTLE_MENU_PAUSE`）を使う。すでに別のポーズ状態になっていないか確認する。 |
| ポーズメニューを閉じたときに**Optionsウィンドウが開いてしまう** | 猶予フレームの間`OpenMenu`がブロックされていない | `TrainingManager.OpenMenu`をフックし、ウィンドウを閉じた後の約20フレームはスキップする。 |
| **メモリリーク**（Luaメモリの増加） | ホットパスでの`pcall(function() ... end)` | `pcall(named_func, args)`に置き換える（ルール5）。 |
| N秒ごとの**フレームスパイク** | タイマーでの`fs.glob`呼び出し | `fs.glob`の呼び出しをウィンドウオープン時のパスのみに移す（ルール7）。 |
| モード変更後、ポーズメニューのスピンが**間違った値**を表示する | getterが古いインデックスを返している | 外部でモードが変化したときにタブを再構築・再インストールする。 |
| NativeHudのテキストの**色が間違っている** | ABGRではなくRGBを使っている | すべての`via.gui`の色は**ABGR**（上位バイトがアルファ、その次が青）。`0xFF0000FF` = 不透明な赤。 |

---

## 14. 付録 -- 型と列挙型リファレンス

### app.Optionの列挙型

| 列挙型 | 使用される値 |
|---|---|
| `app.Option.UnitInputType` | `SpinText`（矢印付きスピン）、`Slider`（横長バー）、`Button_Type1`（サブメニュー/左揃え）、`Button_Type2`（アクション/中央揃え）、`Button_Type0`（ラジオポップアップ、カスタムIDでは動作しない） |
| `app.Option.DecideEventType` | `OpenSubMenu`（サブメニューに入る）、`OpenBattleHudSetting`（HUDウィンドウを開く）、`SettingReset`（ボタン/復元）、`OpenRadioButton`（ポップアップリスト、カスタムIDでは動作しない）、`Invalid`（0、何もしない） |
| `app.Option.SettingDataType` | `Value`（min/maxを持つ数値） |
| `app.Option.TabType` | `General`（「SF6 Tools」が置かれるタブ） |

### app.trainingの型

| 型 | 主なフィールド |
|---|---|
| `TrainingMenuData` | `_Type`（0=TEXT_ONLY、1=SPIN）、`_FuncType`（1〜8が標準、345が自分たち用）、`_MessageID`（GUID）、`_GuideMessage`（GUID）、`_ChildData`（TrainingMenuData[]）、`DynamicChildData`（List）、`IsEnabled`、`_Interval`、`_GuidIcon`、`VisibleCase` |
| `TrainingMenuFunc` | メソッド: `ViewUpdate`、`GetIsActive`、`GetOptionText`、`GetOptionText2`、`GetOptionIndex`、`IsValueType`、`GetVisibleCase`、`IsChangedValue`、`Function` |
| `TrainingPauseMenuUserData` | `_MenuData`: `TrainingMenuData[]`（タブごとに1要素） |

### app.UIFlowOptionBGDialog

| 型 | 主なメンバー |
|---|---|
| `SettingData` | `TopUnit`、`SupportMode`（32）、`UseBattleHudBG`（自分たちのウィンドウでは false）、`PlayerIndex` |
| `Param` | `GetFocusUnit()`、`GetFocusDecideEventType()`、`SetupDispUnits()`、`FlowEvent_ResetCurrentUnits()`、`CreatedObject()`、`OptionUnits`（パーツの配列） |
| 静的メソッド | `Start(SettingData, bool)` -> `IUIFlowHandle` |

### PauseManager

| ポーズタイプ | 値 | 内容 |
|---|---|---|
| `DIALOG_PAUSE` | 1 | ダイアログスコープのオブジェクトのみを一時停止する（戦闘は止めない） |
| `BATTLE_MENU_PAUSE` | 8 | 戦闘を一時停止する（実際のポーズメニューと同じ）。`_CurrentPauseTypeBit`ではビット=64。 |
| `BATTLE_TRAINING_PAUSE` | 11 | トレーニングメニュー以外のコンテキストでは拒否される |

### EConfigInitLayout（開始位置）

| 名前 | 値 |
|---|---|
| `CENTER` | 0 |
| `RIGHT` | 1 |
| `LEFT` | 2 |
| `MANUAL` | 3 |

### ソースファイル

All modules below are published in [`guide/lua/func/`](https://github.com/Wael3rd/SF6_Tools/tree/main/guide/lua/func). Copy them into `reframework/autorun/func/`; `NativeOptions.lua` is the base module.

| モジュール | パス | 役割 |
|---|---|---|
| NativeOptions | [`autorun/func/NativeOptions.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeOptions.lua) | Optionsダイアログウィンドウ（テクニック1） |
| NativePauseMenu | [`autorun/func/NativePauseMenu.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativePauseMenu.lua) | ポーズメニューの行とタブ（テクニック2） |
| NativeHud | [`autorun/func/NativeHud.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeHud.lua) | ダメージパネルとタイマー（テクニック3） |
| NativePopup | [`autorun/func/NativePopup.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativePopup.lua) | 借用要素によるポップアップ（テクニック4） |
| NativeShortcuts | [`autorun/func/NativeShortcuts.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeShortcuts.lua) | Shortcut Settingsの差し替え（テクニック5A） |
| NativeDialog | [`autorun/func/NativeDialog.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeDialog.lua) | KeyConfigダイアログの乗っ取り（テクニック5B） |
| NativeTopBar | [`autorun/func/NativeTopBar.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeTopBar.lua) | モードセレクターバー（借用要素、無効化） |
| NativeBottomBar | [`autorun/func/NativeBottomBar.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/NativeBottomBar.lua) | アクションボタンバー（実験的、無効化） |
| GameState | [`autorun/func/GameState.lua`](https://github.com/Wael3rd/SF6_Tools/blob/main/guide/lua/func/GameState.lua) | ポーズ検出（`GS.in_pause_menu`） |
| Training_ScriptManager | `autorun/Training_ScriptManager.lua` | オーケストレーター（モード切り替え、登録） |

---

## 15. クレジット

- **Wael3rd** -- すべてのネイティブUIモジュール（NativeOptions、NativePauseMenu、NativeHud、NativePopup、NativeShortcuts、NativeDialog、NativeTopBar、NativeBottomBar）、探査ワークフロー、クラッシュ調査、そして本ガイド。
- **mfyk** -- OptionManagerインジェクションのテクニック（UnitListsへのOptionSettingUnit注入、偽GUIDテキストフック、OpenBattleHudSettingウィンドウ）。2026年に公開共有され、パブリックな利用が許可されている。テクニック1の基礎。
- **alphaZomega** -- 開発中に使用したREFrameworkツール群とナレッジベース。
- **cdjay** -- SF6 Toolsのコードベースへの貢献（BCMカタログ、モダン記法、コマンド表示フォーマット）。Training_ScriptManagerで参照されている。
- **praydog** -- REFramework本体。
- **LL5271** -- REFramework-Websocketsフォーク（本ガイドで使用している`dinput8.dll`ビルド）。そのwebsocketサーバーが、リモート探査ワークフロー（`sf6.py run / state / shot`）と本ガイドのすべての解析を可能にしている。

---

*変更履歴: 2026-09-03 -- 10-11章（カラーエディター、Drive Impactの配色メニューのケーススタディ）を追加。2026-08-31 -- 初版。*
