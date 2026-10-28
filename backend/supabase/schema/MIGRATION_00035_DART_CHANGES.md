# Dart Call-Site Changes for Migration 00035

Three RPC signatures changed. Each now requires the caller's PIN.
The PIN is already available at the UI layer — it just needs threading through.

---

## 1. `rpc_open_pos_shift` — new parameter: `p_cashier_pin`

**Position:** 3rd parameter (after `p_cashier_id`).

### File 1: `apps/staff_app/lib/providers/staff_providers.dart` ~line 281

The shift notifier `openShift()` receives `cashierId` but not the PIN.
Thread the PIN in from the call site (ShiftAuditDialog / CounterPosScreen).

```dart
// BEFORE
await client!.rpc('rpc_open_pos_shift', params: {
  'p_client_id': clientId,
  'p_cashier_id': cashierId,
  'p_cashier_name': cashierName,
  'p_opening_float': openingFloatCentimes,
  'p_z_report_sequence': zNum,
  'p_opened_at': openedAt.toIso8601String(),
});

// AFTER
await client!.rpc('rpc_open_pos_shift', params: {
  'p_client_id': clientId,
  'p_cashier_id': cashierId,
  'p_cashier_pin': cashierPin,      // ← ADD
  'p_cashier_name': cashierName,
  'p_opening_float': openingFloatCentimes,
  'p_z_report_sequence': zNum,
  'p_opened_at': openedAt.toIso8601String(),
});
```

Also add `cashierPin` to the offline payload so it can be re-sent on sync:

```dart
final payload = {
  'shift_id': shiftId,
  'cashier_id': cashierId,
  'cashier_pin': cashierPin,        // ← ADD to offline payload
  'cashier_name': cashierName,
  'opening_float_centimes': openingFloatCentimes,
  'z_report_number': zNum,
  'opened_at': openedAt.toIso8601String(),
};
```

Update the method signature:

```dart
// BEFORE
Future<void> openShift({
  required String cashierId,
  required String cashierName,
  required int openingFloatCentimes,
  ...
})

// AFTER
Future<void> openShift({
  required String cashierId,
  required String cashierPin,       // ← ADD
  required String cashierName,
  required int openingFloatCentimes,
  ...
})
```

### File 2: `apps/staff_app/lib/services/staff_audit_logger.dart` ~line 96

```dart
// BEFORE
Future<void> logShiftOpened({
  required String cashierId,
  required String cashierName,
  required int openingFloatCentimes,
  required int zReportNumber,
}) async {
  await client.rpc('rpc_open_pos_shift', params: {
    'p_client_id': null,
    'p_cashier_id': cashierId,
    'p_cashier_name': cashierName,
    'p_opening_float': openingFloatCentimes,
    'p_z_report_sequence': zReportNumber,
    'p_opened_at': DateTime.now().toIso8601String(),
  });
}

// AFTER
Future<void> logShiftOpened({
  required String cashierId,
  required String cashierPin,       // ← ADD
  required String cashierName,
  required int openingFloatCentimes,
  required int zReportNumber,
}) async {
  await client.rpc('rpc_open_pos_shift', params: {
    'p_client_id': null,
    'p_cashier_id': cashierId,
    'p_cashier_pin': cashierPin,    // ← ADD
    'p_cashier_name': cashierName,
    'p_opening_float': openingFloatCentimes,
    'p_z_report_sequence': zReportNumber,
    'p_opened_at': DateTime.now().toIso8601String(),
  });
}
```

### File 3: `packages/data/lib/datasources/offline_sync_service.dart` ~line 143

```dart
// BEFORE (offline sync replay)
case 'pos_shift_open':
  await client.rpc('rpc_open_pos_shift', params: {
    'p_client_id': op.clientId,
    'p_cashier_id': payload['cashier_id'],
    'p_cashier_name': payload['cashier_name'] ?? 'غير مسجل',
    'p_opening_float': payload['opening_float_centimes'] ?? 0,
    'p_z_report_sequence': payload['z_report_number'] ?? 0,
    'p_opened_at': payload['opened_at'],
  });

// AFTER
case 'pos_shift_open':
  await client.rpc('rpc_open_pos_shift', params: {
    'p_client_id': op.clientId,
    'p_cashier_id': payload['cashier_id'],
    'p_cashier_pin': payload['cashier_pin'] ?? '',   // ← ADD (from saved payload)
    'p_cashier_name': payload['cashier_name'] ?? 'غير مسجل',
    'p_opening_float': payload['opening_float_centimes'] ?? 0,
    'p_z_report_sequence': payload['z_report_number'] ?? 0,
    'p_opened_at': payload['opened_at'],
  });
```

---

## 2. `rpc_close_pos_shift` — new parameter: `p_cashier_pin`

**Position:** 3rd parameter (after `p_cashier_id`).

### File 1: `apps/staff_app/lib/providers/staff_providers.dart` ~line 400

```dart
// BEFORE
client!.rpc('rpc_close_pos_shift', params: {
  'p_client_id': clientId,
  'p_shift_id': current.id,
  'p_cashier_id': current.cashierId,
  'p_z_report_sequence': summary.zNumber,
  ...
})

// AFTER
client!.rpc('rpc_close_pos_shift', params: {
  'p_client_id': clientId,
  'p_shift_id': current.id,
  'p_cashier_id': current.cashierId,
  'p_cashier_pin': cashierPin,      // ← ADD (thread from closeShift() param)
  'p_z_report_sequence': summary.zNumber,
  ...
})
```

Update `closeShift()` signature:

```dart
// BEFORE
Future<void> closeShift({required ShiftSummary summary, ...})

// AFTER
Future<void> closeShift({
  required String cashierPin,       // ← ADD
  required ShiftSummary summary,
  ...
})
```

Also add to offline payload:

```dart
final payload = {
  ...
  'cashier_pin': cashierPin,        // ← ADD to offline payload for replay
};
```

### File 2: `apps/staff_app/lib/services/staff_audit_logger.dart` ~line 126

```dart
// BEFORE
Future<void> logShiftClosed({
  required String cashierId,
  required String cashierName,
  required int zNumber,
  ...
}) async {
  await client.rpc('rpc_close_pos_shift', params: {
    'p_client_id': null,
    'p_cashier_id': cashierId,
    'p_z_report_sequence': zNumber,
    ...
  });
}

// AFTER
Future<void> logShiftClosed({
  required String cashierId,
  required String cashierPin,       // ← ADD
  required String cashierName,
  required int zNumber,
  ...
}) async {
  await client.rpc('rpc_close_pos_shift', params: {
    'p_client_id': null,
    'p_cashier_id': cashierId,
    'p_cashier_pin': cashierPin,    // ← ADD
    'p_z_report_sequence': zNumber,
    ...
  });
}
```

### File 3: `packages/data/lib/datasources/offline_sync_service.dart` ~line 153

```dart
// BEFORE
case 'pos_shift_close':
  await client.rpc('rpc_close_pos_shift', params: {
    'p_client_id': op.clientId,
    'p_cashier_id': payload['cashier_id'],
    'p_z_report_sequence': payload['z_number'] ?? 0,
    ...
  });

// AFTER
case 'pos_shift_close':
  await client.rpc('rpc_close_pos_shift', params: {
    'p_client_id': op.clientId,
    'p_cashier_id': payload['cashier_id'],
    'p_cashier_pin': payload['cashier_pin'] ?? '',   // ← ADD
    'p_z_report_sequence': payload['z_number'] ?? 0,
    ...
  });
```

---

## 3. `rpc_adjust_stock` — new parameter: `p_caller_pin`

**Position:** 2nd parameter (after `p_user_id`).

The old signature was: `(p_user_id, p_product_id, p_qty_change, p_reason)`
The new signature is:  `(p_user_id, p_caller_pin, p_product_id, p_qty_change, p_reason)`

### File: `packages/data/lib/datasources/remote/supabase_service.dart` ~line 111

```dart
// BEFORE
Future<Map<String, dynamic>> adjustStock({
  required String userId,
  required String productId,
  required int qtyChange,
  required String reason,
}) async {
  final response = await client.rpc('rpc_adjust_stock', params: {
    'p_user_id': userId,
    'p_product_id': productId,
    'p_qty_change': qtyChange,
    'p_reason': reason,
  });
  return Map<String, dynamic>.from(response as Map);
}

// AFTER
Future<Map<String, dynamic>> adjustStock({
  required String userId,
  required String callerPin,        // ← ADD
  required String productId,
  required int qtyChange,
  required String reason,
}) async {
  final response = await client.rpc('rpc_adjust_stock', params: {
    'p_user_id': userId,
    'p_caller_pin': callerPin,      // ← ADD
    'p_product_id': productId,
    'p_qty_change': qtyChange,
    'p_reason': reason,
  });
  return Map<String, dynamic>.from(response as Map);
}
```

### Where to get the PIN for adjustStock:

`StockAdjustmentDialog` already shows to managers/moderators who are logged in.
The active user's PIN was verified at login — but not stored in plaintext (correct: `StaffLocalAuthStore` only stores a hash).

**Solution:** show a compact PIN re-confirmation prompt in `StockAdjustmentDialog._submitAdjustment()`:

```dart
// In stock_adjustment_dialog.dart _submitAdjustment():

// 1. Collect PIN from the active user
final activeUser = ref.read(authStateProvider);  // existing provider
if (activeUser == null) return;

final pin = await showDialog<String>(
  context: context,
  builder: (_) => _PinConfirmDialog(userName: activeUser.name),
);
if (pin == null || pin.isEmpty) return;   // user cancelled

// 2. Pass to adjustStock
await inventoryRepo.adjustStock(
  userId: activeUser.id,
  callerPin: pin,                         // ← thread through
  productId: _selectedProductId!,
  qtyChange: _qtyChange,
  reason: _notesController.text.trim(),
);
```

The `_PinConfirmDialog` is a simple 4-digit PIN entry widget — you likely already
have `CashierPinDialog` that can be reused for this pattern.

---

## Where the PIN comes from at each call site

| Call site | PIN source |
|---|---|
| `ShiftAuditDialog` open/close | Already collected from `CashierPinDialog` at shift start — thread it into `openShift()` / `closeShift()` |
| `staff_audit_logger.dart` | Called from `CounterPosScreen` after PIN dialog — pass same PIN used to verify |
| `offline_sync_service.dart` | Stored in the offline payload at the time of the original call (while online verification happened) |
| `StockAdjustmentDialog` | Show `_PinConfirmDialog` before submit — same pattern used for other sensitive actions |

> **Security note:** The PIN string is only held in memory for the duration of
> the RPC call. It is never persisted to disk (only the SHA-256 hash is stored
> locally by `StaffLocalAuthStore`). The bcrypt comparison happens server-side
> in `_internal_verify_and_track_pin`. This is the correct flow.
