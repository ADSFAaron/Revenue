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
3. 歷史訂單、稽核紀錄顯示是誰，含懸空 uid 的處理（§6）
4. `orders.createdBy` 的取捨寫進 rules 註解（§5.2）

**Phase 2 — 選人畫面**
5. 操作者概念與「目前操作者：X」常駐指示
6. 選人畫面（全店員工，本機有 session 的排前面）
7. 閒置逾時退回選人，長度做成店家設定，草稿保留（決策 2、3）

**Phase 3 — 登入流程重做**
8. 資訊架構翻轉：選人成為主畫面，登入降級為分支（§3.1）
9. ~~`lib/register.dart` 1325 行拆檔~~——已拆成 `lib/register/` 下的
   `open_store` / `join_store` / `account_fields` / `registration_ui` 四個檔案
10. ~~檢查 `lib/widgets/pre_auth_theme.dart` 該留還是併回主 theme~~——已刪除。
    它確實是「視覺與圖案完全不相符」的根源：那三個畫面的字面色與烤進 SVG 的
    unDraw 配色，逼得整個登入前流程只能鎖在亮色主題。見 design-tokens.md §6.5

**Phase 4 — 可選的鎖**
11. 裝置生物辨識鎖（要裝 `local_auth`，不碰 Firebase）
12. 本機 PIN（§5.3）

離線換人（決策 5）跨 Phase 2 與 3，因為它同時牽涉選人畫面和 session 管理。
