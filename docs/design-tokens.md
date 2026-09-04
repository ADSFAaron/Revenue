# Revenue App — Design Tokens（色彩）

> 產出於 2026-08-29，分支 `chore/android-build-upgrade`。
> 唯一權威來源是 [lib/theme.dart](../lib/theme.dart)（Material Theme Builder 產出，
> 以整數色值儲存）。這份文件把那些整數換算成 hex、對上品牌色票名稱、
> 寫清楚每個角色該用在哪，並在最後列出**色彩系統目前沒有涵蓋到的地方**。
> 改色只能改 theme.dart；改完請回來更新這張表。
> 例外只有啟動畫面——那段畫面在 Flutter 之前，走 §4.6 的平台設定。

## 1. 品牌五色與 token 的對應

品牌色票（設計端命名）與程式端 token 的關係：

| 品牌名稱 | Hex | theme.dart 中的角色 | 狀態 |
|---|---|---|---|
| Revenue Green 品牌主色 | `#4A672D` | light `primary` / `surfaceTint`、dark `inversePrimary` | ✅ 完全相符 |
| Growth Green 成長／亮點 | `#A8D46F` | 沒有 `ColorScheme` 角色；實際用在 app 圖示與啟動畫面的光芒（§4.6） | ⚠️ 介面內仍取不到，見 §6.1 |
| Insight Teal 分析／洞察 | `#386664` | light `tertiary` | ✅ 完全相符 |
| Warm Cream 背景底色 | `#F9FAEF` | light `surface` / `surfaceBright` | ✅ 完全相符 |
| Dark Background 深色背景 | `#1A1C16` | light `onSurface`、dark `surfaceContainerLow` | ⚠️ 深色模式真正的底色是 `#12140E`，見 §6.4 |

四個色相家族（綠、橄欖綠、teal、紅）都是同一組 M3 tonal palette 產出，
所以同一階的顏色亮度幾乎一致——這件事在圖表配色上會反咬一口，見 §6.7。

## 2. 完整 token 表

`—` 表示該角色在兩個模式共用同一值（M3 的 `*Fixed*` 系列）。

### 2.1 主色系

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `primary` | `#4A672D` | `#B0D18B` | 主要動作鈕、選取狀態、單系列圖表、heatmap 最濃端 |
| `onPrimary` | `#FFFFFF` | `#1E3702` | 疊在 `primary` 上的文字／圖示 |
| `primaryContainer` | `#CBEEA5` | `#334E17` | 主色的低強度底（chip、強調區塊） |
| `onPrimaryContainer` | `#0E2000` | `#CBEEA5` | 疊在 `primaryContainer` 上 |
| `inversePrimary` | `#B0D18B` | `#4A672D` | 反色表面上的主色（snackbar 內的動作） |
| `primaryFixed` / `primaryFixedDim` | `#CBEEA5` / `#B0D18B` | — | 不隨模式翻轉的主色。目前無人使用 |

### 2.2 次色系（橄欖綠）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `secondary` | `#57624A` | `#BFCBAD` | 圖表第三序列；一般不當文字色 |
| `onSecondary` | `#FFFFFF` | `#2A331F` | 疊在 `secondary` 上 |
| `secondaryContainer` | `#DBE7C8` | `#404A34` | stat card 圓形圖示底、設定檢查清單卡片 |
| `onSecondaryContainer` | `#151E0B` | `#DBE7C8` | 疊在 `secondaryContainer` 上 |

### 2.3 第三色系（Insight Teal）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `tertiary` | `#386664` | `#A0CFCC` | 分析／洞察類強調、圖表第二序列、Menu Engineering 的 Star |
| `onTertiary` | `#FFFFFF` | `#003735` | 疊在 `tertiary` 上 |
| `tertiaryContainer` | `#BBECE8` | `#1F4E4C` | **上漲趨勢**的 badge 底（不是綠色，見 §4.1） |
| `onTertiaryContainer` | `#00201F` | `#BBECE8` | 疊在 `tertiaryContainer` 上 |

### 2.4 錯誤色系（不在品牌五色內，由 M3 預設帶入）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `error` | `#BA1A1A` | `#FFB4AB` | 錯誤圖示、破壞性動作的前景色 |
| `onError` | `#FFFFFF` | `#690005` | 疊在 `error` 上 |
| `errorContainer` | `#FFDAD6` | `#93000A` | 錯誤 snackbar 底、下跌 badge 底、food cost 過高警示 |
| `onErrorContainer` | `#410002` | `#FFDAD6` | 疊在 `errorContainer` 上 |

### 2.5 表面與文字

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `surface` | `#F9FAEF` | `#12140E` | scaffold 底色與 canvas |
| `surfaceDim` / `surfaceBright` | `#D9DBD0` / `#F9FAEF` | `#12140E` / `#373A33` | 目前未使用 |
| `surfaceContainerLowest` | `#FFFFFF` | `#0C0F09` | — |
| `surfaceContainerLow` | `#F3F5E9` | `#1A1C16` | M3 的 Card 預設值，本 app **不用**（見下） |
| `surfaceContainer` | `#EDEFE4` | `#1E211A` | **Card 底色**（[theme.dart](../lib/theme.dart) 內 `cardTheme` 明確指定） |
| `surfaceContainerHigh` | `#E8E9DE` | `#282B24` | 需要再高一階的卡中卡 |
| `surfaceContainerHighest` | `#E2E3D8` | `#33362E` | heatmap 的「零」色、中性資訊卡底 |
| `onSurface` | `#1A1C16` | `#E2E3D8` | 主要文字 |
| `onSurfaceVariant` | `#44483D` | `#C4C8BA` | 次要文字、說明字、空狀態圖示（全 app 用量最高的角色） |
| `outline` | `#74796C` | `#8E9285` | 有意義的邊框；Menu Engineering 的 Dog |
| `outlineVariant` | `#C4C8BA` | `#44483D` | 分隔線。對比僅 1.62:1，**只能當裝飾，不可承載資訊** |
| `inverseSurface` | `#2F312A` | `#E2E3D8` | snackbar 底 |
| `shadow` / `scrim` | `#000000` | `#000000` | 全 app 卡片 `elevation: 0`，實際只有 scrim 會用到 |

Card 為什麼跳過 `surfaceContainerLow`：那一階跟 scaffold 只差一格，卡片會跟背景糊在一起。
往上兩階讓卡片自己站出來，就不必補陰影。理由寫在 [theme.dart](../lib/theme.dart) 的 `cardTheme` 註解。

## 3. 對比度驗證

WCAG 2.1 相對對比，文字門檻 AA 4.5:1、大字 3:1、非文字（圖示／邊框）3:1。

| 配對 | Light | Dark | 判定 |
|---|---|---|---|
| `onSurface` on `surface` | 16.33 | 14.32 | ✅ AAA |
| `onSurfaceVariant` on `surface` | 8.91 | 10.88 | ✅ AAA |
| `primary` on `surface` | 6.10 | 10.90 | ✅ AA |
| `tertiary` on `surface` | 6.13 | 10.86 | ✅ AA |
| `error` on `surface` | 6.14 | 10.93 | ✅ AA |
| `onPrimary` on `primary` | 6.42 | 6.42 | ✅ AA |
| 各 `on*Container` on 對應 container | 13.3 | 7.2 | ✅ AAA / AA |
| `outline` on `surface` | 4.25 | 5.83 | ✅ 非文字 |
| `outlineVariant` on `surface` | 1.62 | 1.62 | ❌ 僅裝飾 |
| Growth Green `#A8D46F` on `surface` | 1.62 | — | ❌ 不可當文字色 |

換算方式：把 [theme.dart](../lib/theme.dart) 的整數 `& 0xFFFFFF` 取 hex，再算 WCAG 相對亮度。

## 4. 語意用法

### 4.1 趨勢（漲／跌）

上漲 = `tertiaryContainer` + `onTertiaryContainer`（teal），下跌 = `errorContainer` + `onErrorContainer`。
**上漲不是綠色**——綠色已經是品牌主色，按鈕、選取態都在用，再拿來表示「漲」會撞色；
而原本的 `Colors.green` on `Colors.green[100]` 只有 2.2:1。
兩者都額外帶方向箭頭（`trending_up` / `trending_down`），顏色壞掉時語意仍在。
實作在 [stat_card.dart:167-190](../lib/widgets/stat_card.dart#L167-L190)。

### 4.2 Menu Engineering 四象限

Star = `tertiary`、Plowhorse = `primary`、Puzzle = `secondary`、Dog = `outline`。
每個象限另有專屬 icon。實作在 [analysis.dart:553-559](../lib/page/analysis.dart#L553-L559)。

### 4.3 圖表

單一調色盤，順序固定，第一個是品牌色：
`primary` → `tertiary` → `secondary` → `primaryContainer` → `tertiaryContainer` → `secondaryContainer`。
定義在 [chart_theme.dart](../lib/widgets/chart_theme.dart)。限制見 §6.7。

### 4.4 Heatmap

`Color.lerp(surfaceContainerHighest, primary, intensity)`；文字在 `intensity > 0.55` 時翻成 `onPrimary`。
從 surface 起跳而非從白色起跳，空白時段才會讀成「背景」而不是「刻意的零」。
實作在 [analysis.dart:726-735](../lib/page/analysis.dart#L726-L735)。

### 4.5 錯誤與警示

錯誤 snackbar 與 `ErrorView` 一律走 [feedback.dart](../lib/widgets/feedback.dart) 的
`showError` / `showFailure`，底 `errorContainer`、字 `onErrorContainer`。不要自己組 `SnackBar`。

### 4.6 啟動畫面與 launch surfaces

App 圖示按下去到 Flutter 畫出第一幀之間，畫面由平台負責，Flutter 的 token 到不了那裡。
規則是**這段期間一律等於 `colorScheme.surface`**，所以交接時看不出接縫。

| 平台 | 檔案 | Light | Dark |
|---|---|---|---|
| Android < 12 | `drawable[-night]/background.png` | `#F9FAEF` | `#12140E` |
| Android 12+ | `values[-night]-v31/styles.xml` 的 `windowSplashScreenBackground` | `#F9FAEF` | `#12140E` |
| Android 交接後的視窗 | `values[-night]/colors.xml` 的 `@color/window_background` | `#F9FAEF` | `#12140E` |
| iOS | `LaunchBackground.imageset`（含 dark appearance） | `#F9FAEF` | `#12140E` |
| Web 載入中 | [web/index.html](../web/index.html) 的 `#loading` | `#F9FAEF` 底 / `#4A672D` 前景 | `#12140E` 底 / `#B0D18B` 前景 |
| Web 瀏覽器 chrome | `meta[theme-color]` + [manifest.json](../web/manifest.json) | `#F9FAEF` | `#12140E` |

### 4.7 Logo 與 app 圖示

Logo 是雙色的：**R 用 `primary`，光芒用 Growth Green**。這是全份文件裡唯一一個
Growth Green 有正式用途的地方。

| | Light | Dark |
|---|---|---|
| R | `#4A672D` `primary` | `#CBEEA5` `primaryContainer` |
| 光芒 | `#A8D46F` Growth Green | `#A8D46F` Growth Green |

深色模式的 R 不是把亮色的 R 調亮而已——`#4A672D` 疊在 `#12140E` 上只有 1.9:1，
等於看不見，所以整個跳到 `primaryContainer`（14.4:1）。光芒兩個模式共用，
在 `#12140E` 上是 10.9:1。兩個色階彼此的對比在亮色模式是 3.77:1、
深色模式 1.32:1——**深色下兩色差距小是可以接受的**，因為 R 與光芒在圖形上本來就
分離、不相鄰，色階在這裡是層次而不是辨識。

光芒在 `#F9FAEF` 上只有 1.62:1，這是 Growth Green 在暖米白上的先天限制，
旁邊就是 6.1:1 的 R，整體仍然讀得出來——但**不要把這個組合搬到介面上當資訊**。

母檔是 [assets/icon/AppLogo.png](../assets/icon/AppLogo.png)，其餘全部由
[tool/logo_assets.py](../tool/logo_assets.py) 產生，不要手改：

```sh
python3 tool/logo_assets.py         # 需要 Pillow 與 NumPy，只在建置時用
dart run flutter_native_splash:create
dart run flutter_launcher_icons
python3 tool/logo_assets.py --web-maskable   # 必須排在上一行之後
```

| 產出 | 用途 | 幾何 |
|---|---|---|
| `AppLogoSplash[Dark].png` | 傳統 splash | 512px，等於顯示 128dp |
| `AppLogoAndroid12[Dark].png` | Android 12+ splash | 1152 畫布、768 圓（平台上限） |
| `AppLogoAdaptive.png` | Android adaptive 前景 | 1024 畫布、外接圓 0.50 |
| `AppLogoMonochrome.png` | Android 13+ 主題化圖示 | 同上，純白剪影 |
| `AppLogoIcon.png` | iOS／Android 傳統／Windows／Web | 1024 不透明，標記佔 0.58 |
| `AppLogoIconDark.png` | iOS 18 深色／tinted | 1024 透明，深色配色 |
| `web/icons/Icon-maskable-*.png` | PWA maskable | 標記佔 0.475，由 `--web-maskable` 覆寫 |

尺寸不是隨意挑的：這個標記的最小外接圓是自身寬度的 **1.263 倍**（R 佔左半、
光芒散向右上右下，四個角都有內容），所以決定大小的是外接圓不是外框。
三個遮罩形狀不同，佔比就得分開算，目標是**標記的外接圓佔可見範圍七成五**：

| 遮罩 | 可見範圍 | 標記佔畫布 | 佔可見範圍 |
|---|---|---|---|
| iOS 圓角方形 | 整張 | 0.58 | 0.73 |
| Android adaptive 圓 | 72/108 | 0.396 | 0.75 |
| PWA maskable 圓 | 0.80 | 0.475 | 0.75 |

Android adaptive 的 66/108 keyline 是**上限而不是目標**——貼著它畫，標記會佔
可見圓的 92%，看起來就是擠。同理 iOS 用過 0.68，圓角一裁就頂到邊。
`flutter_launcher_icons` 產出的 maskable 檔案跟一般檔案是逐位元組相同的複製，
所以那兩張要在它跑完之後重畫，這就是第四個步驟的用途。

母檔是壓縮過的點陣圖：兩個綠量到 `#365A27` 與約 `#95C259`、逐像素有雜訊，
深色邊緣還帶一圈壓縮振鈴，直接縮放會把暗邊帶到暖米白上。
`tool/logo_assets.py` 因此是把標記重建成兩張遮罩再重新上色，
並把兩個綠吸附到 token——量到的那對彼此是 3.83:1，token 這對是 3.77:1，
等於同一個關係。**有向量原稿的話換掉母檔會更好**，邊緣目前仍帶著壓縮的微幅起伏。

Android 與 iOS 的 splash 資產同樣是產生出來的：改
[pubspec.yaml](../pubspec.yaml) 的 `flutter_native_splash:` 之後跑
`dart run flutter_native_splash:create`。
Web 設 `web: false`，由 [web/index.html](../web/index.html) 手寫——理由寫在 pubspec 的註解裡。

## 5. 規則

- 顏色一律從 `Theme.of(context).colorScheme` 取；`Colors.*` 與 `Color(0xFF…)` 只准出現在 §6.5、§6.6 列出的兩塊例外區。
- `on-` 前綴的 token 是**前景色**，不可當底色（曾經在底部導覽誤用，見 [ui-ux-plan.md](ui-ux-plan.md) A2）。
- 不用 `splashColor`：那是 M2 漣漪色，在 M3 沒有語意，疊出來的顏色不可控。要淺底就用 `secondaryContainer`。
- 顏色不可作為唯一資訊通道：漲跌配箭頭、象限配 icon、圖表配圖例。
- 新增顏色 = 先問能不能用既有角色；真的需要新色，改 Theme Builder 重新產生整組，不要手工塞一個 hex。

## 6. 色彩系統尚未涵蓋的地方

以下是這次盤點抓到的缺口，依重要性排列。**多數不是 bug，是「沒被寫下來」或「沒有 token」**。

### 6.1 Growth Green `#A8D46F` 介面內取不到
它現在有正式用途了——logo 的光芒，因此也出現在每一個啟動畫面與 app 圖示上（§4.7）。
但 `ColorScheme` 裡仍然沒有任何角色帶著這個值：最接近的
`primaryContainer #CBEEA5` 與 dark `primary #B0D18B` 都不等於它，
所以介面要用它只能寫字面色，而那是 §5 明文禁止的。
它在暖米白上只有 1.62:1，本來也只能當填充。
**建議**：明文寫成「品牌／插畫用色，不進 `ColorScheme`」，或從 Theme Builder 把它納入產生一組正式角色。
現況是「品牌看得到、程式碰不到」。

### 6.2 錯誤色系不在品牌五色內
`#BA1A1A` / `#FFDAD6` 這一整個家族是 M3 預設帶進來的，色票圖上完全沒提。
它出現在錯誤 snackbar、下跌 badge、food cost 警示——是使用者看得到的第六個色相家族。
**建議**：把它畫進色票圖，否則設計與程式對不上帳。

### 6.3 沒有 success / warning 語意色
系統只有 error 一個狀態色。目前的應急做法是：
「好」用 `tertiaryContainer`（漲）或 `surfaceContainerHighest`（food cost 正常），
「警告」直接借用 `errorContainer`（[analysis.dart:576](../lib/page/analysis.dart#L576) 的 food cost 過高）。
**後果**：警告與錯誤在畫面上長得一模一樣，使用者分不出「該注意」與「壞掉了」。
**建議**：定義 warning（琥珀系）與 success 兩個角色，或明文寫下「本 app 刻意不分警告與錯誤」。

### 6.4 深色模式只給了一個色票
圖上 `#1A1C16` 在深色模式其實是 `surfaceContainerLow`，真正的底色是 `#12140E`。
深色模式還有另外四階 surface（`#1E211A` / `#282B24` / `#33362E` / `#0C0F09`）
與翻轉後的主色 `#B0D18B`、teal `#A0CFCC`——全部沒有出現在色票圖上。
**建議**：色票圖補一列深色模式對照，否則設計稿無法驗收深色模式。

### 6.5 登入前的三個畫面在色彩系統之外 — 已修正

Welcome / Login / Register 原本是刻意的黑底白線手繪風，用 `Colors.black`、
`Colors.grey[700]`、`Colors.greenAccent`、`Colors.yellow`、`Color(0xFFB71C1C)`
等 47 處字面色，並靠 `pre_auth_theme.dart` 把這些路由鎖在 light 主題，避免深色
模式下變成黑字黑底。那個檔案的註解自己說了：那是暫時的守勢，不是修好。

現在：

* 字面色全部改成 scheme token，`pre_auth_theme.dart` 已刪除，這三個畫面跟著
  系統的深淺設定走。
* 兩張 unDraw 插圖的顏色本來就烤進檔案裡，這是「必須鎖在亮色」的根源之一。
  [illustration_palette.py](../tool/illustration_palette.py) 把 unDraw 的每個
  顏色映射到在這裡做同一件事的 token，亮暗各產一份；原始檔留在 `assets/src/`。
* 三處重複的「黑框膠囊 + 3px 偏移外框」按鈕收斂成
  [pre_auth_button.dart](../lib/widgets/pre_auth_button.dart)。那個外框只在白
  紙上成立——黑色是因為背景是白的，深色模式沒有對應值——所以造型（滿寬、60 高、
  全圓角）留下，顏色與所有狀態交給 M3 按鈕。
* 狀態列圖示原本硬寫 `SystemUiOverlayStyle.dark`（深色圖示），在 `#12140E` 上
  是看不見的；現在跟著 brightness 走。

`register.dart` 同時從 1326 行拆成 `lib/register/` 下的四個檔案。

### 6.6 相機拍菜單頁是全黑 UI
[menu_capture_page.dart](../lib/settings/menu_capture_page.dart) 用 `Colors.black` /
`Colors.white70` / `Colors.white24` 共 8 處。相機取景框用純黑是對的，
但它同樣不在系統內、也沒寫進任何文件。
**建議**：文件內明列為「相機／全螢幕媒體例外」，就不會被誤判成待修的字面色。

### 6.7 圖表調色盤只靠色相區分
六個顏色來自同一組 tonal palette 的同一階，亮度幾乎相同——彼此的 WCAG 對比全部在 1.00–1.01。
換算成 CIE Lab 色差：`primary` vs `secondary` 只有 dE 20.9，模擬綠色盲後掉到 16.7
（`#60602E` vs `#5F5F4A`）；`tertiary` vs `secondary` dE 17.6。
**後果**：三序列以上的圖表，若只靠顏色區分，在灰階列印與綠色盲下前三色會糊在一起。
**建議**：圖表序列超過兩條時強制標籤或圖案；或替第三序列換一個明度明顯不同的色階。

### 6.8 沒有透明度／state layer token
程式裡散落 `withValues(alpha: 0.15 / 0.25 / 0.8 / 0.85)` 四個手寫值。
**建議**：M3 的 state layer 慣例是 hover 0.08、focus 0.10、pressed 0.10、disabled 0.38；
要嘛照抄成具名常數，要嘛寫明本 app 不遵守。

### 6.9 圓角、間距、陰影不在本文件範圍
目前只有卡片圓角 12（theme.dart）、badge 8、heatmap 4 三個值散在各處，沒有 token。
色彩以外的 design token 尚未建立。

## 7. 盤點方式（可重跑）

```sh
# 找出色彩系統外的字面色（theme.dart 本身除外）
grep -rn "Color(0x\|Colors\.[a-z]" lib --include="*.dart" | grep -v "^lib/theme.dart"

# 各角色的實際使用次數
grep -rho "colorScheme\.[a-zA-Z]*\|scheme\.[a-zA-Z]*" lib --include="*.dart" \
  | sed 's/.*\.//' | sort | uniq -c | sort -rn
```

```sh
# 啟動畫面用色（應該只會看到 #F9FAEF / #12140E）
grep -rn "#[0-9A-Fa-f]\{6\}" android/app/src/main/res web/index.html web/manifest.json

# 產生出來的資產只准有這幾個 token
python3 - <<'EOF'
from PIL import Image; from collections import Counter; import glob
import numpy as np
for f in sorted(glob.glob('assets/icon/AppLogo*.png')):
    a = np.asarray(Image.open(f).convert('RGBA'))
    op = a[a[..., 3] >= 250][:, :3]
    print(f, ['#%02X%02X%02X' % tuple(c) for c, _ in Counter(map(tuple, op)).most_common(4)])
EOF
```

現況：logo 與 app 圖示已經只用 `#4A672D` / `#A8D46F` / `#CBEEA5` / `#F9FAEF`
四個 token（母檔 `AppLogo.png` 除外，它是壓縮過的原稿）。
Dart 這一側 `grep` 命中 60 處字面色，拆開來是——pre-auth 手繪風 47 處（§6.5）、
相機頁 8 處（§6.6）、`Colors.transparent` 2 處（無色彩語意，
[analysis.dart:125](../lib/page/analysis.dart#L125)、
[store_settings_import_menu.dart:820](../lib/settings/store_settings_import_menu.dart#L820)）、
註解裡提到舊值的 3 處（不是程式碼）。
**扣掉那兩塊例外區，登入牆之內已經沒有任何字面色。**
啟動畫面那一側則只剩 `#F9FAEF` 與 `#12140E` 兩個值。
