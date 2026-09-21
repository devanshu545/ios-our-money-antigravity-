# OurMoney — Feature & Logic Inventory (extracted from the Android source)

Source of truth: `ourmoney/` (Kotlin + Jetpack Compose, Firebase Auth + Firestore, Gemini AI, PDF engine).
This document is the checklist the iOS port implements 1:1. Nothing here may be dropped or reinvented.

## Technology detected
- Language: Kotlin 2.x, UI: Jetpack Compose + Material 3 (dark graphite/teal theme)
- Auth: Firebase Auth, Google Sign-In via AndroidX Credential Manager (`WEB_CLIENT_ID` from env)
- DB: Firestore, real-time snapshot listeners (`MetadataChanges.INCLUDE` → pending-write badges)
- AI: `com.google.ai.client.generativeai` (Gemini), key from `GEMINI_API_KEY` build config
- Reports: native `PdfDocument` engine (`util/PdfGenerator.kt`), opened via FileProvider
- Backend: `ourmoney/app/google-services.json` (same Firebase project must be reused on iOS)
- Notifications: **none implemented** (no FCM dependency/permission in manifest) → iOS must not fake any.

## Firestore schema (amounts are integer paise)
- `users/{uid}`: `id, name, email, householdId?, connectedAt?, createdAt`
- `households/{id}`: `id, code (6-digit), members[uid], createdAt`
  - `transactions/{id}`: `id, amountPaise, category, dateMillis, paidBy, createdBy, personal, splitMethod(EQUAL|EXACT|PERCENTAGE|SHARES), splits[{userId,amountPaise}], notes, type(EXPENSE|INCOME|TRANSFER), paymentMethod, isDeleted`
  - `settlements/{id}`: `id, amountPaise, paidBy, receivedBy, dateMillis, paymentMethod, notes, createdBy, createdAt`
  - `goals/{id}`: `id, name, targetAmountPaise, currentAmountPaise, personal, createdBy, createdAt`
  - `budgets/{id}`: `id, category, limitAmountPaise, personal, createdBy, monthYear, createdAt`
  - `categories/{id}`: `id, name, createdBy, createdAt` (custom categories)
- `ai_chats/{id}`: `id, title, createdAt, updatedAt, ownerId, householdId, scope(PERSONAL|SHARED)`
- `ai_messages/{id}`: `id, chatId, role(USER|MODEL|SYSTEM), content, timestamp`

## Auth / pairing flow (AuthRepository)
1. Google Sign-In → `signInWithCredential(GoogleAuthProvider)`.
2. Auth-state listener: signed out → Idle; signed in → listen `users/{uid}`.
3. No user doc → `RequiresName` (name input screen saves `users/{uid}`).
4. User doc without `householdId` → `RequiresPairing`.
5. Household listener: member removed / household gone → clear `householdId`, back to pairing; `members.size < 2` → pairing with existing household shown; else `Authenticated`.
6. **Create household**: random 6-digit code (100000..999999), UUID id, `members = [self]`, then set user `householdId` + `connectedAt`.
7. **Join household**: query `households where code == trimmed code`; empty → "Invalid connection code."; already 2 members and not self → "This connection already has two members."; else append member (distinct) + set user householdId.
8. **Cancel pairing**: user `householdId = null, connectedAt = null`; if the old household still exists, **delete the household document**.
9. Sign out removes listeners → Idle.

## Ledger math (domain/LedgerCalculator.kt) — must match exactly
- Only shared (`personal == false`), non-deleted `EXPENSE` transactions count.
- `myTotalPaid += amountPaise` where `paidBy == me`, else `partnerTotalPaid +=`.
- Responsibilities summed per split owner (display only).
- `net = (myTotalPaid - partnerTotalPaid) / 2` (integer division on paise) then settlements adjust: settlement paid by me → `net += amountPaise`; received by me → `net -= amountPaise`.
- `owedToMe = max(net, 0)`, `iOwe = max(-net, 0)`.
- Example: ₹2000 total, Devanshu paid ₹1200, friend ₹800 → each share ₹1000 → friend owes Devanshu ₹200. iOS must produce identical results.

## Repository behaviors (LedgerRepository)
- Transactions flow = combine(shared `personal==false` query, personal `personal==true && createdBy==me` query) sorted by `dateMillis` desc; `isDeleted == true` filtered out; `isPending = hasPendingWrites()` surfaced to UI.
- Settlements flow ordered `dateMillis` desc. Goals/Budgets flows = same shared+personal pattern, sorted `createdAt` desc.
- Categories flow ordered by `name` asc (no personal filter).
- Writes: `add*` sets `createdBy = me` then `set`; updates are full-document `set`; deletes are real `delete()`.
- `resetAllTransactions`: batch-delete all shared transactions + my personal transactions + ALL settlements (Android submits one batch; iOS chunks at 400 to respect the 500-op limit — Android's un-chunked batch is a known bug to fix consistently).

## Screens / interactions to replicate
1. **Splash** (2s, animated wallet logo, gradient) — shown while auth loads.
2. **Google Sign-In screen** (Idle state).
3. **Name input** (RequiresName).
4. **Pairing screen** (RequiresPairing): show my 6-digit code if I created a household; input to join by code; cancel/leave connection; inline errors from repo.
5. **Main** — bottom nav: Home, History, Stats, Budgets, Goals, AI (6 tabs).
6. **Home/Dashboard**: header "OurMoney" + "Connected with {partner}"; settings icon; net balance card (owed to me / I owe); paid-by-me/partner totals; recent transactions; search field; swipe-to-delete on transactions; FAB "Add" + small FAB "Settle"; pending (offline) badge on items with `isPending`.
7. **Add/Edit Expense** (`add_expense?transactionId=`): amount, category dropdown (10 standard: Food & Dining, Groceries, Transport, Shopping, Entertainment, Bills & Utilities, Health, Travel, Education, Misc + custom categories; add/delete custom), personal vs shared toggle, "paid by me/partner" toggle, payment method (UPI/Cash/Card...), date+time picker, notes, split method selector with per-person split editing, validation (amount > 0, category required), save with progress + error surface, delete existing.
8. **History**: combined list (transactions + settlements rendered as "Settlement" transfers), search across category/notes/method/amount/date/scope, date-range filters, scope filter (All/Shared/Personal), edit swipe actions (expense → add_expense, settlement → settle_up), delete with confirm, **PDF export dialog** (scope + Weekly/Monthly report via PdfGenerator).
9. **Stats/Analytics**: total spent, UPI vs Cash cards, You-paid vs Partner-paid cards, category donut chart, category breakdown list with %, highest transaction.
10. **Budgets**: month selector, scope segmented control (All/Shared/Personal), summary (total budget, spent, safe daily limit, days remaining, month-end projection), health status chip (ON TRACK/WATCH/AT RISK/OVER BUDGET at 50/85/100%), weekly bar chart (this week vs last week), per-category budget cards with progress + detail (largest/average transaction, transaction list), add/edit/delete budget (category + monthly limit + personal/shared), custom category management, month-over-month comparison insights.
11. **Goals**: list with progress, FAB add (name, target, personal/shared), edit, delete (confirm), "add contribution" (adds to currentAmountPaise).
12. **Settle Up** (`settle_up?settlementId=`): amount, who paid (me/partner), method, notes, date; balance summary; list of past settlements with edit/delete; validation amount > 0.
13. **Settings**: profile (name/email), partner name, household code display, **Reset all transactions** (danger confirm), **Disconnect** (removes me from household, clears my householdId; on failure falls back to sign out), **Sign out**.
14. **AI**: scope toggle Personal/Shared; chat list (owned by me / shared with household) sorted by `updatedAt` desc; new chat, delete chat (cascades messages), open chat; messages real-time; send → persists USER message, auto-title from first message (30 chars), builds financial context engine snapshot, calls Gemini `gemini-3.5-flash` with the OurMoney system prompt (plain text, no markdown, dynamic length, ₹ formatting), persists MODEL reply; loading + retry-last-message + friendly error state.

## AI financial context engine (AiFinancialContextEngine)
Filtered to shared + my personal data; reports: total spending, per-category totals, budgets with % used, goals with % complete, settlement state (paid totals + net), last 10 transactions with type/amount/category/method/paidBy.

## PDF report (PdfGenerator)
A4 (595x842): header (OURMONEY, generated date, scope, period), budget performance block with progress bar + status chip, at-a-glance stats (txn count, avg daily, highest day/category), period comparison vs previous equal period, shared expense summary (paid/share/net settlement), insights bullets, category donut + legend, daily spending bar chart, payment-method summary (UPI/Cash %), largest 5 expenses table, full transaction ledger table. Shared via system viewer.

## Validation rules & error handling
- Amount must be > 0; category required; partner required for settlement; join errors (invalid code / full household / network) surfaced verbatim; AI key missing → explicit error message; failed writes never fake success (Firestore errors propagate to UI).
