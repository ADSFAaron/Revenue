# 登入、操作者切換、權限 — 現況與計畫

> 產出於 2026-09-03，分支 `v3`。
> §1–§2 是**需求與已定決策**；§3–§5 是**現況分析**（已經是這樣，不是計畫）；
> §6 起是要做的事。
>
> 相關：[離線行為、資料衝突、權限分級](offline-and-permissions-plan.md)、
> [UI/UX 計畫](ui-ux-plan.md)。

## 1. 需求

平板放在櫃檯，一個班次有多個店員經手。目前的行為是**帳號密碼登入一次之後
就一直登入**，所以：

- 誰打的單分不出來。`Order.createdBy` 有值，但共用帳號時每筆都是同一個 uid。
- 店家在意商業機密，需要一套講得出口的資料安全設計。
- 離職員工目前**永遠是這家店的成員**（§5.1）。

**威脅模型：防疏忽，不防蓄意。**

店主的立場是「如果他們高興要共用一組帳號，我也擋不了」。這句話定義了整個
設計的成本上限——要擋的是**沒注意到自己正用別人的身分打單**，不是兩個店員
串通互相報帳號。這個區分讓底下所有便宜的做法都成立；如果哪天要防蓄意冒名，
整套要重做，不是加東西。

**設計預設：店員各自有帳號。** 共用一組是店家自己的選擇，App 不阻止，
也不為了那種店家犧牲正常情況的體驗。

## 2. 已定的決策

| # | 決策 | 理由 |
|---|---|---|
| 1 | 選人畫面顯示**全店員工**，不只本機登入過的 | 新員工不用先知道要點「其他人」。代價是員工清單要快取（§5.4） |
| 2 | 逾時換人時**草稿必須保留並提示** | 打到一半的單被清掉會直接摧毀對這功能的信任 |
| 3 | PIN、指紋**都是可選**，店家自己決定，全部不開也行 | 早餐店和居酒屋的櫃檯節奏差太多，強制一定有一半的店不對 |
| 4 | 移除離職員工是 **owner / manager 專屬** | 需要 rules 支援，目前**做不到**（§5.1） |
| 5 | **離線時可以換人** | 歸屬變成「宣告」而非「驗證」，在上面的威脅模型下可接受 |

### 2.1 生物辨識無法做責任歸屬（技術事實，不是選擇）

Android 與 iOS 的生物辨識 API **只回傳成功或失敗，不回傳是哪一根手指**。
指紋樣板不離開 TEE，平台刻意不提供識別。所以「用哪個指紋登入對應帳號」
在任何平台都無法實作。

更根本的是：共用平板上全部店員的指紋都註冊在同一台裝置，驗證的是
「一根註冊在這台平板上的手指」，不是「這個特定的人」。就算用 passkey 加
帳號選單，A 一樣可以選 B 的帳號、用自己的指紋解開。

**結論：生物辨識只能當「防陌生人拿起沒人看管的平板」的鎖，不能當身分證明。**
UI 文案也不該暗示它是後者。

### 2.2 真正要解決的是「共用比切換便宜」

店員共用帳號通常不是想共用，是**登出再登入太慢**。所以目標不是加驗證，
是讓誠實的路比偷懶的路更快。passkeys 在這裡剛好對：點名字 → 指紋 → 進去，
兩秒，不用打字。

## 3. 四個狀態

```
A 裝置未認領 ──有邀請碼──→ 註冊 ─┐
  （全新平板）  └建立新店家────→ 登入 ┴─→ C

B 選擇操作者 ──點名字 + 指紋/PIN──→ C
  （新的主畫面） └「其他人」──→ 登入表單 ──→ C

C 營運中     ──「換人」或閒置逾時──→ B
  角落常駐「目前操作者：X」 └進背景（若開啟裝置鎖）──→ D

D 鎖定       ──指紋──→ C（回到同一個人）
```

**最關鍵的是 D ≠ B。** 鎖定是「我馬上回來」，選人是「換別人」。混成一個
畫面的話，每次拿起平板都要重選一次人，慢到大家寧可共用帳號——正好繞回
要解決的問題。

### 3.1 登入不再是前門

註冊本來就是邀請碼制（`lib/register.dart:492`「Invite code first, account
second」，六位碼、單次使用）。三個畫面的實際出現頻率跟現在的資訊架構相反：

| 畫面 | 頻率 |
|---|---|
| 選擇操作者 | 每天數十次 |
| 登入表單 | 每位員工每台裝置一次 |
| 註冊 | 每位員工一輩子一次 |

`lib/login.dart` 目前是前門，新架構裡它只是選人畫面的一個分支。
這是這次改動最大的認知轉變，不是把登入畫面畫好看一點。

## 4. 現況：程式已經有什麼

歸屬管線大致鋪好了，缺的不是欄位：

| 東西 | 位置 | 狀態 |
|---|---|---|
| `Order.createdBy` / `voidedBy` | `lib/models/order.dart` | 有欄位，線上路徑有寫入 |
| `AuditLog.byUid` / `byName` | `lib/models/audit_log.dart` | 有，且 rules 釘死 uid |
| `UserRole` owner/manager/staff | `lib/models/app_user.dart` | 有，`canManage` 已在用 |
| 邀請制員工帳號 | `lib/database/invite_repository.dart` | 有，六位單次碼 |
| 五分鐘自行更正窗口 | `kStaffCorrectionWindow` | 有，rules 與 UI 兩邊都實作 |
| passkeys | `lib/database/passkey_repository.dart`、`functions/src/passkeys.ts` | 有，Cloud Function 當 relying party |
| **顯示是誰打的單** | — | **完全沒有。`Order.createdBy` 全 App 沒有任何一處讀取** |
| `local_auth`（裝置鎖） | — | 未安裝 |

最後兩列是重點：`createdBy` 目前是**只寫不讀**的欄位。這表示今天不會因為
懸空 uid 跳 error（因為沒人渲染它），但也表示**責任釐清這個功能實際上還不
存在**。

### 4.1 已修（2026-09-03）

離線鳴收的訂單過去 `createdBy` 一律是 null：`lib/page/addorder.dart` 線上
路徑有帶 `authRepository.currentUid`，但 `PendingOrderQueue.flush()` 呼叫
`submit()` 時完全沒傳。最需要歸屬的那條路上它不存在。

已改為在**排入佇列的當下**捕捉（`PendingOrder.createdBy`），flush 時送出。
時間點是關鍵：flush 時才讀當前登入者會比 null 更糟——佇列在回線時排空，
那可能是別人的班，把單記到錯的人頭上是偽造紀錄，不是缺漏紀錄。

## 5. 現況：Firestore rules 的缺口

`firestore.rules`（414 行）整體寫得紮實：invite 的欄位凍結、`createdAt`
釘伺服器時鐘、`auditLogs.byUid` 釘 `request.auth.uid`、passkey 集合對客戶端
全關、檔尾誠實記下 `dailyStats` 可被竄改這個已知問題。新設計大部分不用動它。

以下是要處理的。

### 5.1 ~~【最嚴重】沒有任何方法把離職員工移出店家~~ —— 已修（2026-09-04）

```
match /users/{uid} {
  allow update: if signedIn() && (
    (request.auth.uid == uid && keepsOwnStoreAndRole()) ||
    managerChangingSomeoneElsesRole(uid)
  );
  allow delete: if false;
}
```

三條路全堵死：`delete` 是 `false`；改自己時 `keepsOwnStoreAndRole()` 釘住
`storeId` 和 `role`；經理改別人時 `managerChangingSomeoneElsesRole()` 同樣
釘住 `storeId`，只准在 `staff` / `manager` 之間換。

**結果：員工離職後永遠是成員**，`memberOf()` 給的東西全部保留——訂單、
菜單、每日營收。對一個主打商業機密在意的 App，這是整份 rules 裡最要緊的事。

先分清楚兩種移除，它們完全不同：

- **從這台裝置移除**（平板不再記住這個人）→ 純本機，不碰 Firestore。
- **從店家移除**（離職）→ 撤銷成員資格，**目前無路可走**。

**建議修法**：`users/{uid}` 加 `active` 布林欄位，`memberOf()` 要求
`me().active == true`，經理可翻掉別人的（永不能翻自己的、不能翻 owner 的）。

比「把 `storeId` 設成 null」好，因為 null 之後那個人再也回不來——`allow
create` 只管建立文件，文件已存在就沒有重新加入的路徑，而餐飲業回鍋很常見。

**附帶問題**：owner 只有一個且不能移除，所以**沒有頂讓或交接的路徑**。
現在不用解，但要知道。

**已實作（2026-09-04）**，照上面的建議：

- `memberOf()` 加 `me().get('active', true) == true`。**預設 true 是必要的**——
  既有的 user 文件全都沒有這個欄位，讀成 false 等於部署當下把每一家店鎖在
  自己的帳本外面。
- `users/{uid}` 的 `allow read` 把同事那一支從 `meExists() && storeId 相同`
  換成 `memberOf()`，所以被移除的人連同事清單都讀不到；**自己的文件仍然讀得到**
  ——不然 app 只能對他顯示 permission-denied，而不是一句話。
- 自己更新自己時 `active` 被釘住（`keepsOwnStoreRoleAndAccess`）。自我更新
  刻意不走 `memberOf()`（被移除的人還是要能改自己的名字），所以不釘就等於
  「移除」可以自己寫回來。
- 經理改別人時改成**列舉可改欄位**：`diff().affectedKeys().hasOnly(['role',
  'active', 'updatedAt'])`。這正是 users.test.js 早先留下的那條註記——舊規則
  只釘五個欄位、對其餘沉默，在有規則開始信任某個欄位之前都無害，而 `active`
  就是那個欄位。
- App 端：`AppUser.active`、`UserRepository.setActive()`、`loadSession()` 在
  `active == false` 時丟出一句話而不是等第一個被拒的讀取、Store Staff 頁的
  溢出選單有「Remove from store / Put back on the team」，被移除的人留在清單
  底部（不然沒有地方把他放回來）。
- `test/rules/users.test.js` 共 110 項通過，含「沒有 `active` 欄位的舊文件仍是
  成員」這條明寫出來的迴歸測試。

### 5.2 `orders.createdBy` 在建立時沒有約束——這是個取捨

`auditLogs` 把作者釘死了：

```
allow create: if memberOf(storeId) &&
  request.resource.data.byUid == request.auth.uid && ...
```

`orders` 沒有：

```
allow create: if memberOf(storeId) && stampedByTheServer();
// stampedByTheServer() 只檢查 createdAt
```

要講精確：**寫入者有驗證**——`memberOf(storeId)` 確認呼叫者是這家店的成員，
非成員寫不進來。**沒有驗證的是 `createdBy` 的內容**，它可以填任何 uid，
包括不是這家店的人。（更新時有釘，`keepsItsOwnClock()` 顧到了。）

決策：

| 做法 | 得 | 失 |
|---|---|---|
| 釘成 `request.auth.uid` | 歸屬不可偽造 | **離線換人變不可能**，flush 時的 session 是誰就只能記誰 |
| 維持不釘 | 離線換人可行（決策 5） | 歸屬是「宣告」而非「驗證」 |

依 §1 的威脅模型選**不釘**，但要在 rules 裡寫下這是刻意的決定和理由——
這份檔案其他每個決定都寫了，只有這個是意外。

### 5.3 PIN 不能放在 `users/{uid}`

```
allow read: if signedIn() &&
  (request.auth.uid == uid || (meExists() && resource.data.storeId == me().storeId));
```

**全店員工互相讀得到彼此的 user 文件**（這也正是決策 1 的選人清單所依賴的
規則）。所以 PIN 就算雜湊過也不能放進去——等於每個員工都拿得到所有同事的
雜湊，離線慢慢爆破。

依決策 3，**PIN 只存本機、不同步**。換裝置要重設，可接受。這也順帶避開了
「rules 無法驗證客戶端 PIN」這件事：PIN 是便利鎖，不是授權機制，不該有任何
資料存取取決於它。

### 5.4 離線：rules 不執行，快取要暖

`cloud_firestore` 在行動端預設開啟離線持久化，所以選人畫面只要在有網路時
讀過同事清單，離線就在快取裡。查詢形狀要一致才會命中，這是唯一的實作細節。

本質限制：**rules 在離線時不會執行**，讀取直接由本機快取滿足。所以剛被停用
的員工，在那台平板重新連線同步前仍讀得到快取資料。這是 offline-first 的固有
性質，不是 bug。店主已確認可接受。

## 6. 帳號刪除與懸空 uid

`functions/src/account.ts` 的實際行為：

| 誰離開 | 發生什麼 |
|---|---|
| **非 owner** | `userRef.delete()` + `getAuth().deleteUser(uid)`。**訂單留下**——「they are the store's books, not the person's」 |
| **owner** | 整間店 `recursiveDelete`，加上所有成員的 user 文件。因為 ownership 只存在於 `users/{uid}.role`，owner 的文件消失會留下一間永遠不能有 owner 的店 |

所以非 owner 離開之後，那些訂單的 `createdBy` 是**懸空的 uid**——對應不到
任何 user 文件。這正是預期行為，訂單是店家的帳，不該因為人走了就消失。

**會不會跳 error：今天不會**，因為沒有任何地方讀 `Order.createdBy`（§4）。
但這次要做的就是把它讀出來，所以實作時必須處理：

- 查不到 user 文件時顯示「已離職員工」之類的字樣，**不是**空白、不是原始
  uid、更不是拋例外。
- 歷史訂單、稽核紀錄、報表匯出三個地方都要一致。
- 員工名字應該在**顯示時**查，不要把名字複寫進訂單文件——那會讓改名不同步，
  而且訂單是不可變的帳。

## 7. 分階段

**Phase 1 — 讓歸屬先有意義**（不動流程，風險低）
1. ~~修離線 `createdBy` 為 null~~（已完成 2026-09-03）
2. ~~rules 加 `active`，補上移除離職員工的路徑（§5.1）~~（已完成 2026-09-04）
3. ~~歷史訂單、稽核紀錄顯示是誰，含懸空 uid 的處理（§6）~~（已完成 2026-09-04）
   —— `UserRepository.staffNames()` 一次查一份、快取到店家有人寫入為止；
   `StaffNames.labelFor()` 分開三種狀態：查得到＝名字、查不到＝「Former
   staff」、根本沒有 uid＝「Not recorded」。稽核紀錄優先用**現在**查到的名字
   （改名會跟著變），查不到才退回寫入當下複寫的 `byName`——帳號被刪掉時那是
   唯一還留著的線索。報表匯出目前是 `dailyStats` 彙總、沒有逐筆列，所以第三處
   要等 A4 的逐筆 CSV 才有地方放。
4. ~~`orders.createdBy` 的取捨寫進 rules 註解（§5.2）~~（已完成 2026-09-04）

**Phase 2 — 選人畫面**
5. ~~操作者概念與「目前操作者：X」常駐指示~~（已完成 2026-09-04）——
   `OperatorChip` 放在 [addorder.dart](../lib/page/addorder.dart) 的 AppBar，
   因為那是「弄錯就變成假紀錄」的那一屏；點它就是交接。
6. ~~選人畫面（全店員工，本機有 session 的排前面）~~（已完成 2026-09-04，
   **範圍與原計畫不同，見下**）
7. ~~閒置逾時退回選人，長度做成店家設定，草稿保留（決策 2、3）~~
   （已完成 2026-09-04，**做法與字面不同，見下**）

**「全店員工」做不到，只能是「這台裝置上有誰」。** 選人畫面出現在**登入前**，
而列出同事需要讀 `users` 的 storeId 查詢——那條規則要求 `memberOf()`，登出狀態
下必然被拒。所以名單只能來自本機：
[device_accounts.dart](../lib/database/device_accounts.dart) 記下曾在這台裝置
登入成功過的人（uid／名字／email／這台裝置上屬於他的 passkey credential id），
最近用過的排前面。它**不存任何憑證**，點名字之後仍然要通過 passkey、密碼或
Google。第一個人一定得走一次完整登入，這是無法避開的。

**passkey 必須能指定人，否則選人畫面是兩層選單。** credential 是
discoverable 的，所以原本的 `beginPasskeyAuthentication` 不帶
`allowCredentials`，作業系統會自己列出所有 passkey 讓人挑——在剛剛才點過自己
名字的畫面上，等於要他從同事清單裡再挑一次自己。現在該 callable 接受
`credentialIds`，由裝置端傳自己記下的 id。**這不是驗證的一部分**：assertion 仍
由 `finishPasskeyAuthentication` 依照 authenticator 實際簽出的 id 去查公鑰驗
證，`allowCredentials` 只是給 authenticator 的提示。也不外洩任何東西——那些 id
本來就存在呼叫端自己的裝置上，是那個人自己註冊或上次登入時寫下的。

**閒置逾時不登出，改成蓋住畫面**（[idle_lock.dart](../lib/entry/idle_lock.dart)）。
原本寫「退回選人」，但選人畫面在登出後才會出現，而登出會把整棵樹拆掉——籃子
裡打到一半的單就沒了。那等於「每次轉身去煮杯咖啡就掉一張單」，而那正是店家把
逾時設成 Off 的原因。

保留 session、只蓋住畫面，保護的東西一樣（沒人站著的收銀台），代價是零：
「Carry on」把同一個人放回他原本在的地方，籃子原封不動。**交接給別人才登出**，
因為那是決定而不是意外，而且會先講清楚代價。開了螢幕鎖的話，Carry on 要通過鎖。

`IdleLock` 掛在 `MaterialApp.builder`，在 Navigator 之上——推一個路由或開一個
對話框就能蓋過去的蓋子不是蓋子。長度是店家設定（`Store.idleTimeoutMinutes`，
0 = 關閉，選項到 30 分鐘為止：再長就不是在蓋無人看管的櫃台了，誠實的做法是選
Off 而不是設一小時然後假裝有在保護）。

### 7.1 多重 live session —— 已實作（2026-09-04）

**先記下一次判斷錯誤**，因為它會再發生：我第一次評估時把這項判掉，理由是
「省下的只是一次指紋」，並且寫了「離線換人不是多重 session 能解的」。**後面
那句是反的。** 多重 session 正是唯一能解它的東西——每個 `FirebaseApp` 會把自
己登入的使用者持久化在本機，所以把一個先前已在這台裝置登入過的人重新變成
current，**完全不需要網路**。第一次的成本估算也錯了一個量級：我把 repository
的**讀取端**（28 檔 100 處）當成改動範圍，實際要改的是它們內部持有 handle 的
方式，`lib/database/` 裡總共 9 個欄位。

**做法**（[session_apps.dart](../lib/database/session_apps.dart)）：一個
`FirebaseApp` 一個 slot，最多四個。第一個 slot **就是預設 app**，所以只有一個
人的店，啟動路徑跟以前一模一樣。啟動時**只開作用中的那一個** slot——把三個
Firebase 初始化放進第一幀的路徑上，去服務一個可能不會發生的換人，是不對的
交易；其他 slot 在有人點到那個名字時才開，那是本機讀取。

**Repository 改成透過持有者讀**，不在建構時抓死：

```dart
FirebaseFirestore get _db =>
    _injected ?? FirebaseFirestore.instanceFor(app: sessionApps.active);
```

注入口留著給測試。`AuthRepository.uidChanges` 會在換手時**重新訂閱**——stream
綁在它來自的那個 instance 上，只訂一次的話換人之後它還在報告已經交班的那個
人，而且會在別人接手的瞬間報告**那個人**登出。

**三個必須同時對的地方**：

1. 每個 slot 開啟時要各自設定離線快取與 App Check。少做任何一個，第二個
   session 就是「沒有離線快取的 session」（那正是它存在的理由）或「每個請求
   都沒有 attestation」（開了強制就是第一屏被拒）。所以設定寫在
   `openSessionApp()` 裡，那是唯一每個 app 剛好經過一次的地方。
2. shell 用 uid 當 key。底下的一切——session resolver、`IndexedStack` 保活的
   頁面、裡面每一條 Firestore stream——都屬於某一個 Firebase app，換手之後那
   是錯的那一個。
3. 登出一律走 `signOutOperator()`：登出當前這位，並把櫃台交給裝置上還握著
   session 的下一位。一台裝置有三個 session 時，「其中一個結束」跟「櫃台空了」
   不是同一件事。

**換手不保留籃子**，而且這是對的：一張被某個人打到一半的單，不該掛在下一個人
名下送出去。但每次都跳確認會讓交接變貴，所以 `unsentBasketLines` 讓蓋板只在
**真的有東西可以失去**的時候才問。

**還沒能驗證的部分（重要）**：多個 `FirebaseApp` 的實際 auth 行為需要真機與真
專案，這裡驗不到。已驗證的是編譯、slot 帳務的單元測試（10 項）、以及只有一個
人的店走的路徑與改動前完全相同。第一次在真機上要看三件事：

1. 第二個 slot 的 **Play Integrity token 有沒有發出來**（沒發的話那個 session
   的每個請求都會被 App Check 擋掉）。
2. **離線切回去時 Firestore 是不是直接從那個 app 自己的快取回答。**
3. **換手瞬間 `authStateChanges()` 會不會先吐一個 null。** 重新訂閱時
   `_auth` 指向新開的 app；如果 Firebase 是非同步還原持久化的使用者，第一筆
   可能是 null，那會讓根畫面閃一下入口畫面、`currentOperator` 被清掉，而且
   `previous != uid` 的規則會多跑一次 `popUntil`。`Firebase.initializeApp`
   應該在回傳前就還原完畢，所以預期不會發生——但這是唯一在這裡證明不了的一
   條，也是最值得第一個看的。

### 7.2 入口導覽的兩個結構性錯誤（2026-09-04 修）

**登入成功後畫面不動，按返回才會進去。** 根畫面在 auth 狀態改變時換掉的是
**home route 的內容**，它沒有辦法移除疊在上面的路由——而登入頁正是被 push 上
去的。所以登入成功之後，人看著的還是自己剛填完的那張表單，後面才是 app。這個
codebase 早就為**登出**處理過同一件事（`popUntil(isFirst)`），但沒有為登入。

修法不是在根畫面上「登入時也 pop」——那會把註冊流程扯斷：註冊會在自己的流程
中途把帳號建出來，後面還有建店要做，在**進來的那一刻** pop 等於製造出
§loadSession 那個「帳號存在、文件不存在」的狀態。所以規則是不對稱的：

- **自己 push 上去的畫面，自己 pop**（登入頁成功後 pop 自己）。
- **根畫面只在 session 被換掉或結束時** pop（`previous != null && previous !=
  uid`），這也順帶蓋掉了換操作者——不然新的人會落在前一個人開著的設定頁裡。

**蓋板不能用 `showDialog`。** `IdleLock` 掛在 `MaterialApp.builder`，那是
**Navigator 之上**（已用探針測試證實：從 builder 拿到的 context 找不到
NavigatorState）。掛在那裡正是它能蓋住 pushed route 和對話框的原因，代價就是
它自己不能開對話框。籃子的確認改成**畫在蓋板上**。

兩件事都寫成了測試（`test/widgets/entry_navigation_test.dart`），而且
`idle_lock_test` 改成用 `builder` 掛載——原本掛在 `home` 底下，剛好避開了這個
問題，那正是它沒被測出來的原因。


**本機 PIN（Phase 4 第 12 項）——不做。**

三個理由，任一個都夠：

1. 店主自己已經定了「每個員工有自己的帳號」，記在
   `shared-tablet-attribution`，那條決定**本身就排除了 per-staff PIN 層**。
2. `local_auth` 的 `biometricOnly: false` 已經自動退回裝置密碼，所以「感應器
   讀不到手指」這個情境**已經有解**，不需要第三個密碼。
3. 依 §5.3，PIN 只能存本機、規則驗證不到它，所以它不能承載任何授權意義。再
   加一個沒有授權意義、大家會跨店重複使用的秘密，是負值。

留下的唯一情境是「共用平板的裝置密碼不想給員工知道」。那是真的，但很窄，而且
螢幕鎖在沒有生物辨識時是**放行**而不是拒絕（見 §Phase 4 第 11 項），所以不會
有人被鎖在外面。要做的話這是一個獨立的小功能，不是這個 Phase 的一部分。

**Phase 3 — 登入流程重做**
8. ~~資訊架構翻轉：選人成為主畫面，登入降級為分支（§3.1）~~（已完成
   2026-09-04）
9. ~~`lib/register.dart` 1325 行拆檔~~——已拆成 `lib/register/` 下的
   `open_store` / `join_store` / `account_fields` / `registration_ui` 四個檔案
10. ~~檢查 `lib/widgets/pre_auth_theme.dart` 該留還是併回主 theme~~——已刪除。
    它確實是「視覺與圖案完全不相符」的根源：那三個畫面的字面色與烤進 SVG 的
    unDraw 配色，逼得整個登入前流程只能鎖在亮色主題。見 design-tokens.md §6.5

**Phase 4 — 可選的鎖**
11. ~~裝置生物辨識鎖（要裝 `local_auth`，不碰 Firebase）~~（已完成 2026-09-04）
12. 本機 PIN（§5.3）

**鎖住哪幾個畫面，以及為什麼不是全部**（[screen_lock.dart](../lib/settings/screen_lock.dart)）：
Insights 分頁、匯出、員工清單、變更史、Account & app。**Today 與 Reports 沒有
鎖**——那些數字是站在收銀台的人整天都看得到的，在通往員工每天要開的東西的路上
擋一道提示，就是那種會被關掉的鎖。Insights 是唯一有成本、毛利與滯銷品的地方。

一次解鎖有 5 分鐘寬限期（對帳的人會在同一分鐘內走過 Insights → 變更史 → 匯出），
登出時作廢。**關掉鎖要先通過鎖**——誰都可以打開一道鎖，只有已經能通過的人才該
能把它拿走。

裝置沒有登記生物辨識時，`confirm()` 一律放行而不是拒絕：把店家鎖在自己的帳本
外面、而且沒有回頭路，比這道鎖擋下的東西嚴重得多。它是無人看管畫面上的嚇阻，
不是保險庫。平台呼叫丟例外時同理。

**這道鎖絕對不能被說成是身分驗證**，理由就是 §2.1：指紋只說「這台平板現在有人
在旁邊」，不說是誰。UI 文案在 Security 頁最後一段明講了這件事。

離線換人（決策 5）跨 Phase 2 與 3，因為它同時牽涉選人畫面和 session 管理。

### 7.3 螢幕鎖是「畫上去的蓋板」而不是「門」（2026-09-04 修）

店主從櫃檯回報五件事，五件是同一個根因：**鎖被實作成畫在已經活著的 app 上的一層蓋板**，
而不是一道擋在前面的門。`IdleLock` 掛在 `MaterialApp.builder`，在 Navigator 之上，
`_TillCover` 是它的 `Stack` 子節點——但整個 shell 早就掛好了：每一條 Firestore stream
都開著、當天的營業額都抓完了、Today 跟 Insights 都排版完了，就在那層蓋板底下。

由此推出的五個缺陷，每一個都是真的：

1. **蓋板根本沒蓋滿。** `Stack` 給沒有 `Positioned` 的子節點的是 **loose constraints**，
   所以蓋板只有自己內容那麼高，底下的 app 繼續露出來——可讀、可捲、**可點**。截圖裡
   「Still signed in. Unlock to carry on.」下面就是 Guests / Per order / Add Order /
   底部導覽列。使用者說的「點一下空白處指紋鎖就跳掉了」不是鎖被關掉，是**他點到了沒被蓋住的
   那塊 app**。→ `Positioned.fill`。
2. **先渲染才驗證。** 鎖保護的是一張截圖，不是資料。→ 改成 `AppLockGate`，放在
   auth stream 之下、`_SessionGate` **之上**：鎖上時 `child` 連 build 都不會 build，
   所以沒有任何一次讀取發生。位置是修法本身——`_SessionGate` 的 state 一建立就開始讀，
   任何比這更深的鎖都是「圖表已經抓好了才問你是誰」。
3. **換手就是一扇沒鎖的門。** `_handOver` 成功後直接 `tillLocked.value = null`，
   從來沒問過。「先 switch 到另一個帳號再切回來」因此完全免驗證。→ 換手不再等於解鎖；
   進來的 session 走自己的 gate（gate 以 uid 為 key），而 gate 一律
   `check(allowGrace: false)`——五分鐘的寬限期是給 app **裡面**的畫面用的，
   讓門也吃它就等於「切出去再切回來」直接放行。
4. **`confirm()` 全部 fail-open。** 裝置沒有註冊生物辨識、平台呼叫丟例外——兩種情況
   都 `return true`。鎖開著、蓋板在畫面上、什麼都沒問就進去了。→ 改成三態
   `LockCheck { passed, refused, unavailable }`。`unavailable` 在**門口**是明講並給兩條
   出路（重新登入／明確關掉鎖），在 app 裡面才放行——而且只在那裡放行。
5. **可用性判斷問錯問題。** 是 `isDeviceSupported() && canCheckBiometrics`。
   但 `authenticate` 是用 `biometricOnly: false` 呼叫的，所以只有 PIN、沒有指紋辨識模組的
   櫃檯平板——櫃檯上很常見——會回報「這台不能鎖」然後被直接放行。
   → 只看 `isDeviceSupported()`（有指紋/臉 **或** 有 PIN/圖形/密碼皆為 true）。
   `getAvailableBiometrics()` 只拿來寫文案，不拿來分支。

順帶：兩個 `authenticate` 同時進行在 Android 上是平台錯誤，而這個 app 產得出來
（門口在問，底下的畫面進場時也在問），所以 `check` 現在共用同一次提示而不是互相搶。
`isAvailable` 的快取在 app 回到前景時作廢——離開 app 去設定裡移除指紋是唯一的移除方式，
回來就是那個快取唯一會錯得有意義的時刻。

**文案：指紋 ≠ passkey。** 店主明確指出這兩個被混在一起，而 Security 畫面確實是這樣寫的
（鎖寫「Ask for a fingerprint」、passkey 那列也寫「Sign in with a fingerprint」，
連 icon 都是同一個指紋）。兩者回答的是相反的問題：**鎖只證明有人拿著這台裝置，不說是誰**；
**passkey 對伺服器證明是誰，而且是它才創得出 session**。所以 passkey 那列改成
`Icons.key_outlined` 與「Sign in as you, with no password to steal」，鎖那列改成明講
「這台裝置自己的指紋、臉或 PIN」。

**還沒做，真機上值得看的**：Android 的最近使用畫面（recents）快照。gate 之後冷開機不再有問題，
但 app 切到背景時系統仍會拍一張當下畫面。`FLAG_SECURE` 可以擋掉，代價是整個 app 不能截圖——
店主可能會想截報表，所以這是要問過的取捨，不是預設。
