# SIP (Auto Savings) – API Documentation

All SIP APIs use `POST` method and require `Authorization: Bearer <token>` header.
Base URL: configured via `AppConfig.baseUrl`.

---

## 1. SIP Configuration

### `POST /sip/config`

Fetches the initial configuration for the Auto Savings module.

**Request:** No body required.

**Response:**
```json
{
  "success": true,
  "data": {
    "min_amount": 10,
    "max_amount": 50000,
    "frequencies": [
      { "id": 1, "name": "Daily", "is_default": 0 },
      { "id": 2, "name": "Weekly", "is_default": 0 },
      { "id": 3, "name": "Monthly", "is_default": 1 }
    ],
    "commodities": [
      { "id": 1, "name": "Gold" },
      { "id": 3, "name": "Silver" }
    ]
  }
}
```

---

## 2. Denominations

Denomination endpoints accept an optional `frequency` parameter to return
frequency-specific amounts (Daily, Weekly, Monthly may have different presets).

### `POST /sip/gold-denominations`

**Request:**
```json
{
  "frequency": 1
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `frequency` | int | ❌ | Frequency ID (`1` = Daily, `2` = Weekly, `3` = Monthly). If omitted, returns default denominations. |

**Response (example — Daily):**
```json
{
  "success": true,
  "data": [
    { "value": 10, "is_popular": 0 },
    { "value": 100, "is_popular": 1 },
    { "value": 500, "is_popular": 0 },
    { "value": 1000, "is_popular": 0 }
  ]
}
```

**Response (example — Monthly):**
```json
{
  "success": true,
  "data": [
    { "value": 100, "is_popular": 0 },
    { "value": 500, "is_popular": 1 },
    { "value": 1000, "is_popular": 0 },
    { "value": 5000, "is_popular": 0 },
    { "value": 10000, "is_popular": 0 }
  ]
}
```

### `POST /sip/silver-denominations`

**Request:**
```json
{
  "frequency": 1
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `frequency` | int | ❌ | Frequency ID (`1` = Daily, `2` = Weekly, `3` = Monthly). If omitted, returns default denominations. |

**Response (example — Daily):**
```json
{
  "success": true,
  "data": [
    { "value": 10, "is_popular": 0 },
    { "value": 100, "is_popular": 1 },
    { "value": 500, "is_popular": 0 },
    { "value": 1000, "is_popular": 0 }
  ]
}
```

**Response (example — Monthly):**
```json
{
  "success": true,
  "data": [
    { "value": 100, "is_popular": 0 },
    { "value": 500, "is_popular": 1 },
    { "value": 1000, "is_popular": 0 },
    { "value": 5000, "is_popular": 0 },
    { "value": 10000, "is_popular": 0 }
  ]
}
```

> **Note:** The app automatically re-fetches denominations when the user switches
> frequency tabs (Daily → Weekly → Monthly). If the API does not support
> frequency filtering yet, it should ignore the field and return default values.

---

## 3. Create SIP Plan

### `POST /sip/create` 🔐 _Encrypted_

Creates a new auto savings plan.

**Daily Payload:**
```json
{
  "frequency": 1,
  "commodity_id": 1,
  "amount": 100
}
```

**Weekly Payload:**
```json
{
  "frequency": 2,
  "commodity_id": 1,
  "amount": 100,
  "day": "Monday"
}
```

**Monthly Payload:**
```json
{
  "frequency": 3,
  "commodity_id": 1,
  "amount": 100,
  "date": 5
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "SIP created",
  "data": {
    "subscription_id": "G24D042399DA77",
    "status": "ACTIVE",
    "order_id": "cf_order_123",
    "session_id": "sub_session_abc",
    "authorization_link": "https://sandbox.cashfree.com/subscription/pay/sub_session_abc",
    "environment": "SANDBOX"
  }
}
```

> **⚠️ Important:** The `authorization_link` is the full Cashfree checkout URL from the
> mandate creation response. The app opens this URL in the browser for the user to
> authorize the UPI Autopay / e-Mandate. Do NOT use the Cashfree PG SDK — it only
> supports one-time payment sessions, not subscription sessions (`sub_session_...`).

> **Security:** The `amount` field is encrypted via RSA-OAEP-SHA256 before transmission.

---

## 4. SIP Details (Active Plans)

### `POST /sip/details`

Fetches all SIP plans for the user.

**Request:** No body required.

**Response:**
```json
{
  "success": true,
  "data": [
    {
      "subscription_id": "G24D042399DA77",
      "start_date": "2024-04-23",
      "frequency": "Daily",
      "frequency_id": 1,
      "amount": 100,
      "status": "ACTIVE",
      "commodity_name": "Gold",
      "commodity_id": 1
    },
    {
      "subscription_id": "S25W050199BC44",
      "start_date": "2024-05-01",
      "frequency": "Weekly",
      "frequency_id": 2,
      "amount": 500,
      "status": "ACTIVE",
      "commodity_name": "Gold",
      "commodity_id": 1,
      "day": "Monday"
    }
  ]
}
```

---

### App Behaviour — Auto Savings Overview Screen (`SipOverviewScreen`)

> **Page Name:** `SipOverviewScreen`
> **Menu Location:** Profile → Auto Savings
> **Route:** `/sip-overview`
> **API Used:** `POST /sip/details` (same endpoint as above — no new API needed)

This screen provides a consolidated view of the user's Auto Savings (SIP) plans.

#### Screen Behaviour:

| Element | Behaviour |
|---|---|
| **Frequency Tabs** | Three pill tabs: Daily, Weekly, Monthly. Always shown regardless of active plans. |
| **Invest Type Radio** | Gold 24K / Silver radio buttons — filters plans by commodity. |
| **Plan Card** | Displayed when an ACTIVE or PAUSED plan exists for the selected frequency + commodity combination. Shows: Started On, Savings Amount, Frequency, Reference ID, Status badge. |
| **No Plan State** | Shown when no plan exists for the selected combination. Includes "Setup Auto Savings" CTA → navigates to `/auto-savings`. |
| **Quick Actions** | Two cards: "SIP Transactions" → `/sip-transactions`, "New Auto Save" → `/auto-savings`. |
| **Tap on Plan Card** | Navigates to Manage Savings screen (`/sip-manage`) with `subscription_id`. |

#### Data Flow:
1. Screen calls `POST /sip/details` on entry (always invalidated for fresh data).
2. Response is a flat list of all plans.
3. Client filters by `frequency` + `commodity_name` based on selected tab/radio.
4. Plan card fields are mapped as follows:

| Card Field | API Field | Format |
|---|---|---|
| Started On | `start_date` | Parsed from `YYYY-MM-DD` → `DD Mon YYYY` |
| Savings Amount | `amount` | `₹{amount}` (integer display) |
| Frequency | `frequency` | Direct string (`Daily`, `Weekly`, `Monthly`) |
| Reference ID | `subscription_id` | Direct string |
| Status | `status` | Uppercase badge — green for `ACTIVE`, amber for `PAUSED` |

---

## 5. Manage Details

### `POST /sip/manage-details`

Fetches detailed info for a specific subscription.

**Request:**
```json
{
  "subscription_id": "G24D042399DA77"
}
```

**Response:**
```json
{
  "success": true,
  "data": {
    "subscription_id": "G24D042399DA77",
    "start_date": "2024-04-23",
    "amount": 100,
    "status": "ACTIVE",
    "frequency": "Daily",
    "commodity_name": "Gold"
  }
}
```

---

## 6. Pause SIP

### `POST /sip/pause` 🔐 _Encrypted_

Pauses an active SIP plan.

**Request:**
```json
{
  "subscription_id": "G24D042399DA77"
}
```

**Response:**
```json
{
  "success": true,
  "message": "SIP paused successfully"
}
```

---

## 7. Resume SIP

### `POST /sip/resume`

Resumes a paused SIP plan.

**Request:**
```json
{
  "subscription_id": "G24D042399DA77"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `subscription_id` | String | ✅ | The subscription ID to resume |

**Response:**
```json
{
  "success": true,
  "message": "SIP resumed successfully"
}
```

---

## 8. Cancel SIP

### `POST /sip/cancel` 🔐 _Encrypted_

Cancels a SIP plan. **Cannot cancel within 24 hours of creation.**

**Request:**
```json
{
  "subscription_id": "G24D042399DA77",
  "reason": "No money"
}
```

**Reason Options:**
- `No money`
- `Change frequency`
- `Other saving method`
- `Goal achieved`

**Response (Success):**
```json
{
  "success": true,
  "message": "SIP cancelled successfully"
}
```

**Response (Within 24 hours):**
```json
{
  "success": false,
  "message": "Cannot cancel within 24 hours of creation"
}
```

---

## 8.5. Confirm SIP (Mandate Authorization Verification)

### `POST /sip/confirm`

Called after Cashfree SDK callback (success or failure). Verifies the
mandate authorization status with Cashfree and updates the subscription
record accordingly.

**Request:**
```json
{
  "order_id": "2727035"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `order_id` | String | ✅ | Order ID returned from `sip/create` and Cashfree SDK callback |

**Response (Success — Mandate authorized):**
```json
{
  "success": true,
  "message": "Subscription authorized successfully",
  "data": {
    "subscription_id": "G26DE49BDBBBF6",
    "status": "ACTIVE",
    "mandate_status": "ACTIVE"
  }
}
```

**Response (Pending — Bank approval required):**
```json
{
  "success": true,
  "message": "Authorization pending bank approval",
  "data": {
    "subscription_id": "G26DE49BDBBBF6",
    "status": "BANK_APPROVAL_PENDING"
  }
}
```

**Response (Failed):**
```json
{
  "success": false,
  "message": "Mandate authorization failed. Please try again."
}
```

> **Note:** For UPI Autopay, `status` is typically `ACTIVE` immediately.
> For e-Mandate/NACH, it may be `BANK_APPROVAL_PENDING` (2–3 business days).

---

## 9. SIP Transactions (History)

### `POST /sip/transactions`

Fetches the SIP transaction history for the current user. Returns grouped transactions by date.

**Request:** No body required.

**Response:**
```json
{
  "success": true,
  "data": {
    "plans": [
      { "frequency": "Daily", "commodity_name": "Gold 24K" },
      { "frequency": "Daily", "commodity_name": "Silver" },
      { "frequency": "Weekly", "commodity_name": "Gold 24K" }
    ],
    "grouped_transactions": {
      "28 Apr 2026": [
        {
          "transaction_id": "SIP_TXN_001",
          "title": "SIP Autopay",
          "subtitle": "Daily Gold Auto-Savings",
          "type": "sip",
          "amount": 100,
          "weight_grams": "0.0125",
          "display_date": "28 Apr 2026, 10:30 AM",
          "status": "success",
          "metal_name": "Gold 24K"
        },
        {
          "transaction_id": "SIP_TXN_002",
          "title": "SIP Autopay",
          "subtitle": "Daily Silver Auto-Savings",
          "type": "sip",
          "amount": 50,
          "weight_grams": "0.5612",
          "display_date": "28 Apr 2026, 10:30 AM",
          "status": "success",
          "metal_name": "Silver"
        },
        {
          "transaction_id": "SIP_TXN_004",
          "title": "SIP Autopay",
          "subtitle": "Weekly Gold Auto-Savings",
          "type": "sip",
          "amount": 500,
          "weight_grams": "0.0628",
          "display_date": "28 Apr 2026, 10:30 AM",
          "status": "success",
          "metal_name": "Gold 24K"
        }
      ],
      "27 Apr 2026": [
        {
          "transaction_id": "SIP_TXN_003",
          "title": "SIP Autopay",
          "subtitle": "Daily Gold Auto-Savings",
          "type": "sip",
          "amount": 100,
          "weight_grams": "0.0126",
          "display_date": "27 Apr 2026, 10:30 AM",
          "status": "failed",
          "metal_name": "Gold 24K"
        }
      ]
    }
  }
}
```

| Response Field | Type | Description |
|---|---|---|
| `plans` | Array | List of SIP plans (used to build frequency tabs + commodity chips) |
| `plans[].frequency` | String | `"Daily"`, `"Weekly"`, `"Monthly"`, or `"Custom"` — used for tab segmentation |
| `plans[].commodity_name` | String | Plan commodity name (e.g., "Gold 24K", "Silver") |
| `grouped_transactions` | Object | Transactions grouped by display date key |
| `grouped_transactions[date]` | Array | List of transactions for that date |
| `transaction_id` | String | Unique transaction identifier |
| `title` | String | Transaction title |
| `subtitle` | String | **Must include frequency** (e.g., "Daily Gold Auto-Savings", "Weekly Silver Auto-Savings", "Custom Gold Auto-Savings") — used for filtering |
| `type` | String | Always `"sip"` for SIP transactions |
| `amount` | Number | Transaction amount in ₹ |
| `weight_grams` | String | Weight of commodity purchased |
| `display_date` | String | Human-readable date + time string |
| `status` | String | `success`, `pending`, `failed`, `cancelled` |
| `metal_name` | String | `"Gold 24K"` or `"Silver"` |

> **App Behavior — Frequency Segmentation:**
> - **Primary**: Transactions are segmented by frequency (Daily / Weekly / Monthly / Custom) tabs.
> - If only one frequency exists → no tabs, just a frequency badge.
> - If multiple frequencies exist → TabBar with Daily | Weekly | Monthly | Custom, in that order.
> - **Secondary**: Within each frequency tab, if both Gold and Silver exist → horizontal toggle chips ("All" | "Gold 24K" | "Silver").
> - API is called fresh every time the screen is entered (no caching).
> - The `subtitle` field **must contain the frequency name** (e.g., "Daily", "Weekly", "Monthly", "Custom") as it is used for client-side filtering.
> - **Custom SIP transactions**: Custom SIP (multi-date AutoPay, see §CustomSIPScheme / `sip/custom/*` endpoints) is a separate backend product from regular Daily/Weekly/Monthly SIP. For it to appear as a "Custom" tab here, the backend must merge its transactions into this same `grouped_transactions` feed (and add a `{"frequency": "Custom", "commodity_name": ...}` entry per commodity to `plans`) — the mobile app does not call a separate endpoint for Custom SIP history.

---

## 10. SIP Transaction Details

### `POST /sip/transaction-details`

Fetches details for a single SIP transaction.

**Request:**
```json
{
  "transaction_id": "SIP_TXN_001"
}
```

| Field | Type | Required | Description |
|---|---|---|---|
| `transaction_id` | String | ✅ | The transaction ID to fetch details for |

**Response:**
```json
{
  "success": true,
  "data": {
    "transaction_id": "SIP_TXN_001",
    "order_id": "2727035",
    "title": "Gold 24K",
    "subtitle": "Daily Gold Auto-Savings",
    "amount": "100.00",
    "weight_grams": "0.0125",
    "metal_name": "Gold 24K",
    "scheduled_date": "28 Apr 2026",
    "payment_method": "UPI Autopay",
    "timeline": [
      {
        "step_name": "Order Placed",
        "status": "Success",
        "time": "28 Apr 2026, 10:30 AM"
      },
      {
        "step_name": "Payment Received",
        "status": "Success",
        "time": "28 Apr 2026, 10:30 AM"
      },
      {
        "step_name": "Gold Credited",
        "status": "Success",
        "time": "28 Apr 2026, 10:31 AM"
      }
    ],
    "footer_message": "Gold has been credited to your vault successfully.",
    "invoice_number": "INV-2026-001234",
    "invoice_url": "https://api.example.com/invoices/INV-2026-001234.pdf",
    "price_breakdown": {
      "rate": "7950.00",
      "quantity": "0.0125",
      "value": "99.38",
      "gst": "0.62",
      "total_amount": "100.00"
    },
    "technical_details": {
      "transaction_id_display": "SIP_TXN_001",
      "gold_transaction_id": "GT_12345",
      "order_id": "2727035",
      "placed_on": "28 Apr 2026, 10:30 AM",
      "paid_via": "UPI Autopay"
    },
    "scheme_info": {
      "scheme_id": 1,
      "label": "Daily Gold 24K",
      "frequency": "Daily",
      "amount": "100",
      "total_saved": "2500",
      "cycles_done": 25,
      "status": "ACTIVE"
    }
  }
}
```

| Response Field | Type | Description |
|---|---|---|
| `transaction_id` | String | Unique transaction ID |
| `order_id` | String | Payment order ID |
| `title` | String | Metal name |
| `subtitle` | String | Plan label |
| `amount` | String | Amount in ₹ |
| `weight_grams` | String | Weight purchased |
| `metal_name` | String | `"Gold 24K"` or `"Silver"` |
| `timeline` | Array | Status timeline steps |
| `timeline[].step_name` | String | Step label (e.g., "Order Placed") |
| `timeline[].status` | String | `Success`, `Pending`, `Failed` |
| `timeline[].time` | String | Timestamp string |
| `footer_message` | String | Summary message |
| `invoice_url` | String | Download URL (empty if unavailable) |
| `price_breakdown` | Object | Rate, quantity, value, GST, total |
| `technical_details` | Object | Order ID, transaction ID, placed on, paid via |
| `scheme_info` | Object\|null | SIP plan details (null if not a SIP transaction) |
| `scheme_info.label` | String | Plan name (e.g., "Daily Gold 24K") |
| `scheme_info.frequency` | String | `Daily`, `Weekly`, `Monthly` |
| `scheme_info.total_saved` | String | Total saved across all cycles |
| `scheme_info.cycles_done` | int | Number of completed cycles |
| `scheme_info.status` | String | `ACTIVE`, `PAUSED`, `CANCELLED` |

> **App Behavior:**
> - API is called fresh every time the screen is entered (no caching).
> - Response structure is identical to `/transactions/details` — reuses the same `TransactionDetailResponse` model.
> - `scheme_info` block is shown as a dedicated "SIP Plan Details" card if present.

---

## Encryption Rules

The following SIP endpoints require encryption:
- `sip/create` – encrypts `amount`
- `sip/cancel` – encrypts `subscription_id`
- `sip/pause` – encrypts `subscription_id`
- `sip/resume` – encrypts `subscription_id`
- `sip/confirm` – encrypts `order_id`
- `users/nominee/update` – encrypts `mobile`, `id_number`

Encryption is handled automatically by `ApiSecurityInterceptor` using RSA-OAEP-SHA256.

## Edge Cases

| Scenario | Handling |
|---|---|
| API failure | Show error toast, allow retry |
| Payment failure | Show failure screen with retry |
| Duplicate plan for same frequency **+ commodity** | Block creation, show existing plan card |
| Same frequency, different commodity | ✅ **Allowed** (e.g. Daily Gold + Daily Silver) |
| Cancel within 24h | Server returns error, info banner shown |
| Nominee not added | Block SIP creation, show alert with "Add Nominee" |
| Back navigation | State maintained via Riverpod |
| Offline | Blocked by `ApiSecurityInterceptor` connectivity check |

## Duplicate Prevention Rules

Plans are scoped by **frequency + commodity** combination. This means:

| Gold Daily | Silver Daily | Allowed? |
|---|---|---|
| ✅ Active | ❌ None | ✅ Silver Daily can be created |
| ✅ Active | ✅ Active | ❌ Both occupied |
| ✅ Active | ❌ None (Weekly) | ✅ Different frequency |

**Examples of valid concurrent plans:**
- Daily Gold + Daily Silver ✅
- Daily Gold + Weekly Gold ✅
- Daily Gold + Weekly Silver + Monthly Gold ✅

**Blocked:**
- Daily Gold + Daily Gold ❌ (same frequency + same commodity)

---

# Nominee Management – API Documentation

All Nominee APIs use `POST` method and require `Authorization: Bearer <token>` header.

---

## 8. Get Nominee Details

### `POST /user/nominee/details`

Fetches existing nominee details for the current user.

**Request:**
```json
{}
```

**Response (Nominee exists):**
```json
{
  "success": true,
  "data": {
    "name": "John Doe",
    "relationship": "Father",
    "dob": "1980-05-10",
    "mobile": "9876543210",
    "email": "john@example.com",
    "id_type": "Aadhaar",
    "id_number": "123456789012",
    "address": "Chennai",
    "city": "Chennai",
    "state": "Tamil Nadu",
    "pincode": "600001"
  }
}
```

**Response (No nominee):**
```json
{
  "success": true,
  "data": {}
}
```

---

## 9. Update Nominee

### `POST /users/nominee/update` 🔐 _Encrypted_

Creates or updates the nominee for the current user.

**Request:**
```json
{
  "name": "John Doe",
  "relationship": "Father",
  "dob": "1980-05-10",
  "mobile": "9876543210",
  "email": "john@example.com",
  "id_type": "Aadhaar",
  "id_number": "123456789012",
  "address": "Chennai",
  "city": "Chennai",
  "state": "Tamil Nadu",
  "pincode": "600001"
}
```

### Fields:

| Field | Type | Required | Validation |
|---|---|---|---|
| `name` | String | ✅ | Alphabets + spaces only, min 2 chars |
| `relationship` | String | ✅ | One of: Father, Mother, Spouse, Son, Daughter, Brother, Sister, Other |
| `dob` | String | ✅ | Format: `yyyy-MM-dd`, must be past date |
| `mobile` | String | ✅ | 10 digits |
| `email` | String | ❌ | Valid email format if provided |
| `id_type` | String | ❌ | Aadhaar, PAN, Voter ID, Passport, Driving License, Others |
| `id_number` | String | ❌ | Min 4 chars if provided |
| `address` | String | ❌ | Free text |
| `city` | String | ❌ | Free text |
| `state` | String | ❌ | Free text |
| `pincode` | String | ❌ | 6 digits |

> **Security:** Fields `mobile` and `id_number` are encrypted via RSA-OAEP-SHA256 before transmission.

**Response:**
```json
{
  "success": true,
  "message": "Nominee updated successfully"
}
```

---

# Content – Refund Policy API

## 10. Refund Policy

### `POST /content/refund-policy`

Fetches the refund policy content for the application.

**Request:** No body required (POST with empty payload or `{}`).

**Response:**
```json
{
  "success": true,
  "data": {
    "content": "Refund Policy content text goes here. This can include HTML or plain text as returned by the backend."
  }
}
```

| Field | Type | Description |
|---|---|---|
| `content` | String | The refund policy text/HTML content to display |

> **Note:** This API follows the same pattern as `POST /content/terms`, `POST /content/privacy`, and `POST /content/about-us`. The app renders the `content` field as plain text in a scrollable view.
