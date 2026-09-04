# Revenue App — UI/UX 修正與資訊架構重設計

> 產出於 2026-08-26，分支 `v3`。接續 [refactor-plan.md](refactor-plan.md)（Phase 0-8 已完成）。
> 那份文件處理的是「資料對不對」，這份處理的是「畫面對不對、路徑順不順」。
> 預計 2026-08-27 開始執行。

## 進度（2026-08-27）

**A、B、C、D 四個批次全部完成。** `flutter analyze` 乾淨；`flutter test` 70 項
全過；`flutter build web --no-tree-shake-icons` 通過。

新增的檔案：
[lib/widgets/stat_card.dart](../lib/widgets/stat_card.dart)（`StatCard` /
`StatIcon` / `ChangeBadge`，取代四份複製的 `_buildCard`）、
[lib/widgets/money.dart](../lib/widgets/money.dart)、
[lib/widgets/chart_theme.dart](../lib/widgets/chart_theme.dart)、
[lib/analysis/headline.dart](../lib/analysis/headline.dart)（結論層）、
[lib/settings/theme_controller.dart](../lib/settings/theme_controller.dart)。
刪掉的：`lib/page/overview.dart`、`assets/google-gemini-icon.svg`。

`lib/widgets/feedback.dart` 是**跟另一條工作線共用的**——`showError` /
`showInfo` / `showSnack` 是這份計畫加的，`showFailure` / `ErrorView` 來自
同時進行的錯誤處理重構。動它之前先看一眼現況。

### 三處要知道的決定

**A10 的中英文**：AddOrder 送出鈕的「增加訂單／修改訂單」改成英文
（`Add order` / `Save changes`），跟其他 100% 的介面一致。**這不等於決定了
整個 app 就要英文**——只是先把唯一一處混雜拿掉。要中文化是另一件事，
兩個字串改回來很便宜。

**B2 的偏離**：計畫寫「結論卡放頁頂」，實作成 **Summary 分頁、預設第一個**。
頁頂放卡再接 TabBar + TabBarView 會兩層捲動打架。點卡片會 `animateTo` 到
對應報表，跳轉行為有保留。

**順手做的**：`home.dart` 改成 lazy `IndexedStack`。原本 `screens[pageIndex]`
每切一次分頁就重建 State、重讀一次 session；改成建過就留著，但沒被點過的
分頁不建（否則沒開過 Insights 的人也要付九十天的 `fetchRange`）。

### 一個既有問題，不是這次改出來的

`flutter build web`（不加 `--no-tree-shake-icons`）會失敗：

```
Target web_release_bundle failed: Error: Avoid non-constant invocations of
IconData or try to build again with --no-tree-shake-icons.
```

來源是 [menu_item.dart:72](../lib/models/menu_item.dart#L72) 和
[store_settings_edit_menu.dart:396](../lib/settings/store_settings_edit_menu.dart#L396)
——菜單品項把使用者挑的圖示存成 codePoint，再用 `IconData(codePoint)` 組回來，
Flutter 的圖示搖樹沒辦法證明哪些圖示用得到。這兩處也是 `flutter analyze`
唯一剩下的兩個警告。要修的話是另一個題目（把可選圖示限縮成一組常數表），
不屬於這份計畫。

---

## 0. 三個結論

1. **顏色**：主題系統存在但沒人用。[main.dart:29](../lib/main.dart#L29) 寫死
   `themeMode: ThemeMode.light`，[theme.dart](../lib/theme.dart) 整套 `darkScheme()`
   是死碼；全 app 約 90 處硬寫 `Colors.*`，所以就算現在打開 dark mode 也會壞。
   個別的錯用（`splashColor` 當底色、`on-` 前綴色當背景）都是這個缺口的症狀。
2. **Overview 砍掉**。它顯示的兩個數字 Transaction 頁全都有且更完整，兩頁掛著
   一模一樣的 FAB，獨有內容只剩問候語和一個時鐘。它佔的是四個 tab 裡最貴的位置。
3. **Insights 升到一級 tab**，且要補一層「結論」。Statistics 回答「賣了多少」，
   Insights 回答「該做什麼」——後者才是老闆打開 app 的理由，現在卻藏在
   [statistics.dart:159](../lib/page/statistics.dart#L159) 一個沒有文字標籤的
   AppBar IconButton 裡。

## 1. 執行順序

四個批次照相依性排。**批次 A 內每一項互不相依，可以任意順序、隨時停下來出貨。**
批次 B 動導覽結構，要一次做完。C、D 是新東西。

| 批次 | 內容 | 風險 | 一句話 |
|---|---|---|---|
| **A** | 顏色 token 化、清空殼、Export 移位 | 低 | 純修，不動結構 |
| **B** | 砍 Overview、四個 tab 重排 | 中 | 一次改完再上 |
| **C** | Insights 結論卡 + 成本填寫引導 | 中 | Insights 配得上一級的前提 |
| **D** | 圖表配色統一、dark mode 打開 | 中 | 要等 A 做完才有意義 |

---

## 2. 批次 A — 顏色與空殼（低風險，可各自出貨）

### A1 `splashColor` 不是 surface token

`splashColor` 是 M2 的漣漪色（半透明黑，約 alpha 0.1），在 M3 沒有語意。疊在
Card 上實際顏色不可控、對比沒保證。每張 stat card 的圓形圖示底就是它——所以
它們看起來像髒掉的灰，而不是設計過的顏色。

改成 `colorScheme.secondaryContainer`，圖示改 `onSecondaryContainer`。

- [x] ~~overview.dart~~ — 隨 B1 一起消失
- [x] [statistics.dart:443](../lib/page/statistics.dart#L443)、[:562](../lib/page/statistics.dart#L562)
- [x] [transaction.dart:175](../lib/page/transaction.dart#L175)、[:221](../lib/page/transaction.dart#L221)
- [x] [store.dart:147](../lib/page/store.dart#L147)、[:183](../lib/page/store.dart#L183)
- [x] [store_staff.dart:187](../lib/settings/store_staff.dart#L187) ← 唯一還在用 `splashColor` 的地方

順手做掉：這五個檔案的 `_buildCard()` 是**同一份程式碼複製四遍**
（overview / statistics / transaction / store 各一份，寬度都是
`MediaQuery.size.width / 2 - 30`）。抽成一個共用 widget，之後改配色只要改一處。

### A2 底部導覽把字色當底色

[home.dart:38](../lib/home.dart#L38) `indicatorColor: onPrimaryContainer`（深綠），
選中圖示 `onPrimary`（白）。M3 規範是 indicator = `secondaryContainer`、
icon = `onSecondaryContainer`。現在是一顆深色藥丸配白圖示，比周圍 surface 重太多，
視覺上像一個黑點；而且選中的 **label 顏色沒跟著改**，仍是 `onSurfaceVariant`，
跟指示器對不起來。

- [x] 移除整個 `NavigationBarTheme` 包裝，讓 M3 預設值生效
- [x] 移除 `selectedIcon` 的 `color:` 覆寫
- [x] `animationDuration: 800ms` 太慢（[home.dart:42](../lib/home.dart#L42)），
      M3 預設 500ms；切頁時指示器還在滑，內容已經換完了

### A3 漲跌 badge 對比不足且撞色

[statistics.dart:615-620](../lib/page/statistics.dart#L615-L620)：`Colors.green`
文字放在 `Colors.green[100]` 底上，對比約 2.2:1，遠低於 4.5:1 —— 這是全 app
最不該看不清的數字。另外 primary 本來就是綠的，「+12%」的綠和按鈕的綠是兩種
不同的綠，並排看很雜。

- [x] 漲：`tertiaryContainer` / `onTertiaryContainer`；跌：`errorContainer` / `onErrorContainer`
- [x] 箭頭圖示保留（不能只靠顏色表達漲跌）

### A4 錯誤 SnackBar 一律 `Colors.red` + 白字

六處。改 `colorScheme.errorContainer` / `onErrorContainer`。

- [x] [statistics.dart:127](../lib/page/statistics.dart#L127)
- [x] [addorder.dart:228](../lib/page/addorder.dart#L228)、[:232](../lib/page/addorder.dart#L232)
- [x] [store_invites.dart:222](../lib/settings/store_invites.dart#L222)
- [x] [store_staff.dart:155](../lib/settings/store_staff.dart#L155)
- [x] [change_password.dart:180](../lib/settings/change_password.dart#L180)
- [x] [user_passkeys.dart:249](../lib/settings/user_passkeys.dart#L249)

### A5 灰字改 `onSurfaceVariant`

- [x] ~~overview.dart 的 `Colors.grey` / `Colors.black54`~~ — 隨 B1 一起消失
- [x] [analysis.dart:577](../lib/page/analysis.dart#L577)、[:675](../lib/page/analysis.dart#L675)（空狀態圖示）
- [x] [addorder.dart:462](../lib/page/addorder.dart#L462)、[:465](../lib/page/addorder.dart#L465)
- [x] [store_setting_history_order_detail.dart:161](../lib/settings/store_setting_history_order_detail.dart#L161)、[:172](../lib/settings/store_setting_history_order_detail.dart#L172)、[:176](../lib/settings/store_setting_history_order_detail.dart#L176)、[:178](../lib/settings/store_setting_history_order_detail.dart#L178)、[:213](../lib/settings/store_setting_history_order_detail.dart#L213)
- [x] [store_settings_audit_log.dart:66](../lib/settings/store_settings_audit_log.dart#L66)
- [x] [store_settings_edit_menu.dart:175](../lib/settings/store_settings_edit_menu.dart#L175)、[store_categories.dart:109](../lib/settings/store_categories.dart#L109)（`Colors.black26` 拖曳把手）
- [x] [store_setting_history_order_detail.dart:126](../lib/settings/store_setting_history_order_detail.dart#L126) 手寫 `Color(0xFFFFCDD2)` → `errorContainer`

> `login.dart` / `register.dart` / `sign_in_options.dart` / `main.dart` 的
> WelcomeScreen 是另一套刻意的黑白手繪風（`Colors.yellow` 按鈕、黑框圓角）。
> **這批先不動**——它自成一格，要改就是整個登入流程重新設計，不屬於這份計畫。

### A6 Card 邊界看不見

[theme.dart:133](../lib/theme.dart#L133) `scaffoldBackgroundColor: colorScheme.background`
（Flutter 3.22+ 已 deprecated，等同 surface），而全 app 每張 Card 都
`elevation: 0` 且沒設 color，M3 預設給 `surfaceContainerLow`。兩者只差一階明度，
卡片跟背景幾乎糊在一起——這是「畫面平平的、沒有層次」的直接原因。

- [x] `colorScheme.background` → `colorScheme.surface`
- [x] Card 統一給 `surfaceContainer`（差兩階），或保留 elevation 0 但加
      `outlineVariant` 的 1px 邊框。二選一，**不要兩個都做**

### A7 清掉空殼與 debug 殘留

- [x] [statistics.dart:179-182](../lib/page/statistics.dart#L179-L182) Gemini FAB：
      `onPressed` 只有 `debugPrint`，內層 `GestureDetector` 連 `onTap` 都沒有。
      畫面上最大最搶眼的按鈕按不動 —— **直接移除**。
      這就是 refactor-plan 裡掛著沒解的 F7；決定是「不做」，順便把
      `assets/google-gemini-icon.svg` 和 [statistics.dart:41](../lib/page/statistics.dart#L41)
      那個永遠是 false 的 `isDark` 一起清掉
- [x] [overview.dart:136-138](../lib/page/overview.dart#L136-L138) 點卡片跳
      `Store ID: xxx` 的 SnackBar —— debug 殘留（若 B1 先做則直接消失）

### A8 Export 藏了三層

現在要匯出 Excel：捲到頁尾 → 點一張沒有文字標籤的「+」卡 → sheet 裡點 Export →
sheet 自動關 → 再捲到頁尾點新出現的卡片。而且 `featureSelected`
（[statistics.dart:44](../lib/page/statistics.dart#L44)）是 in-memory，切個 tab 就沒了。

- [x] Export 移到 AppBar action（`Icons.download_outlined`，帶 tooltip），
      匯出中換成 `CircularProgressIndicator`
- [x] 整個 `featureSelected` / `_buildAddMoreCard` / `_buildAddMoreSheet` 移除。
      "Income" 那張卡顯示的值跟頁頂 Revenue 卡**完全一樣**，本來就是多餘的

### A9 翻頁箭頭是兩顆大方塊

[statistics.dart:243](../lib/page/statistics.dart#L243)、[:256](../lib/page/statistics.dart#L256) 用 `ElevatedButton` 包 `Icon`，
最小寬度 64，看起來像兩顆方塊夾著日期。

- [x] 改 `IconButton`
- [x] 補水平滑動翻頁。三個 tab 刻意共用一個 body（為省 Firestore 讀取，
      [statistics.dart:197-201](../lib/page/statistics.dart#L197-L201) 有說明）——
      **這個取捨是對的，不要改成 TabBarView**，但滑動手勢可以用
      `GestureDetector` 的 `onHorizontalDragEnd` 補回來

### A10 文案與幣別不一致

- [x] [addorder.dart:474](../lib/page/addorder.dart#L474) 送出鈕寫「增加訂單／修改訂單」，
      全 app 其他地方都是英文。**先決定整個 app 要中文還是英文**，再一次改完；
      現在這樣是最差的狀態
- [x] 幣別：statistics 用 `store.currency`（[statistics.dart:418](../lib/page/statistics.dart#L418)），
      而 overview / transaction / addorder / store 硬寫 `'NTD'`。把
      `_money(Store)` 抽成共用函式（analysis.dart 底部已經有一份一模一樣的）

### A11 Overview 時鐘每分鐘重建整頁

[overview.dart:26](../lib/page/overview.dart#L26) `Timer.periodic` + `setState`
重建整棵樹，只為了一行時間字。若 B1 執行則整頁消失，此項自動解決。

---

## 3. 批次 B — 資訊架構（一次改完再上）

### B1 砍掉 Overview

[overview.dart](../lib/page/overview.dart) 顯示今日營收、今日單數；
[transaction.dart](../lib/page/transaction.dart) 顯示今日營收、單數、來客數、客單價，
外加最近五筆交易。兩頁掛著一模一樣的 `Add Order` FAB。Overview 獨有的只有
問候語和時鐘——時鐘手機狀態列就有。

現在的流程是：開 app → Overview 看兩個數字 → 想看更多 → 切到 Trans 看到
同樣的數字加更多。第一頁純粹是一道多餘的門。

- [x] 刪除 `lib/page/overview.dart`
- [x] 問候語（`_getGreeting`）搬到 Transaction 頁頂端，取代
      [transaction.dart:57-68](../lib/page/transaction.dart#L57-L68) 寫死的
      「Today's Summary」標題
- [x] 更新 [refactor-plan.md](refactor-plan.md) 裡提到 overview.dart 的兩處引用

### B2 四個 tab 重排

[home.dart:19-34](../lib/home.dart#L19-L34)：

| # | 現在 | 改成 | 內容 | 圖示 |
|---|---|---|---|---|
| 1 | Overview | **Today** | 現 Transaction 全部 + 問候語 | `today_rounded` |
| 2 | Trans | **Insights** | 現 [analysis.dart](../lib/page/analysis.dart) 四個 tab + 結論卡（C1） | `lightbulb_rounded` |
| 3 | Stats | **Reports** | 現 [statistics.dart](../lib/page/statistics.dart)，Export 在 AppBar | `bar_chart_rounded` |
| 4 | Store | Store | 不動 | `storefront_rounded` |

- [x] `AnalysisPage` 現在是 `Navigator.push` 進去的、建構子吃 `Session`
      （[analysis.dart:29](../lib/page/analysis.dart#L29)）。當成 tab 就要自己
      載 session，改成跟其他頁一樣的 `loadSession()` + `FutureBuilder`，
      並移掉 [statistics.dart:157-166](../lib/page/statistics.dart#L157-L166)
      的 Insights AppBar 按鈕
- [x] 標籤字：`Trans` 這種縮寫在 M3 NavigationBar 裡沒必要，`Today` / `Insights`
      / `Reports` / `Store` 都塞得下

### B3 AddOrder 第一屏全是設定

日期、通路、人數、付款四個 tile 佔滿第一屏（[addorder.dart:267-273](../lib/page/addorder.dart#L267-L273)），
最高頻的「點菜」要先捲過去。而且 `categoryId` 有讀進來
（[addorder.dart:28](../lib/page/addorder.dart#L28)）但 UI 完全沒分組，
菜單是一長條平鋪。

- [x] 四個設定 tile 收進一個預設收合的 `ExpansionTile`（標題直接摘要現值：
      「內用 · 1 位 · 現金 · 今天 14:30」），點菜區直接見面
- [x] 菜單按 `categoryId` 分組，沿用 [store_categories.dart](../lib/settings/store_categories.dart) 的排序

---

## 4. 批次 C — Insights 要有結論

### C1 結論卡

Insights 現在本質上是「四個報表的容器」，自己不下結論——四個 tab 各是一張表，
使用者得自己看出意思。要配得上一級 tab，最上面該有一層把數字寫成句子的摘要：

- 「Dog 類有 3 道菜，佔菜單 12% 卻只帶來 2% 營收」
- 「週二 14–17 點平均 0.8 單」
- 「食材成本 38%，高於 35% 警戒線」

每張卡點進去才是現在的四個分頁。這些數字 [lib/analysis/](../lib/analysis/)
裡**都已經算好了**（`MenuEngineering.foodCostRate`、`DemandProfile.peak`、
`ofClass(MenuClass.dog)`），缺的只是一個把它們寫成句子的層。

- [x] 新增 `lib/analysis/headline.dart`：吃 `MenuEngineering` + `DemandProfile`，
      吐一組排序過的 `Headline(嚴重度, 句子, 目標分頁)`
- [x] Insights 頁頂放這組卡，點擊跳對應分頁
- [x] 沒有足夠資料時整組不顯示，不要塞佔位卡

### C2 成本填寫引導（C1 的前提）

Insights 全靠 `menuItems.cost`。沒填成本，菜單工程矩陣整個是空的——
[analysis.dart:154-164](../lib/page/analysis.dart#L154-L164) 已經有這個 empty
state。升成一級 tab 之後，新使用者點進去第一眼就是空白，比藏在 AppBar 裡更糟。

- [x] [store_settings_edit_menu.dart](../lib/settings/store_settings_edit_menu.dart)
      列表上顯示「N 道菜還沒填成本」的橫幅，點擊篩出那些菜
- [x] Insights 的 empty state 加一顆直接跳過去的按鈕（現在只有一句文字說明）

### C3 四象限顏色分不出來

[analysis.dart:263-266](../lib/page/analysis.dart#L263-L266) 用
amber / orange / blue / grey。amber 和 orange 在 24px 圖示上幾乎一樣，
而 Star vs Plowhorse 正是最需要一眼區分的兩類。

- [x] 換成語意色：Star → `tertiary`、Plowhorse → `primary`、
      Puzzle → `secondary`、Dog → `outline`。四個都從 scheme 來，dark mode 自動跟上

---

## 5. 批次 D — 圖表與 dark mode

### D1 同一頁四套配色

統計頁三張 `SfCartesianChart` 沒設 palette，用 Syncfusion 預設藍；gauge 是紫；
badge 是綠紅；主題是綠。一個畫面四套色系。

- [x] 抽一個 `chartPalette(ColorScheme)`，三張圖和 gauge 共用
- [x] [statistics.dart:708-711](../lib/page/statistics.dart#L708-L711) gauge 的
      `#6A6EF6 → #DB82F5` 漸層和 `#00A8B5` 是 Syncfusion 範例直接抄的，
      跟綠色主題毫無關係，且在統計頁最顯眼。換成 primary → tertiary
- [x] 同一段的 `fontFamily: 'Times'` + italic 也是範例殘留
      （[statistics.dart:675-697](../lib/page/statistics.dart#L675-L697)），
      跟全 app 字體不同調，改用 `textTheme`

### D2 打開 dark mode

**要等 A1–A6 全做完才有意義**，否則一開就是一堆黑字配黑底。

- [x] [main.dart:29](../lib/main.dart#L29) `ThemeMode.light` → `ThemeMode.system`
- [x] [app_settings.dart](../lib/settings/app_settings.dart) 加淺色／深色／跟隨系統
      三選一，存 `SharedPreferences`
- [x] 驗收：`grep -rn --include="*.dart" -E "Colors\.(grey|black|white|red|green)" lib`
      在 `lib/page/`、`lib/settings/`、`lib/theme.dart` 底下應該**零命中**
      （`login.dart` / `register.dart` / `sign_in_options.dart` / `main.dart`
      的 WelcomeScreen 是刻意的另一套風格，見 A5 註）
- [x] [menu_capture_page.dart](../lib/settings/menu_capture_page.dart) 的
      `Colors.black` / `Colors.white70` 是相機取景框，**刻意保留**——
      取景畫面本來就該永遠是深色

---

## 6. 明天怎麼開始

從 A 做起，A7（清 Gemini FAB 和 Store ID SnackBar）和 A8（Export 移到 AppBar）
是立刻有感、風險最低的兩項。A1 抽共用 stat card 會動到四個檔案，但那四份程式碼
本來就一樣，抽完之後 A3、A6、D1 都只要改一處。

B 不要跟 A 混在同一個 commit——砍頁面和改配色一起 review 會看不清楚。

---

## 7. Material 3 Expressive — 現況與準備（2026-08-27 查證）

### Flutter 目前不支援，而且短期不會

追蹤 issue [flutter/flutter#168813](https://github.com/flutter/flutter/issues/168813)
上 Flutter 團隊的原話是：**「目前我們沒有在開發 Material 3 Expressive，
現階段也不接受 Expressive 相關的貢獻或更新。」** 那張 issue 是一個
umbrella，底下**一項都沒有完成**。

原因寫在同一張 issue（2025-07-29）：material 和 cupertino 兩個 library 正在
被拆成獨立套件以加快開發（進度看
[#101479](https://github.com/flutter/flutter/issues/101479)），
**所有 M3E 的工作都會等套件在 `flutter/packages` 底下站穩之後才在那裡進行**。

issue 列出的範圍：

| 類別 | 內容 |
|---|---|
| 要改的既有元件（9） | App bars、Buttons、Extended FAB、FABs、Icon buttons、Navigation bar、Navigation rail、Progress indicators、Carousel |
| 全新元件（5） | Button groups、FAB menu、Loading indicator、Split button、Toolbars |
| 樣式（4） | motion-physics 系統、強調型排版、擴充形狀庫（35 個新形狀）、鮮豔配色 |

本專案用的 Flutter 3.44.8 原始碼裡，`page_transitions_theme.dart` 有一段直接
承認這件事：

> Android 原生用的是 Flutter 目前不支援的 Material 3 Expressive spring，
> 所以這裡的 450ms 是近似值，而不是原生實際使用的 800ms。

**結論：現在沒有「升級到 M3 Expressive」這條路可以走**，官方 API 還不存在。
社群有第三方套件（`material_3_expressive` 之類），但那是別人重刻的一套元件，
把整個 app 綁上去，等官方版出來時要再拆一次。

### 現在就有的 M3E 相鄰 API

Flutter 3.44 已經內建、而且屬於 M3E 清單上那幾項的：

| API | 位置 | 能拿來做什麼 |
|---|---|---|
| `Durations` / `Easing` | `material/motion.dart` | M3 的動態 token（`Durations.medium2`、`Easing.emphasizedDecelerate` 等）。**不是** M3E 的 spring physics，但是同一個系統的前身 |
| `CarouselView` / `CarouselViewTheme` | `material/carousel.dart` | M3 carousel。它在 M3E 的「要改的元件」清單上，代表 Flutter 已經有了、之後會被更新 |
| `DynamicSchemeVariant.expressive` / `.vibrant` / `.rainbow` / `.fruitSalad` | `ColorScheme.fromSeed` | 最接近「鮮豔配色」的東西，今天就能用 |

### 這次改動已經鋪好的地基

M3E 真的來的時候，改動量取決於「顏色、字級、形狀、動態」這四件事有多集中。
現在的狀態：

1. **顏色** — `lib/page/` 和 `lib/settings/` 底下已經沒有硬寫的 `Colors.*`
   （登入流程和相機取景框是刻意保留的例外）。換一套 `ColorScheme` 是一行的事。
2. **字級** — 所有文字都走 `textTheme` 角色（`bodySmall` 25 處、`titleMedium`
   13 處、`headlineSmall`、`labelSmall`…），沒有寫死的 `fontSize`。換 type scale
   全 app 一起變。
3. **形狀** — Card 的圓角集中在 [theme.dart](../lib/theme.dart) 的 `cardTheme`。
   35 個新形狀進來時只有一處要改。
4. **圖表** — 抽成 [chartPalette(ColorScheme)](../lib/widgets/chart_theme.dart)，
   跟著 scheme 走。

### 建議的準備動作（還沒做，等決定）

| # | 動作 | 為什麼值得先做 |
|---|---|---|
| **P1** | [theme.dart](../lib/theme.dart) 改用 `ColorScheme.fromSeed(seedColor:…, dynamicSchemeVariant:…)`，取代手寫的 ARGB 整數 | 現在是 Material Theme Builder 吐出的六十幾個 `Color(4283066157)`，要換色只能重跑產生器。改成 seed 之後，試 `.expressive` / `.vibrant` 只是改一個 enum 值——這是**離「鮮豔配色」最近的一步，而且今天就能做** |
| **P2** | 給 `MaterialTheme` 一個真的 `TextTheme` | [main.dart:36](../lib/main.dart#L36) 傳的是空的 `TextTheme()`，而 [theme.dart:129](../lib/theme.dart#L129) 的 `textTheme.apply(bodyColor:…)` 對一個欄位全 null 的 TextTheme 是 **no-op**——那段其實沒有作用（文字顏色是 `ThemeData` 依 brightness 給的預設 typography 提供的，所以 dark mode 仍然正確，只是不是靠這段）。M3E 的「強調型排版」需要一份真的 type scale |
| **P3** | `Durations.*` / `Easing.*` 取代寫死的毫秒 | 目前只剩 [statistics.dart:564](../lib/page/statistics.dart#L564) gauge 的 `animationDuration: 1000` 一處。**便宜到可以順手做** |
| **P4** | 盯 `flutter/packages` 的 material 套件 | M3E 只會在那裡出現。在那之前不要引第三方 M3E 套件 |

P1 + P2 + P3 加起來大概是半天的工，做完之後 M3E 落地時要動的就只剩「換套件、
換元件名」，而不是「把顏色和字級從一百個檔案裡挖出來」。

---

## 8. 第二輪（2026-08-27 下午）

第 6 節之後又審了一遍，做掉六組加一個線上設定問題。

### 8.0 `Cannot list invite codes` — 根因是設定沒部署

`firebase firestore:indexes` 拿回線上實際部署的內容，跟本地檔案對不起來：

| | 本地 `firestore.indexes.json` | 線上實際 |
|---|---|---|
| `orders(businessDate, placedAt)` | ✅ | ✅ |
| `orders(status, placedAt)` | ✅ | ✅ |
| `dailyStats(orderCount, revenue)` | ✅ | ✅ |
| `orders(itemIds, businessDate)` | ❌ 缺 | ✅ |
| `invites(storeId, createdAt)` | ✅ | ❌ **缺** |

**Phase 6 之後的 firestore 設定從來沒部署過。** 畫面上看到的
`permission-denied` 是線上還在跑舊 rules（沒有 `match /invites/{code}` 那段）；
就算 rules 補上，後面還有一個 `failed-precondition` 在等，因為 invites 的
複合索引也沒建。UI 這邊已經擋過 `canManage` 了，所以不是角色問題。

已經做的：

- [x] 把線上有、本地缺的 `orders(itemIds, businessDate)` 補回
      [firestore.indexes.json](../firestore.indexes.json)。**這很重要**——
      不補就部署，CLI 會問要不要刪掉它，而它是搭配分析在用的
- [x] [invite_repository.dart](../lib/database/invite_repository.dart) 的
      `watchForStore()` 加上 `.handleError`。snapshot 的錯誤是走 stream 出來的，
      不是 throw，所以呼叫端 catch 不到——這就是為什麼畫面上出現的是原始的
      `[cloud_firestore/permission-denied] Missing or insufficient permissions.`
- [x] `_translate` 加 `failed-precondition` 分支（保留伺服器訊息裡的建索引連結）
- [x] [store_invites.dart](../lib/settings/store_invites.dart) 改用 `ErrorView`，
      `denied` 不給重試按鈕（重試被拒絕的權限只會再被拒絕一次）
- [x] 順手修一個既有 bug：那個 30 秒 ticker 每次 `setState` 都會在 `build`
      裡重新建一個 stream，等於每半分鐘重訂閱、重讀一次整份清單。改成存在欄位裡

**還沒做，需要你跑**（會動生產環境，我沒有自己執行）：

```
firebase deploy --only firestore:rules,firestore:indexes
```

索引建立要幾分鐘才會生效。

### 8.1 深色模式弄壞了登入流程 — 這是 D2 的迴歸

D2 把 `themeMode` 打開跟隨系統，但登入前的四個畫面被刻意排除在 A5 之外，
裡面約四十個寫死的淺色色值不會跟著走。Scaffold 背景變深、上面的
`Colors.black` 標題沒變 → 整條入口流程在深色手機上讀不到。

- [x] 新增 `pre_auth_theme.dart`，把 WelcomeScreen、LoginPage、RegisterPage
      （三個 Scaffold）釘在淺色主題

這曾經是**權宜之計，不是修好**——那套黑白手繪風是刻意選的，要真的支援深色就是
把它重新設計一次。

- [x] 已經重新設計過，`pre_auth_theme.dart` 隨之刪除。字面色改成 scheme
      token；unDraw 插圖由 [illustration_palette.py](../tool/illustration_palette.py)
      映射到本專案的調色盤並亮暗各產一份；黑框膠囊按鈕收斂成
      [pre_auth_button.dart](../lib/widgets/pre_auth_button.dart)。
      見 [design-tokens.md](design-tokens.md) §6.5

### 8.2 登入頁

- [x] 加 `autofillHints` + `keyboardType: emailAddress` + `AutofillGroup` +
      成功後 `TextInput.finishAutofillContext()`。註冊頁一直都有，登入頁沒有
      ——密碼管理員能填你一年用一次的表單，卻不能填你每天用的那個
- [x] 送出改成按鈕內嵌 loading。原本是
      `showDialog(barrierDismissible: false)`，而且只在成功和 `AuthException`
      兩條路上關掉——**其他任何例外都會留下一個全螢幕、點不掉、關不了的
      轉圈**。現在有 `catch` 和 `finally`
- [x] 密碼顯示切換
- [x] 「Forgot password?」，`AuthRepository.sendPasswordReset()`
      （對沒有帳號的信箱一樣回報成功，否則這個表單就變成查詢某個
      email 有沒有註冊的工具）
- [x] 錯誤區塊：原本是沒有內距、沒有圓角的裸紅色 `DecoratedBox`

### 8.3 AddOrder

- [x] 數量減號在 0 的時候 disable（原本永遠是亮的，按了沒反應）
- [x] 數量文字從固定 24pt 改成 `minWidth: 32` + `Semantics`
- [x] 菜單空的時候給一顆「Edit the menu」按鈕
- [x] `PopScope`：籃子裡有東西時返回會先問

### 8.4 一致性

- [x] Insights AppBar 加重新整理（它是一次性 `Future`，其他頁不是 stream 就有
      下拉重整）
- [x] 全 app 剩下的 `Text('Error: …')` 六處全換成 `ErrorView`，並在能重試的
      地方接上 `onRetry`。`store_settings_history_order` 和 `addorder` 的
      錯誤欄位從 `String?` 改成 `Object?`——`ErrorView` 需要原始物件才能分辨
      「被拒絕」（不給重試）和「連線斷了」（給重試）
- [x] Reports 的空期間改成有圖示、有說明、期間含今天時給「Add an order」
- [x] Summary 分頁底部加 Pairings 的指路卡（它是五個可捲動分頁的第五個，
      在手機上根本在畫面外）

### 8.5 無障礙

- [x] 五個純圖示按鈕補 tooltip，現在全 app 零遺漏
- [x] AddOrder 數量加 `Semantics(label: '…')`
- [x] Insights 熱度圖的格子和欄寬改成跟系統字級縮放（上限 1.6×）。
      原本固定 32pt，字級一調大就把自己的數字裁掉——在廚房裡調大字級是常態

### 8.6 首次使用

- [x] 新增 [setup_checklist.dart](../lib/widgets/setup_checklist.dart)，
      放在 Today 頁頂：上菜單 → 填成本 → 設目標 → 邀請同事，四項有進度條，
      點任一項直接過去，回來會重新檢查，四項做完整張卡自己消失。

  目標那項的「完成」判定是**跟預設值不同**（`StoreTargets` 預設
  100 單 / 20000），因為每家新店都是同一組預設值，沒動過和沒看過分不出來。

### 驗證

`flutter analyze` 只剩既有的兩個 `codePoint` 警告；`flutter test` 70 項全過；
`flutter build web --no-tree-shake-icons` 通過。

---

## 9. 第三輪（2026-08-27 晚）

`firebase deploy --only firestore:rules,firestore:indexes` 已執行，
`firebase firestore:indexes` 確認五個索引全部上線，含 `invites(storeId, createdAt)`。

### 9.1 AddOrder：搜尋 + POS 模式

- [x] **搜尋列**。六十道菜分六類仍然要用眼睛找。搜尋結果**不再分類**——
      一份已經篩過的短名單再拆成四個標題、每個底下一道菜，比不拆更難讀
- [x] **POS 模式**，AppBar 右上切換，用 `shared_preferences` 記住
      （`addOrder.posMode`）。**清單模式完整保留**，兩種並存

  設計上的取捨寫在程式裡：清單適合「讀」——一行裡放得下價格、分類和加減；
  但收銀台前的人是站著的、在趕時間、手可能是濕的，56pt 的列配上最右邊
  24pt 的 `−`/`+` 是錯的目標尺寸。格狀模式下**整張磚就是按鈕**（約
  150×140），點一下加一。減號只在數量 > 0 時出現，所以沒點過的磚上
  永遠只有一件事可以做。

  欄數用 `LayoutBuilder` 按寬度算（約 150pt 一格，2–5 欄），手機兩欄、
  平板更多，而不是寫死。

- [x] **購物籃 sheet**。格狀模式下選中的菜散在整個網格裡，底部改成
      「N dishes」按鈕，點開列出目前這張單的每一行、可直接加減

### 9.2 圖表

- [x] **Top dishes 改成橫向長條圖**。原本是十根直柱配 45° 旋轉的菜名——
      菜名長、是類別型、而且常常是中文，這三件事沒有一件能在旋轉之後
      還好讀。橫著排名稱平躺在左邊，長條本身就是排名。高度改成
      `80 + n * 30`，三道菜和十道菜是不同大小的圖，不是同一個框
- [x] **資料標籤依資料點數量開關**（`source.length <= 12`）。單日幾根柱子時
      數字有用；切到月，31 根柱子上壓 31 個數字是一團灰
- [x] **半圓儀表換成進度條**。`SfRadialGauge` 用掉三分之一個畫面說
      「118 / 200，59%」，而那三件事一條長條加一行字就講完了，省下的高度
      留給資訊量高得多的趨勢圖。達標時轉成 `tertiary` 色

  連帶：**`syncfusion_flutter_gauges` 整個相依可以移除了**，已從
  pubspec 拿掉；`chart_theme.dart` 裡沒人用的 `gaugeGradient` 也清掉

### 9.3 第 7–12 項

- [x] **7 訂單歷史篩選**：通路／付款／只看作廢，一排可捲動的 FilterChip，
      AppBar 有 Clear。**刻意做成前端篩選**而不是 Firestore `where`——
      每種組合都要一個複合索引，而這頁本來就是分頁載入最近的訂單；
      對帳的人要的是篩「已經在畫面上的」，作廢單尤其是他們來這裡找的東西。
      篩選中會顯示「N 筆已載入的訂單裡沒有符合的」，不會假裝是空的
- [x] **8 Edit Menu 搜尋**。**篩選狀態下清單會從 `ReorderableListView` 換成
      普通 `ListView`**——在篩過的視圖裡拖曳，會把一個子集推導出的順序
      寫回整份菜單
- [x] **9 Firestore 離線快取**。`configureFirestore()` 放在
      [repositories.dart](../lib/database/repositories.dart)，不是 main.dart——
      要維持「只有 `lib/database/` 碰 `cloud_firestore`」這個不變式。
      手機 SDK 預設開、**web SDK 預設關**，所以同一家店在平板上斷線還能用、
      在筆電上就白畫面
- [x] **10 Reports 跳回今天**。往回翻一個月之後要回來得按三十次前進箭頭。
      期間標題本身變成可點的，右邊多一個今天的圖示
- [x] **11 破壞性按鈕**。新增 `DestructiveButton`（[feedback.dart](../lib/widgets/feedback.dart)），
      Delete / Remove / Void 三處改用 `colorScheme.error`。M3 底下
      `TextButton` 跟旁邊的 Cancel 長得一模一樣，畫面上結果最不同的兩顆
      按鈕看起來一樣
- [x] **12 Insights 期間選單**。自訂 `child` 的 `PopupMenuButton` 沒有漣漪也
      沒有 tooltip，讀起來像說明文字。補上 tooltip、日曆圖示、以及選單裡
      目前項目的勾

### 9.4 順手（不在編號內，但同一批檔案）

- [x] **Today 的最近交易可以點了**。五筆訂單長得跟 View All 後面那些
      一模一樣，就是沒有 `onTap`
- [x] **Logout 會先問**。原本 `onTap: authRepository.signOut` 裸接在一排
      導覽項目中間，手滑一下就要重打密碼

### 驗證

`flutter analyze` 只剩既有的兩個 `codePoint` 警告；`flutter test` 70 項全過；
`flutter build web --no-tree-shake-icons` 通過。

---

## 10. 第四輪：量測而非目測（2026-08-27 深夜）

前三輪都是用眼睛審的。這一輪改成**量**，於是翻出三個前幾輪自己弄進去的問題。

### 10.1 用 Flutter 自己的無障礙準則去測

新增 [test/widgets/accessibility_test.dart](../test/widgets/accessibility_test.dart)，
跑 `flutter_test` 內建的 `meetsGuideline()`：`textContrastGuideline`、
`androidTapTargetGuideline`、`labeledTapTargetGuideline`，淺色深色各一輪，
外加 1.0×／1.5×／2.0× 字級的溢位檢查。共用元件（`StatCard`、`ChangeBadge`、
`ErrorView`、`DestructiveButton`）全數通過。

**這些準則不需要人來判斷好不好看，只判斷能不能操作、能不能讀。**
之後改配色或改版面，跑一次就知道有沒有退步。

### 10.2 把主題的對比值算出來

把 [theme.dart](../lib/theme.dart) 的 ARGB 整數換算成 WCAG 對比值，全部 20 組
前景／背景配對：**Material Theme Builder 產出的配色本身沒有問題**（`onX on X`
一律 6.4:1 以上，深色更高）。只有 `outlineVariant` 在淺色 1.62:1、深色 1.98:1
——那是分隔線用的裝飾 token，本來就不該承載意義。

問題是**我第二輪把 `Colors.black26` 的拖曳把手換成了 `outlineVariant`**。
拖曳把手是在說「這一列可以拖」，屬於 WCAG 1.4.11 的 UI 元件，要 3:1。
改成 `onSurfaceVariant`（8.9:1）。同樣理由：POS 磚未選取時的邊框、
匯入菜單的照片區外框改用 `outline`（4.25:1）。

- [x] `store_settings_edit_menu.dart`、`store_categories.dart` 拖曳把手
- [x] `addorder.dart` 磚邊框、`store_settings_import_menu.dart` 照片區外框
- [x] 圖表的軸線與格線維持 `outlineVariant`——那是真的裝飾

### 10.3 我上一輪做出了一個 40×40 的按鈕

POS 磚角落的減號用了 `visualDensity: VisualDensity.compact`，那會在兩個軸
各減 8pt，把點擊區從 48×48 變成 40×40，低於 Flutter 明文的下限。
**在趕時間的收銀台上，「取消剛剛按錯的那一下」正是最需要一次按中的按鈕。**
拿掉。

### 10.4 最大的一個：整個 app 沒有大螢幕版面

`StatCard` 用 `MediaQuery.size.width / 2 - 30` 決定自己的寬度——那是**視窗**
寬度，不是父層給它的空間。在 1400pt 的瀏覽器視窗裡，一張「半寬」磚就是
670pt，中間浮著一個數字。而你一直是在 web 上測的。

Flutter 的大螢幕指引講得很直白：用約束不要用 `MediaQuery.size`、
不要把手機版面拉開、內容要有最大寬度、超過 600dp 用 NavigationRail。

- [x] `StatCard` 不再自己決定寬度；新增 **`StatCardGrid`**，用 `LayoutBuilder`
      的約束和「單格最大寬度」（240pt）算欄數。手機兩欄，寬視窗四到六格
      正常大小的磚，而不是兩塊巨大的卡
- [x] 新增 **[PageBody](../lib/widgets/page_body.dart)**，內容置中、最大 720pt。
      720 是為了閱讀挑的，不是為了斷點——讓正文維持在 70–80 字元的行長。
      套用在 Today / Insights 之外的所有主頁與**全部 12 個設定頁**
- [x] 登入前的三個畫面用 480pt（表單沒有理由 1400pt 寬），
      並把 login 那顆 `minWidth: MediaQuery.size.width` 的按鈕改成
      `double.infinity`
- [x] **[home.dart](../lib/home.dart) 超過 600dp 改用 `NavigationRail`**，
      量的是 `LayoutBuilder` 的約束不是裝置，所以縮放視窗和分割畫面都對。
      相機取景頁刻意不套 `PageBody`——取景畫面就該填滿

### 驗證

`flutter analyze` 只剩既有的兩個 `codePoint` 警告；`flutter test` **80 項**全過
（原 70 + 新的 10 項無障礙／字級測試）；`flutter build web --no-tree-shake-icons`
通過。

---

## 11. 第五輪規格：先釐清，一次做完

前四輪有幾處改了兩次（幣別掃過還漏四個、`Colors.black26` 換成 `outlineVariant`
之後才發現對比不夠）。這一輪先把每一項的事實查證完、決策定下來，再動手。

### 11.1 已用證據確認的事實

**`PageBody` 包錯層是真的。** 寫了探針測試：800×600 視窗、內容限寬 300pt，
滑鼠滾輪放在側邊空白處——

| 作法 | 中央滾動 | 側邊滾動 |
|---|---|---|
| `Align + ConstrainedBox` 包在捲動容器**外**（目前 12 個設定頁） | 300 | **0** |
| padding 給在捲動容器**內** | 300 | 300 |

Flutter 的 `Scrollable` 只處理落在自己 RenderBox 內的 pointer signal。
**修法：捲動容器維持滿版，用 `LayoutBuilder` 算出左右內距交給它自己的
`padding`。**

**帳號刪除只能走 Cloud Function。** [firestore.rules](../firestore.rules) 裡
`users/{uid}`、`stores/{storeId}`、`orders/{orderId}` 全是
`allow delete: if false`——客戶端一個都刪不掉。用 Admin SDK 的
`getAuth().deleteUser()` 還順帶免掉 `requires-recent-login` 的重新驗證流程
（那是客戶端 `user.delete()` 才有的限制）。

**離線旗標不能掛在現有 stream 上。** `SnapshotMetadata.isFromCache` 存在且
語意正確，但 `.snapshots()` 的 `includeMetadataChanges` 預設 `false`——
重新連線後若資料沒變就不會再吐一次快照，橫幅會卡在「離線」不消失。
**需要一個專屬的 listener 開 `includeMetadataChanges: true`。**

**擁有權只存在 `users/{uid}.role`**，`stores/{id}` 上沒有 owner 欄位，
而 rules 的 `claimsUnusedStore()` 要求 store 不存在才能宣告 owner——
所以店長的 user 文件一旦消失，那間店永遠不可能再有店長。

### 11.2 已定的決策

| 題目 | 決定 |
|---|---|
| 店長刪帳號 | **連整間店一起刪。** 員工／manager 可自由刪自己；店長刪除時遞迴刪掉 store 底下全部資料、所有成員的 users 文件與 auth 帳號。刪除前要求輸入店名確認 |
| 內容最大寬度 | **維持 720pt**（登入表單 480pt） |
| 骨架屏 | **不做。** 現有的轉圈不是問題所在，換成 shimmer 是把一個小噪音換成另一個，而且要碰每一個載入分支 |

### 11.3 這一輪要做的（一次做完）

| # | 項目 | 檔案 |
|---|---|---|
| 1 | `ReadingWidth`：捲動容器滿版、內距置中，取代 12 個設定頁包錯層的 `PageBody` | 新 widget + 12 檔 |
| 2 | 帳號刪除：callable function `deleteAccount` + User Settings 入口 + 店名確認 | `functions/src/account.ts`、`user_settings.dart`、`auth_repository.dart` |
| 3 | 離線橫幅：專屬 listener（監看 `users/{uid}`，`includeMetadataChanges: true`）+ shell 橫幅 | 新 `connection_status.dart`、`home.dart` |
| 4 | `user_settings` 兩處裸 `Text` 換 `ErrorView` | `user_settings.dart` |
| 5 | 兩處單行空狀態統一成「圖示＋說明（＋動作）」 | `store_settings_history_order.dart`、`store_staff.dart` |
| 6 | 最後四處寫死的 `NTD` | `edit_menu`、`import_menu`、`store_settings` |
| 7 | 四個設定對話框的靜默失敗：欄位空白／無效時要說話 | `store_settings.dart` |
| 8 | `user_settings` 五列的 chevron 一致性 | `user_settings.dart` |

### 11.4 實作結果

八項全數完成。`flutter analyze` 只剩既有的兩個 `codePoint` 警告；
`flutter test` **83 項**全過；`flutter build web --no-tree-shake-icons` 通過；
`functions/` 的 `tsc --noEmit` 通過。

**1 — `ReadingWidth`。** 12 個設定頁的約束從捲動容器外面移到它自己的
`padding`。新增
[test/widgets/reading_width_test.dart](../test/widgets/reading_width_test.dart)，
把這件事釘成回歸測試——包含一個**反例**測試，證明舊寫法的側邊真的是死的，
免得日後有人覺得「包一層 ConstrainedBox 比較乾淨」又改回去。
相機取景頁維持滿版。

**2 — 帳號刪除。** 新增 [functions/src/account.ts](../functions/src/account.ts)
的 `deleteAccount` callable：

- 員工／manager：刪掉 `users/{uid}` 與 auth 帳號。**他們鳴過的訂單留著**——
  那是店的帳本，不是個人資料，`createdBy` 變成指向不存在的人
- 店長：先比對前端傳來的店名與真實店名（不符就 `failed-precondition`），
  然後刪 invites → 所有成員的 users → `recursiveDelete(stores/{id})`
  → 同事的 auth 帳號 → **最後**才刪自己的。順序是刻意的：中間任何一步失敗，
  呼叫者仍然登得進來重試，而不是被鎖在一個刪一半的店外面
- 客戶端在 User Settings 底部，紅色、兩段確認，店長那段要求把店名打對

**3 — 離線橫幅。** 新增
[connection_status.dart](../lib/database/connection_status.dart)，一個專屬
listener 監看 `users/{uid}` 並開 `includeMetadataChanges: true`，
`ValueNotifier<bool>` 餵給 shell 頂端的橫幅。**用 `users/{uid}` 而不是 store
文件**：它一定存在、只有一份、rules 本來就讀得到，而且在知道 storeId 之前就能用。

**4–8。** `user_settings` 兩處裸 `Text`、四處 `NTD`、四個對話框的靜默失敗
（現在會說「A store needs a name.」「Enter a tax rate between 0 and 100.」等）、
chevron 一致性。

**順手收斂的：** 空狀態原本有五份——`_EmptyNotice`（Insights）、
`_CenteredMessage`（invites）、`_Message`（passkeys）、`_EmptyState`（categories），
外加兩個只印一行字的畫面。全部收進
[lib/widgets/empty_state.dart](../lib/widgets/empty_state.dart) 的 `EmptyState`。
會這樣做正是因為「不要修同一個地方兩次」——留著五份，下次改空狀態就要改五個地方。

### 11.5 要你執行

```
firebase deploy --only functions:deleteAccount
```

在部署之前，User Settings 裡那顆刪除鍵按下去會失敗（找不到那個 function）。
