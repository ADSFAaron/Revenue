# Revenue App — 重構與功能規劃

> 這份文件是給後續接手的 Claude session 的交接說明。
> 產出於 2026-08-08，分支 `v3`。

## 實作進度（2026-08-21 更新）

**Phase 0-3 已實作完成，Phase 4-5 尚未開始。**

| Phase | 狀態 |
|---|---|
| 0 — security rules、repository 層、註冊流程 | ✅ 完成 |
| 1 — `menuItems` subcollection、`cost`、分類、軟刪除 | ✅ 完成 |
| 2 — `orders` subcollection、counters、`dailyStats`、AddOrder 改寫、作廢單 | ✅ 完成 |
| 3 — 統計頁 Day/Week/Month 真實區間、翻頁、與前期比較 | ✅ 完成 |
| 4 — 菜單工程矩陣、熱度圖、搭配分析、備料預估 | ⬜ 未開始 |
| 5 — Excel 匯出、auditLog UI | ⬜ 未開始 |

已修掉的項目：B1–B9 全部、F1、F2、F3、F5、F6。**仍未修：F4、F7**——
Export 與 Gemini FAB 仍只有 `debugPrint`（分別是 Phase 5 與未排期）。

Phase 0-2 之外另外補的：Firebase Auth 也收進 repository 層了
（[auth_repository.dart](../lib/database/auth_repository.dart)）。原本
`FirebaseAuth.instance` 散在五個畫面，login 與 register 各有一份錯誤碼對照表
且已經走鐘。現在 `grep -rl 'firebase_auth' lib/` 只會列出 `lib/database/`。

實作時與本文件規劃不同之處，見 §7。

---

## 0. 這個 app 的定位

給小型餐飲店（台灣、NTD）自己記帳與分析用。**不是點餐系統** —
店家明確表示不想用外部公司的點餐平台，所以：

- 沒有客人端介面、沒有掃碼點餐、沒有平台抽成
- 店員自己在手機上把品項加一加、送出，等於一台電子化的記帳本
- 核心價值在**事後分析**：什麼賣得好、什麼時段人多、什麼賺錢

**設計時請記住：這是一個分析型 app，不是交易型 app。**
所有結構決策都應該優先服務「查詢與彙總」，而不是「寫入速度」。

---

## 1. 現況問題清單

> ⚠️ 這一節記錄的是 2026-08-08 重構**之前**的狀態，行號連結指向已經改寫過的檔案，
> 不要當成現況讀。哪些已修、哪些還沒修，看文件開頭的「實作進度」。
> 保留原文是為了讓後人看得懂每個結構決策當初在解什麼問題。

### 1.1 明確的 Bug（不是設計問題，是壞的）

| # | 問題 | 位置 |
|---|---|---|
| B1 | 註冊用 `users.add({...})` 產生隨機 doc ID，但所有讀取端都用 `users.doc(currentUser.email)` → **註冊完的帳號永遠讀不到自己的資料** | [register.dart:312](../lib/register.dart#L312) vs [overview.dart:39](../lib/page/overview.dart#L39)、[store.dart:32](../lib/page/store.dart#L32)、[transaction.dart:31](../lib/page/transaction.dart#L31)、[statistics.dart:122](../lib/page/statistics.dart#L122) |
| B2 | 註冊時**完全沒有建立 `store/{storeID}` document**，也沒建預設 menu → 新用戶進去是空的 | [register.dart:310-318](../lib/register.dart#L310-L318) |
| B3 | 付款方式選了但**沒寫進資料庫** — `_paymentMethod` 只留在 state，寫入的 map 裡沒這個欄位 | [addorder.dart:19](../lib/page/addorder.dart#L19)、[addorder.dart:320](../lib/page/addorder.dart#L320) vs [addorder.dart:113-133](../lib/page/addorder.dart#L113-L133) |
| B4 | `_taxRate` 寫死 0，且同樣沒存 | [addorder.dart:20](../lib/page/addorder.dart#L20) |
| B5 | `allorderSave` 第一次算完就快取住、永不失效 → 加了新訂單統計數字不會更新 | [statistics.dart:477-498](../lib/page/statistics.dart#L477-L498) |
| B6 | 單號用 read-then-update，兩台裝置同時點單會撞號 | [addorder.dart:172-175](../lib/page/addorder.dart#L172-L175) |
| B7 | store doc 同時讀 `users` 與 `users2` 兩個不同欄位 | [store.dart:179](../lib/page/store.dart#L179) vs [store.dart:180-191](../lib/page/store.dart#L180-L191) |
| B8 | 累計營業額太長時用 `substring(4)` 硬截字串顯示 | [store.dart:110](../lib/page/store.dart#L110)、[transaction.dart:136](../lib/page/transaction.dart#L136) |
| B9 | **完全沒有 Firestore security rules** — 資料等於全公開 | — |

### 1.2 假的 / 沒接上的 UI

| # | 問題 | 位置 |
|---|---|---|
| F1 | Day / Week / Month 三個分頁是**同一段 UI 複製三次**，餵完全相同的資料，切換無效 | [statistics.dart:210-315](../lib/page/statistics.dart#L210-L315) |
| F2 | 統計頁左右翻頁箭頭 `onPressed: () {}` 空的 | [statistics.dart:350-363](../lib/page/statistics.dart#L350-L363) |
| F3 | 儀表板數字寫死 `currentOrders = 60, expectOrders = 200` | [statistics.dart:180-181](../lib/page/statistics.dart#L180-L181) |
| F4 | Export 按下去只有 `debugPrint` | [statistics.dart:236](../lib/page/statistics.dart#L236) |
| F5 | Transaction 頁 "Last Transactions" 是寫死的假資料（`itemCount: 1`、"Order No" / "Transaction Time" 字面字串），成長率 `+5%` 也是寫死的 | [transaction.dart:171-189](../lib/page/transaction.dart#L171-L189)、[transaction.dart:262](../lib/page/transaction.dart#L262) |
| F6 | 品項排行**沒有日期篩選**，是開店至今的全部累計；也沒有排序 | [statistics.dart:477-498](../lib/page/statistics.dart#L477-L498) |
| F7 | Statistics 頁的 Gemini FAB 只有 `debugPrint` | [statistics.dart:155-162](../lib/page/statistics.dart#L155-L162) |

### 1.3 架構問題

| # | 問題 | 說明 |
|---|---|---|
| A1 | **所有訂單塞在單一 document 的 array 裡**（`tmporder/{storeId}.orders`） | Firestore 單一 doc 上限 1MB；`arrayUnion` 每次改寫整份；每次開統計頁要抓全部歷史。一天 100 單的店幾個月就撞牆。**這是最大的阻礙。** |
| A2 | 品項靠 `name` 字串認人，沒有穩定 ID | 改菜名 → 歷史數據斷成兩道菜 |
| A3 | 刪除菜色是直接從 array 移除 | 下架一道菜就把它的歷史紀錄變成無法解讀的孤兒 |
| A4 | 資料存取邏輯散在各頁面 | `lib/database/firestore.dart` 整個是註解掉的空殼；「讀 user → 拿 storeId → 讀 store」在 4 個檔案裡重複 4 遍 |
| A5 | 沒有營業日概念，用日曆日切 | 凌晨 2 點的單在老闆心裡屬於前一天。做宵夜的店每天營業額都是錯的 |
| A6 | 一張單 = 一個客人 | 一家四口點一單，來客數少算 3 人，客單價嚴重高估 |
| A7 | 集合名稱 `tmporder`（tmp = 暫存？） | 這是正式資料，命名誤導 |

---

## 2. 後端選型：要不要繼續用 Firebase

**結論：Phase 0-4 繼續用 Firebase，但要知道它的天花板在哪，並且把資料存取層隔離好，讓未來換得掉。**

### 2.1 Firebase 的問題不是成本，是查詢能力

成本完全不是問題。Spark（免費）方案給 **1GB 儲存、每天 50,000 次讀、20,000 次寫**，
單店一天 100-300 單根本用不完。

真正的問題是：**Firestore 沒有 GROUP BY。**

Firestore 只支援三個彙總函式：`count()`、`sum()`、`average()`，
而且是對整個查詢結果算出**單一數值**，無法按欄位分組。
官方文件通篇沒有 GROUP BY / 分組彙總。另外這些彙總查詢**不支援即時更新、不支援快取**，
超過 60 秒會 `DEADLINE_EXCEEDED`。

這代表：

- 「每小時營業額」→ 沒辦法一句 query 解決
- 「每道菜的銷量排行」→ 沒辦法
- 「星期 × 小時熱度圖」→ 沒辦法
- 「哪兩道菜常一起點」→ 更沒辦法

**每一個新的分析問題，都必須事先設計一張預先彙總表（rollup），或是把全部訂單抓下來在手機上算。**
這就是為什麼下面 §3 的 schema 一定要有 `dailyStats`。

同樣的問題在 SQL 資料庫是一句 `GROUP BY EXTRACT(HOUR FROM placed_at)` 就解決的。

### 2.2 Firebase 的優勢（不要低估）

1. **離線持久化。** Firestore 內建 offline persistence，斷網照樣寫入、恢復後自動同步。
   餐廳 wifi 不穩是常態，這一點對這個 app 非常實際。
2. 已經接好了 — Auth、Storage 都在用，換掉是實打實的工作量。
3. 不用管伺服器。店家不會想維運一台機器。

### 2.3 替代方案評估

| 方案 | 優點 | 缺點 | 適用時機 |
|---|---|---|---|
| **維持 Firestore + rollup 表** | 不用改、離線最強、免費夠用 | 沒有 GROUP BY，每個新報表都要新設計一張 rollup | **現在建議這個** |
| **Supabase（Postgres）** | 真正的 SQL：GROUP BY、window function、materialized view。分析需求一句 query 解決。有 RLS、有 Flutter SDK、有免費方案 | **離線支援遠弱於 Firestore** — Flutter SDK 沒有內建 offline cache | 當分析需求複雜到 rollup 表管不動時 |
| **Supabase + PowerSync** | 補上 Supabase 的離線弱點：把 Postgres 同步成裝置端的本機 SQLite，app 讀寫本機、背景同步。是目前少數有 first-class Flutter 離線支援的 sync engine | 多一層基礎設施要理解與付費 | 要 Postgres 又要離線時的正解 |
| **PocketBase（自架）** | Go 單一執行檔 + 內嵌 SQLite，內含 auth / realtime / 檔案儲存 / admin 後台，有官方 Dart SDK。MIT 授權、零 vendor lock-in、$6/月 VPS 跑得動 | 要自己維運（備份、升級、憑證）；離線要自己做 | 若「不想被外部公司綁住」延伸到基礎設施層 |
| **純本機 SQLite（Drift / sqflite）** | 完整 SQL，分析能力最強，零成本零延遲 | 多裝置同步要自己做（很難）；換手機資料就沒了 | 單機單店、只有老闆一個人用 |

### 2.4 給後續執行者的建議

1. **現在不要換。** 先把 §3 的 schema 做好，Firestore 撐得住 Phase 0-4。
2. **但要把資料存取全部收進 repository 層**（見 §5.1）。
   這是最重要的一條 — 只要 UI 從來不直接碰 `FirebaseFirestore.instance`，
   未來換後端就是改一層，不是改十個檔案。
3. **觸發換後端的訊號**（出現任一即重新評估）：
   - 開始要做多店比較、跨店報表
   - rollup 表的欄位設計開始互相打架、每加一個報表就要 backfill
   - 需要臨時查詢（ad-hoc query）而不是固定報表
   - 需要跑排程 / 寄報表 → 已經要 Blaze 方案了，那不如直接評估 Supabase
4. 若真的要換，**Supabase + PowerSync 是最接近現有開發體驗又能解決 GROUP BY 的路**。

### 2.5 Cloud Functions 的取捨

`dailyStats` 的維護有兩種做法：

- **Client 端 transaction + `FieldValue.increment()`** ← 建議先用這個。免費方案就能跑，
  `increment` 是原子操作，多裝置同時點單撐得住。
- **Cloud Functions onWrite trigger** — 較乾淨，但**需要 Blaze（付費）方案**。
  等到有多分店或要跑排程再搬。

---

## 3. 新的資料結構

> **前提：使用者已同意清空現有資料，不需要 migration。**

```
users/{uid}
stores/{storeId}
stores/{storeId}/menuItems/{itemId}
stores/{storeId}/orders/{orderId}
stores/{storeId}/dailyStats/{businessDate}
stores/{storeId}/counters/{businessDate}
stores/{storeId}/auditLogs/{logId}
```

`tmporder` collection 整個廢除。

### 3.1 `users/{uid}`

```js
{
  uid, email, displayName,
  storeId,
  role: 'owner' | 'manager' | 'staff',
  createdAt, updatedAt
}
```

**用 Firebase Auth 的 uid 當 document ID，不要用 email。**
email 可以改，改了資料就變孤兒。這同時修掉 B1。

店員清單改成 `where('storeId', '==', id)` 反查，取代 store doc 裡的 `users` / `users2`（修 B7）。

### 3.2 `stores/{storeId}`

```js
{
  name,
  currency: 'TWD',
  timezone: 'Asia/Taipei',
  taxRate: 0.05,
  taxIncluded: true,
  dayCutoffHour: 4,              // 營業日切點，見 A5
  businessHours: { mon: [{ open: '11:00', close: '21:00' }], ... },
  targets: { dailyOrders: 200, dailyRevenue: 30000 },   // 餵儀表板，修 F3
  categories: [{ id, name, sortOrder }],
  createdAt, updatedAt
}
```

**移除 `totalIncome` 與 `orderIndex`。**
累計營業額改由 `dailyStats` 加總；單號改用 counters（見 3.6）。這順帶修掉 B8。

### 3.3 `stores/{storeId}/menuItems/{itemId}`

```js
{
  name,
  categoryId,
  icon,                 // 沿用現有的 MaterialIcons codePoint 字串
  sortOrder,
  price,                // 售價
  cost,                 // 食材成本 ← 解鎖毛利與菜單工程矩陣
  isActive: true,       // 軟刪除，見 A3
  createdAt, updatedAt
}
```

- **穩定的 `itemId`**：修 A2。
- **`cost` 是投報率最高的一個欄位** — 一個欄位解鎖整套菜單工程分析（見 §4.3）。
- **`isActive` 軟刪除**，不要真的從集合刪除。[store_settings_edit_menu.dart:232](../lib/settings/store_settings_edit_menu.dart#L232) 的 `removeMenuItem()` 要改成設 `isActive: false`。
- 可選：`stores/{id}/menuItems/{itemId}/priceHistory/{id}` 記錄調價歷程，用來回答「毛利是什麼時候開始掉的」。

### 3.4 `stores/{storeId}/orders/{orderId}` ← 核心

**一張單一個 document。** 這是整個重構的重點，解決 A1。

```js
{
  orderNo: 42,
  businessDate: '2026-08-08',   // 已套用 dayCutoffHour，字串方便 group/query
  placedAt: Timestamp,
  hourOfDay: 18,                // 0-23，冗餘欄位，見下方說明
  weekday: 5,                   // 1=Mon .. 7=Sun，冗餘欄位

  channel: 'dine_in' | 'takeout' | 'delivery',
  guestCount: 2,                // 見 A6
  tableNo: 'A3' | null,
  paymentMethod: 'cash' | 'credit_card' | 'line_pay' | 'other',   // 修 B3

  items: [
    { itemId, name, categoryId,
      unitPrice, unitCost, qty,
      lineRevenue, lineCost, note }
  ],
  itemIds: ['itm_a', 'itm_b'],  // 供 arrayContains 查詢

  subtotal, discountAmount, discountReason,
  taxAmount, total,             // 修 B4
  totalCost, grossProfit,

  status: 'completed' | 'voided',
  voidedAt, voidedBy, voidReason,

  createdBy, createdAt, updatedAt
}
```

**三個設計決定，實作時不要「優化」掉：**

1. **`items` 裡把 `name` / `unitPrice` / `unitCost` 抄一份進去是刻意的（denormalize）。**
   歷史訂單必須凍結成交當下的價格與成本 —
   否則食材漲價或改一次售價，過去所有月份的毛利報表會被回溯改寫。
   這是 POS 的標準做法。（現有結構的 `details` 已經有存 name/price，這點是對的，要保留。）

2. **`hourOfDay` / `weekday` / `businessDate` 是冗餘欄位，但必須存。**
   Firestore 沒有 SQL 的 `EXTRACT(HOUR FROM ...)`，不能對 Timestamp 分組。
   不存這幾欄，熱度圖就只能把全部訂單抓下來在手機上算 —— 等於回到 A1 的問題。

3. **`status: 'voided'` 而不是刪除 document。**
   作廢單要留痕，這是防員工財務糾紛的基礎。

### 3.5 `stores/{storeId}/dailyStats/{businessDate}` ← 效能關鍵

```js
{
  businessDate: '2026-08-08',
  orderCount, guestCount, voidedCount,
  revenue, cost, grossProfit, discountTotal, taxTotal,

  byHour:     { '11': { orders, revenue, guests }, '12': {...} },
  byChannel:  { dine_in: { orders, revenue }, takeout: {...} },
  byPayment:  { cash: { orders, revenue }, line_pay: {...} },
  byItem:     { itm_a: { name, qty, revenue, cost, profit } },
  byCategory: { cat_1: { qty, revenue, profit } },
  updatedAt
}
```

**存在理由是錢與速度。** Firestore 按「讀取的 document 數」計費。
看一個月報表：讀 30 份 `dailyStats` vs 讀 3000 筆訂單 —— 差 100 倍，
而且手機端不用做重運算。

**Day / Week / Month 三個分頁全部從這裡讀。**
`orders` 集合只有在看「單筆訂單明細」時才碰。

維護方式見 §2.5。寫入訂單時在同一個 transaction 裡 `increment` 對應欄位。

> ⚠️ 注意：`byItem` 是 map，品項多的店要留意 document 大小。
> 單店菜單通常 < 100 項，不會有問題；若超過數百項再考慮拆成
> `dailyStats/{date}/items/{itemId}` 子集合。

### 3.6 `stores/{storeId}/counters/{businessDate}`

```js
{ nextOrderNo: 43 }
```

用 transaction 取號，修掉 B6。**每日重置從 1 開始** —— 台灣小店習慣如此，
也比一個永遠累加的 `orderIndex` 好認。

### 3.7 `stores/{storeId}/auditLogs/{logId}`

```js
{
  action: 'void_order' | 'edit_order' | 'apply_discount' | 'edit_menu_price',
  targetId, before, after,
  byUid, byName, at
}
```

改單、刪單、改價留痕。有請員工才有意義，但欄位先留著。

### 3.8 索引

需要手動建立的 composite index：

- `orders`: `businessDate ASC, placedAt ASC`
- `orders`: `status ASC, placedAt DESC`
- `orders`: `itemIds ARRAY, businessDate ASC`

### 3.9 Security Rules（目前完全沒有，修 B9）

最低限度：

```js
match /stores/{storeId}/{document=**} {
  allow read, write: if request.auth != null
    && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.storeId == storeId;
}
```

改價、刪單、改設定再額外要求 `role in ['owner', 'manager']`。

---

## 4. 要做的分析功能

依「隔天就能改變行為」的程度排序。

### 4.1 現有資料就能算（Phase 3-4）

| 功能 | 說明 | 資料來源 |
|---|---|---|
| **客單價** | `revenue / orderCount`，以及 `revenue / guestCount`（每人平均） | dailyStats |
| **與前期自動比較** | 老闆要的不是「今天 12,000」，是「比上週同一天多 8%」。單一數字沒有決策價值 | dailyStats |
| **星期 × 小時熱度圖** | ⭐ **這是「哪個時段人多」的答案。** 注意是二維 —— 週二晚上跟週六晚上是兩種店，單純的 24 小時長條圖不夠 | `byHour` + `weekday` |
| **品項排行（含日期區間 + 排序）** | 修 F6 | `byItem` |
| **品項 × 時段交叉表** | 「哪個時段哪些賣得好」 | orders `itemIds` + `hourOfDay` |
| **品項搭配分析** | 算 support / confidence / lift：「點了牛肉麵的人有 62% 會加點滷蛋」。**這個 app 的資料結構天生佔便宜** —— 一筆訂單天然就是一個 basket | orders `itemIds` |
| **備料預估** | 由「星期 × 時段 × 品項」歷史推估。**這是唯一會真正改變隔天行為的報表**，其他都是事後諸葛 | dailyStats 多日彙總 |
| **付款方式佔比** | 對帳 + 算手續費成本 | `byPayment` |
| **分類營收佔比** | 「飲料佔營收 18%」→ 判斷要不要加賣 | `byCategory` |
| **通路比較** | 內用/外帶/外送成本結構完全不同（包材、平台抽成） | `byChannel` |

### 4.2 儀表板與翻頁

- Day/Week/Month 分頁接上真實日期區間（修 F1）
- 左右箭頭能翻期（修 F2）
- 儀表板讀 `store.targets`（修 F3）
- Transaction 頁「Last Transactions」接真實資料（修 F5）
- Excel 匯出（修 F4）

### 4.3 ⭐ 菜單工程矩陣（Menu Engineering Matrix）

**這是整份規劃裡最有價值的一項。** 店家問「什麼熱賣」，
但熱賣 ≠ 賺錢。餐飲業從 1980 年代用到現在的標準框架，用「受歡迎程度 × 毛利」兩軸分四類：

|  | 高毛利 | 低毛利 |
|---|---|---|
| **賣得多** | ⭐ **Stars** — 保護它，別亂改 | 🐴 **Plowhorses** — 賣到手軟但不賺，調價或改配方 |
| **賣得少** | 🧩 **Puzzles** — 賺錢卻沒人點，改菜單排版、叫店員推 | 🐕 **Dogs** — 直接下架 |

**Plowhorse 是最陰險的一類** —— 它會出現在目前那張長條圖的第一名，
老闆看了很開心，實際上每賣一份都在稀釋利潤。
**只做銷量排行的報表，永遠找不出這件事。**

實作只需要 `menuItems.cost` 一個欄位。

順帶可算食材成本率（業界抓 30-35%，長期 > 35% 代表定價／耗損／分量出問題；
此為美國餐飲基準，台灣結構略有不同，當警戒線用是合理的）。

### 4.4 明確排除（超出定位，不要做）

- **Prime Cost**（食材 + 人事，業界抓營收 60-65% 以下）→ 需要工時資料
- **庫存周轉、進貨管理** → 需要進貨資料
- 這兩塊要做就是另一個產品了，先不碰。

---

## 5. 實作順序

| Phase | 狀態 | 內容 | 動到的檔案 |
|---|---|---|---|
| **0** | ✅ | 清空 Firestore；寫 security rules；建 repository 層；修註冊流程（uid 當 key、同時建 store doc） | [register.dart](../lib/register.dart)、[firestore.rules](../firestore.rules)、[firestore.indexes.json](../firestore.indexes.json)、[lib/database/](../lib/database/)、[lib/models/](../lib/models/) |
| **1** | ✅ | `menuItems` subcollection + `cost` 欄位 + 分類 + 軟刪除 | [store_settings_edit_menu.dart](../lib/settings/store_settings_edit_menu.dart) |
| **2** | ✅ | `orders` subcollection + AddOrder 改寫（channel / guestCount / paymentMethod / tax 真的寫進去）+ counters 取號 + `dailyStats` 同 transaction 累加 | [addorder.dart](../lib/page/addorder.dart)、[store_settings_history_order.dart](../lib/settings/store_settings_history_order.dart)、[store_setting_history_order_detail.dart](../lib/settings/store_setting_history_order_detail.dart)、[store_settings.dart](../lib/settings/store_settings.dart) |
| **3** | ⬜ | 統計頁重寫（Day/Week/Month 真的能切、箭頭能翻頁、與前期比較） | [statistics.dart](../lib/page/statistics.dart) |
| **4** | ⬜ | 菜單工程矩陣、星期×小時熱度圖、品項搭配分析、備料預估 | 新檔案 |
| **5** | ⬜ | Excel 匯出、auditLog UI | — |

**Phase 0-2 之間資料結構不相容，要一次做完再上。**
Phase 3 之後每一步都能獨立出貨。

> Phase 2 順手把 [transaction.dart](../lib/page/transaction.dart)、
> [store.dart](../lib/page/store.dart)、[overview.dart](../lib/page/overview.dart)
> 也接到新結構了——它們原本讀的是已經廢掉的 `totalIncome` / `orderIndex`，
> 不改就是編不過。這幾頁現在顯示的是真實數字，但「與前期比較」仍是 Phase 3。
>
> Phase 3 要用的資料層已經齊了：`StatsRepository.fetchRange()` 取區間，
> `DailyStats.sum()` 把多天加總成一個，`StatsRepository.shiftBusinessDate()` 前後翻頁。

### 5.1 ⭐ Repository 層（Phase 0 必做）✅ 已完成

所有 Firestore 存取都收在 `lib/database/` 底下的 repository 類別裡：

```
lib/database/
  repositories.dart     ← 共用實例 + loadSession()（讀 user → 拿 storeId → 讀 store）
  user_repository.dart
  store_repository.dart
  menu_repository.dart
  order_repository.dart
  stats_repository.dart
  feedback_repository.dart
lib/models/
  app_user.dart, store.dart, menu_item.dart, order.dart, order_draft.dart, daily_stats.dart
```

原本的 `firestore.dart`（整個是註解掉的空殼）已刪除。
A4 的「讀 user → 拿 storeId → 讀 store」重複 4 遍，收斂成 `loadSession()` 一支。

**UI 層不得直接出現 `FirebaseFirestore.instance`。**
這是 §2.4 換後端能力的前提，也是這次重構最重要的一條紀律。
目前 `lib/` 底下只有 `lib/database/` 這一層會 import `cloud_firestore`——
改動時請維持這件事成立（`grep -rl FirebaseFirestore lib/` 應該只列出 `lib/database/`）。

---

## 6. 待確認事項 → 已確認（2026-08-08）

實作前詢問使用者的結果：

| # | 問題 | 決定 | 實作方式 |
|---|---|---|---|
| 1 | 有沒有請員工？ | 未問（不阻擋 Phase 0-2） | `role` 與 `auditLogs` 欄位／rules 都已就位，UI 留到 Phase 5 |
| 2 | 有沒有做外送平台？ | **有** | `channel` 三種值全開；`stores.deliveryPlatforms[]` 存平台與抽成率，訂單記 `deliveryPlatformId` / `commissionRate` / `commissionAmount`，毛利已扣掉抽成 |
| 3 | 有沒有桌號？ | **不要桌號，只記來客數** | `tableNo` 整組不做；`guestCount` 在點單頁用 stepper 輸入，預設 1 |
| 4 | `cost` 逐項填？ | **欄位做好，可選填** | `menuItems.cost` 允許留空存 0；`ItemStat.marginRate` 在 cost 為 0 時回傳 null，不會把「沒填」誤報成 100% 毛利 |
| 5 | `dayCutoffHour` 預設幾點？ | **要能讓使用者自訂** | 預設仍是 4，但已做成 Store Settings →「Trading day starts at」的 0-23 下拉選單。改設定只影響之後的新訂單，既有訂單保留寫入當下的 `businessDate` |

---

## 7. 實作與本規劃的差異

Phase 0-2 實作時偏離本文件的地方，都是刻意的：

1. **`dailyStats` 不存 `grossProfit`。** 改由 `revenue - cost - commissionTotal`
   在 model 端算出來。少一個要維護正確的欄位，也不可能跟其他欄位對不起來。
   另外多存了規劃裡沒有的 `commissionTotal`（外送抽成，見 §6 第 2 點）。

2. **集合名稱是 `stores`（複數），舊的是 `store`。** 依本文件 §3 的寫法。
   因為資料清空，不需要 migration。

3. **`feedback` 改成一筆一個 document**（`feedback/{feedbackId}`，帶 `storeId` 欄位），
   不再是每店一個 doc 裡塞 `arrayUnion` 陣列——跟 A1 同一個問題，順手一起修掉。

4. **多了 `FeedbackRepository`。** §5.1 說「UI 層不得直接出現 `FirebaseFirestore.instance`」，
   app_settings.dart 是唯一的漏網之魚，補上一個 repository 才算真的做到。

5. **`OrderDraft` / `OrderTotals`（`lib/models/order_draft.dart`）是規劃裡沒有的。**
   點單頁顯示的金額與寫進資料庫的金額用同一段計算，兩者不可能對不上。

6. **編輯訂單若跨營業日，會重新取號。** 單號是每日重置的，沿用舊號會跟新那天的號碼撞在一起。

7. **`orders` 的翻頁查詢用 `placedAt` 單欄索引**（Firestore 自動建），
   §3.8 那三個 composite index 留給依營業日與依品項的查詢。

8. ⚠️ **`firebase.json` 在 `.gitignore` 裡。**
   rules 與 indexes 要靠它的 `firestore` 區塊才 deploy 得出去，
   但那個區塊不會進版控——換一台機器 clone 下來得自己補回去（README 有寫）。
   要一勞永逸就是把 `firebase.json` 從 `.gitignore` 拿掉；
   裡面只有 projectId 與 appId，都是會編進 client 的公開值，不是密鑰。

---

## 8. 參考資料

- [22 Restaurant KPIs to Track — Lightspeed](https://www.lightspeedhq.com/blog/restaurant-kpis/)
- [Top 11 Benchmark KPIs Every Restaurant Owner Should Measure — NetSuite](https://www.netsuite.com/portal/resource/articles/erp/restaurant-kpis.shtml)
- [13 Essential Restaurant POS Reports — Quantic](https://getquantic.com/restaurant-pos-reports/)
- [Menu Engineering Matrix — Toast](https://pos.toasttab.com/blog/on-the-line/menu-engineering-matrix)
- [銷售報表與管理 — iCHEF POS](https://www.ichefpos.com/zh-tw/analytics-management)
- [餐飲POS系統必備報表 — Eats365](https://www.eats365pos.com/tw/blog/post/pos-325)
- [What Is Market Basket Analysis? — LatentView](https://www.latentview.com/glossary/market-basket-analysis/)
- [Summarize data with aggregation queries — Firebase 官方](https://firebase.google.com/docs/firestore/query-data/aggregation-queries)
- [Firestore usage and limits — Firebase 官方](https://firebase.google.com/docs/firestore/quotas)
- [Firebase Pricing](https://firebase.google.com/pricing)
- [Supabase + PowerSync 整合指南](https://docs.powersync.com/integrations/supabase/guide)
- [PocketBase — GitHub](https://github.com/pocketbase/pocketbase)
