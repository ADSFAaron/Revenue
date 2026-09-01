# 折扣與促銷 — 設計計畫

> 產出於 2026-08-30，分支 `v3`。尚未實作，這份文件是實作前的規格。
> 起因：`OrderDraft.discountAmount` / `discountReason`、`Order.discountAmount`、
> `dailyStats.discountTotal`、audit log 的折扣動作、Excel 匯出的折扣欄
> **全部已經存在**，但收銀台沒有任何介面可以打折。也就是說欄位一直在那裡等，
> 只是永遠是 0。

## 0. 先講結論

**不要一次做完整的規則引擎。** 分三期，每一期都能單獨上線：

| 期 | 內容 | 為什麼是這個順序 |
|---|---|---|
| P1 | 手動折扣（整單 / 單品，%或金額）＋ 折扣分攤 ＋ 權限與稽核 | 沒有這層，後面每一種自動折扣都沒有地方落地。**分攤**是整個計畫的地基，不是加分項 |
| P2 | 規則引擎：時段、門檻、通路、品項範圍、自動套用、疊加規則 | 需要 P1 的資料結構才有意義 |
| P3 | 買X送Y、第二件折、組合價 | 只有這一類需要「看整籃再決定」，複雜度是前兩期加起來的量 |

下面每一節標了屬於哪一期。

## 1. 為什麼「分攤」是地基（P1）

折扣如果只記在訂單層（`Order.discountAmount`），下面這些**全部會錯**：

- `dailyStats.byItem[].revenue` — 菜單分析（[menu_engineering.dart](../lib/analysis/menu_engineering.dart)）
  的星級/瘦狗矩陣是拿品項營收算的。整單打九折卻不攤回品項，每道菜的營收都虛高 10%。
- `byCategory[].revenue` — 同上，「飲料佔營收 18%」會偏。
- 毛利 — `grossProfit = total - totalCost - commissionAmount`。`total` 已折，
  `byItem` 沒折，兩套數字對不起來。

**規則**：任何折扣，不管是打在整單還是單品，最後都要攤回 `OrderLine`。
整單折扣按各品項 `lineRevenue` 比例攤，餘數（因為只到元）給**金額最大的那一行**，
這樣加總必定等於訂單折扣，不會差一塊。

```
OrderLine 新增：
  int discountAmount   // 這一行被扣掉多少（已含攤下來的整單折扣）
  int get netRevenue => lineRevenue - discountAmount
```
`_applyStats` 的 `byItem` / `byCategory` 改寫 `netRevenue`。這是一次**寫入格式變更**，
舊訂單沒有這個欄位 → `discountAmount` 預設 0，語意正確，不需要 backfill。

## 2. 稅與抽成的計算順序（P1，必須先定死）

台灣菜單價**內含稅**（`store.taxIncluded = true`），所以順序是：

```
小計 subtotal = Σ lineRevenue
折扣 discount = Σ line.discountAmount          （已攤完）
淨額   net    = subtotal - discount
內含稅：total = net,           tax = net × r / (1+r)
外加稅：tax   = net × r,       total = net + tax
平台抽成：commission = total × rate            ← 折後金額
```

三個要當成決定寫下來的點：

1. **稅在折扣之後算。** 現行 [order_draft.dart](../lib/models/order_draft.dart) 的
   `price()` 已經是 `subtotal - discount` 再拆稅，順序是對的，不用改。
2. **抽成算折後**：外送平台抽的是實收金額。目前 `commissionAmount = total × rate`，
   `total` 已是折後，正確。但**平台自己出資的折扣**（平台促銷，非店家買單）不該
   進這個式子——P2 引入折扣來源欄位時要一起處理，見 §6。
3. **四捨五入只做一次**，在攤到品項那一步。先攤再取整、加總補餘數，不要每步都 round。

## 3. 折扣類型清單（完整）

分成兩軸：**打在哪** × **算法**。

| | 整單 | 單品 |
|---|---|---|
| 百分比 | 全單 9 折 | 這道菜半價 |
| 固定金額 | 折 50 元 | 這道菜折 10 元 |
| 改價 | 整單改成 X（罕見，通常是宴席） | 改價（`open price`） |
| 免費 | 整單招待（通常是內部單） | 送這道 |

再加三種**需要看整籃**的（P3）：

- **買X送Y（BOGO）**：買 2 送 1、買 A 送 B。要決定送的是「第一件 / 最便宜 / 最貴」——
  業界預設是**最便宜的那件**（Toast、Square 都是這個預設），因為對店家最省。
- **第二件 N 折 / 均一價**：第二杯半價、兩件 100。本質是「同群組滿 N 件，對第 k 件套折」。
- **組合價（combo / set）**：指定品項湊齊 → 整組固定價。差價要攤回組成品項（§1）。

**贈品的成本仍然要計。** 送出去的那道菜 `unitCost` 照算進 `totalCost`，
只有 `netRevenue` 是 0。否則 BOGO 會讓毛利率變好看，這是最容易錯的一格。

## 4. 觸發條件（P2）

一條規則 = 條件 AND 條件 AND …：

- **時段**：星期幾 ＋ 一天內的多個時間區間（下午 2–5 點的下午茶、平日 11–14 的午間）。
  多區間是必要的，不是加分（Toast 的 availability 就是多區間）。
- **日期範圍**：`from` / `to`，做檔期。
- **通路**：內用 / 外帶 / 外送（`OrderChannel`），甚至指定平台。外送平台抽三成，
  店家通常**不希望**自家折扣套在外送單上——這一條是台灣店家真的會用的。
- **門檻**：滿 X 元、滿 N 件。門檻要說清楚**用折前還是折後金額**判斷（建議折前，
  否則兩條規則會互相影響到無法預測）。
- **適用範圍**：全部 / 指定分類 / 指定品項。門檻與折抵的範圍可以不同
  （「飲料類滿 100 折 20」）。
- **上限**：最高折抵金額（%折扣一定要有，否則大單失控）。
- **每日/總量上限**：前 20 名。（P3 才做，需要跨裝置計數器，離線會撞——見
  [offline-and-permissions-plan.md](offline-and-permissions-plan.md)）

**時段判斷用哪個時鐘**：用 `placedAt` 的本地時間，不是營業日。晚上 11 點的
happy hour 屬於哪個營業日不重要，重要的是牆上的鐘。

## 5. 疊加規則（P2）— 這裡最容易做錯

業界的做法（Toast / GrowFlow / Atlas 都類似）收斂成四個設定：

1. **每條規則自己標「可否與其他折扣併用」**（`stackable: bool`）。
2. **互斥群組**（`exclusiveGroup: String?`）：同群組只能中一條。
3. **優先序**（`priority: int`）：決定套用順序，順序會影響 % 折扣的基數。
4. **自動折扣選最優**：多條自動規則同時成立且不可疊時，**選對客人最有利的那條**
   （GrowFlow 的預設行為）。理由不是慷慨，是可預測：否則同一籃子在不同裝置上
   可能算出不同結果。

**建議的預設**：自動規則預設 `stackable = false` + 選最優；手動折扣一律可以疊在
自動折扣之上，但要權限（§7）。整單折扣一次只能有一條。

**計算順序固定為**：單品折 → 整單折 → 上限截斷 → 攤回品項 → 稅。
寫成一個純函式（`lib/analysis/` 或 `lib/models/pricing.dart`），輸入籃子+規則+時間，
輸出每行的 `discountAmount` 和套用了哪些規則。**純函式才測得起來**，
這也是 P1 就要把它獨立出來的原因。

## 6. 資料模型（P1 定形，P2 填滿）

```
Order 新增：
  List<AppliedDiscount> discounts   // 這張單實際套到的，快照
  （既有的 discountAmount 保留，等於 Σ discounts.amount）

AppliedDiscount（存在訂單上的快照，不是指標）：
  ruleId      String?   // 自動規則的 id；手動折扣為 null
  name        String    // 「熟客 9 折」——當下的名字，之後改名不影響歷史
  kind        enum      // percent / amount / openPrice / freeItem / bogo / combo
  value       num       // 0.1 或 50
  amount      int       // 實際折抵的元
  scope       enum      // order / line
  lineIds     List<String>?
  fundedBy    enum      // store / platform / campaign   ← 決定抽成與毛利歸屬
  byUid       String?   // 手動折扣是誰按的
  reason      String?
```

**快照而不是指標**，理由跟 `OrderLine` 凍結單價完全一樣：規則之後會被改名、
改成數、停用，但六月那張單當時折了多少是既成事實。這也直接解掉「編輯舊訂單時
規則已經變了」的問題——編輯時**不重跑規則引擎**，除非使用者明確按「重新套用」。

```
Store 新增：
  List<DiscountRule> discountRules   // inline，跟 categories / paymentMethods 一樣
  DiscountPolicy discountPolicy      // 誰能手動折、上限幾 %、要不要理由
```

```
dailyStats 新增：
  Map<String, StatBucket> byDiscount   // 依 ruleId/name 分桶
  （discountTotal 已存在）
```

## 7. 權限與稽核（P1）

手動折扣是收銀短溢的第二大來源（第一是作廢，已經在
[offline-and-permissions-plan.md](offline-and-permissions-plan.md) 處理）。

- 店員可折的**上限**（% 或元）寫在 `DiscountPolicy`，超過要 manager。
- 超過某個門檻**必須填理由**。
- 每一筆手動折扣寫 audit log（`AuditAction` 已有折扣動作，
  [store_settings_audit_log.dart](../lib/settings/store_settings_audit_log.dart)
  已經在讀 `after['discountAmount']`）。
- 報表要能看「這個月折了多少、誰折的」——`byDiscount` 桶 ＋ audit log 就夠。

## 8. UI

- **收銀台**：`_buildSummary` 的小計列旁邊加「折扣」按鈕；自動套到的規則以
  chip 顯示在總計上方，可以單獨取消（取消要記 audit）。單品折扣走長按菜色格。
- **設定**：`Store Settings → Discounts`，跟 payment methods / delivery platforms
  同一套 CRUD 版型（[store_payment_methods.dart](../lib/settings/store_payment_methods.dart)
  可以直接抄）。規則列表顯示「什麼時候、對誰、折多少」一行講完。
- **收據/歷史**：折扣要逐條列出，不能只顯示一個總數。

## 9. 邊界情況清單（實作時逐條打勾）

1. 折扣大於小計 → clamp 到小計，不可為負（現行 `price()` 已經 clamp，保留）。
2. 折扣 + 內含稅 → 稅額跟著變小，收據上的稅額要重算，不能沿用原稅額。
3. 作廢一張有折扣的單 → `_applyStats(-1)` 要把 `discountTotal` 和 `byDiscount` 一起扣回。
4. 編輯一張有折扣的單 → 預設保留快照；若品項變了，比例攤的分母就變了，
   **必須重攤**（金額不變、分攤變）。
5. 規則被刪 → 歷史訂單靠快照顯示，跟 payment method 的處理一致。
6. 兩條規則都成立但互斥 → 選最優；相同金額時取 `priority` 小的，再相同取 id，
   **必須是決定性的**，否則兩台機器算不一樣。
7. 贈品成本 → 進 `totalCost`（§3）。
8. 外送單 → 平台出資的折扣不進店家毛利也不減抽成基數（`fundedBy`）。
9. 離線 → 規則來自快取的 store 文件，可能是舊的；折扣是**當下算、快照存**，
   所以離線算出來的就是那張單的事實，不需要回線後重算。
10. 時段規則跨午夜（22:00–02:00）→ 區間要允許 `to < from`，判斷式要處理繞圈。
11. 幣別只到元 → 所有 % 折扣結果 `round()`，攤分餘數補在最大行。
12. 每日限量 → 需要跨裝置原子計數，離線無解，P3 再處理。

## 11. 補漏 —— 第一版沒列到的（2026-08-30 第二輪）

被問到「確定只有這些嗎」，答案是**不確定，而且漏了七項**。補在這裡：

### 11.1 服務費（加一成）— 這個影響計算順序，優先度最高

app 現在**完全沒有服務費**的概念。內用加一成在台灣很常見，而它跟折扣是反向操作，
順序必須定死：

```
淨額 = 小計 - 折扣
服務費 = 淨額 × 10%          ← 折後才加，不然等於折扣被服務費吃掉一部分
total = 淨額 + 服務費（內含稅則從 total 反拆稅）
```

要當成獨立欄位存（`Order.serviceCharge`），不能混進 `total` 就算了 ——
服務費在會計上是另一個科目，而且外送通常不收。**建議跟折扣 P1 一起做**，
因為兩者共用同一條計算管線，分兩次做等於改兩次。

### 11.2 禮券／儲值金：一筆錢只能認列一次

**前一版這裡寫「禮券是付款方式不是折扣」，那句話少講了前提，會誤導。**
正確的問題不是「折扣還是付款方式」，是**營收在哪一天認列**——賣券那天，
還是兌換那天。選定一天，另一天就不能再算一次。

賣券的時候如果有開單記營收，那筆錢**已經算過了**；兌換時再記一次營收就是
重複計算，當月營收會憑空多出禮券的面額。

兩套一致的做法，選一套：

| | 方案 A：賣出時認列 | 方案 B：兌換時認列 |
|---|---|---|
| 賣券 | 開單，營收 +500 | **不是銷售**，是預收款。錢進抽屜、不進營收 |
| 兌換 | 出餐但**不再記營收**（金額 0 或標記已預收）| 正常開單，營收 +500，付款方式＝禮券 |
| 報表 | **會歪**：賣券日毛利 100%（有營收無成本），兌換日毛利 −100%（有成本無營收）。菜單分析裡那幾道菜看起來是白送的 | 正確：營收落在真正出餐那天，成本、毛利、客單價、菜單分析全部對得上 |
| 抽屜對帳 | 對得起來 | 賣券日現金多 500 而營收沒有，**需要一筆「非營收收款」的紀錄** |
| 還要什麼 | 「不計營收的訂單」旗標 | 未兌換餘額（負債）的追蹤 |

**選哪一套不是偏好，是券的種類決定的**（依統一發票使用辦法第 14 條，
國稅局多次重申）：

- **商品禮券**（券上載明可兌換一定數量的貨物，如「憑券兌換牛肉麵一碗」）
  → **售出時**開立統一發票 → 稅務上營收認在賣券那天 → **方案 A**
- **現金禮券**（券上只載明金額，視同以現金消費）
  → **兌付貨物時**開立統一發票 → **方案 B**
- **儲值**（客人先存錢進帳戶）：國稅局對預收款一般要求**收款時**開立發票，
  時點接近 A，但商業管理上多半當 B 在做。這一格務必問記帳士，不要照這份文件辦。

**app 現在兩套都做不到**：沒有預收款/負債的概念，也沒有「不計營收的訂單」。
最小可行的一步是——

- 走 A：加一個「不計營收」的訂單標記（或獨立通路），讓兌換單有成本、有出餐紀錄，
  但不進 `revenue`。跟 §11.3 的招待單是同一個機制，可以一起做。
- 走 B：「禮券」開成一個付款方式（**現在就做得到**），另外記未兌換餘額。

**「儲 1000 送 100」的那 100** 是第三個問題：它是贈與，不是折扣，
應該在兌換時按比例攤進成本，不是在儲值時記一筆折扣。這一格等 A/B 選定再談。

**決定（2026-08-30）：整套暫緩，只留文件。** 走 B 的話「禮券」就是一個付款方式，
而付款方式**現在已經可以自訂**，所以真的有店家在用禮券時，當天就能開一個。
未兌換餘額（負債）的追蹤**不做** —— 那是記帳的範圍，不是收銀機的，而且在還沒有
任何一家店真的發券之前，做出來的一定是猜的。等有店家實際碰到再回來讀這一節。

### 11.3 招待 / 員工餐（comp）算不算一張單

整單免費的單有三種記法，會得到三種報表：

| 記法 | 訂單數 | 營收 | 客單價 | 成本 |
|---|---|---|---|---|
| 100% 折扣 | +1 | 0 | 被拉低 | 計入 |
| 獨立通路（staff） | +1（可從報表排除）| 0 | 可排除 | 計入 |
| 不開單 | 0 | 0 | 不變 | **漏掉** ❌ |

**建議**：獨立通路或獨立折扣類型 + 報表預設排除在客單價之外，但**成本一定要計**，
否則食材消耗對不起來。這一格不決定，「客單價」這個數字就是髒的。

### 11.4 沒有客戶資料 → 會員折扣現在做不了

「熟客 9 折」需要認得出這位客人，而 app 裡**沒有任何客戶/會員的概念**。
在加入客戶資料之前，會員折扣只能是「店員手動按的一個按鈕」，
自動套用是不可能的。這決定了 P2 的規則條件裡**不能有「會員等級」這一項**。

### 11.5 電子發票與折讓單

如果之後要開統一發票（B2C 電子發票），折扣必須**在開立前**反映在發票金額上。
發票開出去之後才折 → 要開**折讓證明單**，那是另一套流程和另一份文件。
影響：折扣不能事後補記，「編輯昨天那張單加個折扣」在有發票的情況下是不合法的操作。
現在沒接發票所以還好，但接了之後 §7 的權限要再收一層。

### 11.6 時段特價：折扣 vs 第二套價格

下午茶時段咖啡 50 元，有兩種做法，報表意義完全不同：

- **折扣規則**：原價 60 記營收 60、折扣 10 → `discountTotal` 看得到促銷成本。
- **時段菜單價**（Toast 的 menu-specific pricing）：直接記營收 50，沒有折扣紀錄。

**建議走折扣**，因為店家真正想知道的是「這個促銷花了我多少」，
時段改價會讓那筆錢消失在營收裡看不見。但這是決定，不是唯一解。

### 11.7 其他小的

- **取消自動折扣之後又改籃子**：要不要重新自動套用？建議**不要**（sticky removal），
  店員手動取消過的，就當這張單不套用，否則會出現「刪不掉的折扣」。
- **取整方式**：`round()` 還是無條件捨去到元 / 到 5 元？台灣不少店習慣捨去到 5 元。
  這要變成設定，不能寫死。
- **退款**：app 目前只有作廢（整單），沒有部分退款。折扣做完之後，
  「退其中一道菜」會需要決定折扣要不要按比例退回。

## 10. 參考

- [Toast — Discount types](https://doc.toasttab.com/doc/platformguide/adminDiscountTypes.html)
- [Toast — 自動套用折扣](https://doc.toasttab.com/doc/platformguide/adminAutoApplyDiscounts.html)
- [Toast — BOGO 設定](https://doc.toasttab.com/doc/platformguide/adminDiscountsConfigureBogo.html)
- [Toast — 折扣的可用時段](https://doc.toasttab.com/doc/platformguide/adminDiscountAvailability.html)
- [Toast — 折扣對價格的影響（分攤）](https://doc.toasttab.com/doc/platformguide/adminDiscountPricing.html)
- [GrowFlow — 折扣疊加與「選最優」](https://help.growflow.com/en/articles/6977150-retail-discount-stacking)
- [Atlas — 訂單層與品項層折扣的併用限制](https://help.atlas.kitchen/merchant-portal/add-discounts)
- [Microsoft Dynamics — mix and match 的資料模型](https://learn.microsoft.com/en-us/dynamics365/commerce/price-adjustments-discounts)
- [財政部中區國稅局 — 營業人銷售禮券應依規定開立統一發票](https://www.ntbca.gov.tw/singlehtml/3c844e426e9c4b5ebcaaa18694d7e230?cntId=4c7b5eedc63f44f1b3f8fcddb12ce7ab)
- [商品禮券與現金禮券開立統一發票時限大不同](https://www.grandcpa.com.tw/NewsDetail.php?REFDOCTYPID=0lxxizzin9028kar&REFDOCID=0nyxlijeg6vj5yuk)
- [財政部稅務入口網 — 預收貨款已開立發票後，實際發貨時是否須再開](https://www.etax.nat.gov.tw/etwmain/tax-info/understanding/tax-q-and-a/national/business-tax/collection-prcedure/EwKADRM)
