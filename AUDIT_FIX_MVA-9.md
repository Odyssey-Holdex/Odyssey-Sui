# Audit Issue MVA-9: Unrestricted Symbols - Fix Proposal

## Issue Summary

**Severity**: Medium
**Status**: Pending
**Code Location**: `sources/maker_vault.move#184`

The `register_maker_symbol()` function accepts any arbitrary string as a `symbol` parameter. This allows users to register as makers for undefined or invalid trading symbols, which could lead to:

1. **Incorrect staking requirements**: Users might bypass intended minimum stake amounts by using undefined symbols
2. **Database pollution**: Unlimited symbols can bloat the `makers` table with invalid entries
3. **Inconsistent behavior**: Different symbols may have different stake requirements, but undefined symbols fall back to the default

## Current Behavior

```move
public fun register_maker_symbol<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,  // ← No validation
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
)
```

The `get_min_stake_amount()` function returns:
- Custom minimum if symbol exists in `custom_min_stake_amounts` table
- Default `minimum_stake_amount` otherwise

This means any random symbol will use the default stake amount, which may be incorrect.

## Proposed Solutions

### **Option 1: Whitelist Approach (Recommended)**

Add a table of allowed symbols to the `MakerVault` struct and validate against it.

#### Implementation:

**1. Update the MakerVault struct:**

```move
public struct MakerVault<phantom T, phantom IthacaType> has key {
    id: UID,
    version: u64,
    admin: ID,
    makers: Table<MakerSymbolKey, MakerInfo>,
    minimum_stake_amount: u64,
    custom_min_stake_amounts: Table<String, u64>,
    collateral_balance: Balance<T>,
    ithaca_balance: Balance<IthacaType>,
    // NEW: Whitelist of allowed trading symbols
    allowed_symbols: Table<String, bool>,
}
```

**2. Add new error code:**

```move
#[error]
const EInvalidSymbol: vector<u8> = b"Symbol is not allowed for maker registration";
```

**3. Add admin function to manage symbols:**

```move
/// Add a symbol to the allowed list (admin only)
public fun add_allowed_symbol<T, IthacaType>(
    admin_cap: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
) {
    assert!(vault.admin == object::id(admin_cap), ENotAdmin);
    assert!(vault.version == VERSION, EWrongVersion);

    if (!table::contains(&vault.allowed_symbols, symbol)) {
        table::add(&mut vault.allowed_symbols, symbol, true);

        event::emit(SymbolAdded { symbol });
    }
}

/// Remove a symbol from the allowed list (admin only)
public fun remove_allowed_symbol<T, IthacaType>(
    admin_cap: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
) {
    assert!(vault.admin == object::id(admin_cap), ENotAdmin);
    assert!(vault.version == VERSION, EWrongVersion);

    if (table::contains(&vault.allowed_symbols, symbol)) {
        table::remove(&mut vault.allowed_symbols, symbol);

        event::emit(SymbolRemoved { symbol });
    }
}

/// Check if a symbol is allowed
public fun is_symbol_allowed<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>,
    symbol: String,
): bool {
    table::contains(&vault.allowed_symbols, symbol)
}
```

**4. Add validation to register_maker_symbol:**

```move
public fun register_maker_symbol<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    assert!(vault.version == VERSION, EWrongVersion);

    // NEW: Validate symbol is allowed
    assert!(table::contains(&vault.allowed_symbols, symbol), EInvalidSymbol);

    let sender = tx_context::sender(ctx);
    let key = MakerSymbolKey {
        maker: sender,
        symbol,
    };

    // ... rest of the function remains the same
}
```

**5. Add events:**

```move
public struct SymbolAdded has copy, drop {
    symbol: String,
}

public struct SymbolRemoved has copy, drop {
    symbol: String,
}
```

**6. Update initialize function:**

```move
public fun initialize<T, IthacaType>(
    admin_cap: &MakerVaultAdminCap,
    default_minimum_stake_amount: u64,
    initial_symbols: vector<String>,  // NEW: Initialize with allowed symbols
    ctx: &mut TxContext
): MakerOrderCap {
    assert!(default_minimum_stake_amount > 0, ENotZeroAmount);

    let maker_order_cap = MakerOrderCap {
        id: object::new(ctx),
    };

    let mut allowed_symbols = table::new<String, bool>(ctx);

    // Add initial symbols
    let mut i = 0;
    let len = vector::length(&initial_symbols);
    while (i < len) {
        let symbol = *vector::borrow(&initial_symbols, i);
        table::add(&mut allowed_symbols, symbol, true);
        i = i + 1;
    };

    let vault = MakerVault<T, IthacaType> {
        id: object::new(ctx),
        version: VERSION,
        admin: object::id(admin_cap),
        makers: table::new(ctx),
        minimum_stake_amount: default_minimum_stake_amount,
        custom_min_stake_amounts: table::new(ctx),
        collateral_balance: balance::zero<T>(),
        ithaca_balance: balance::zero<IthacaType>(),
        allowed_symbols,  // NEW
    };

    transfer::share_object(vault);
    maker_order_cap
}
```

**7. Update migration function:**

```move
entry fun migrate<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    admin_cap: &MakerVaultAdminCap
) {
    assert!(vault.admin == object::id(admin_cap), ENotAdmin);
    assert!(vault.version < VERSION, ENotUpgrade);

    // If migrating from version 1 to version 2, add allowed_symbols table
    if (vault.version == 1) {
        // Initialize empty allowed_symbols table
        // Note: Admin will need to populate this after migration
        vault.allowed_symbols = table::new(ctx);
    }

    vault.version = VERSION;
}
```

---

### **Option 2: Pattern Validation Approach**

Validate symbol format using string pattern matching.

#### Implementation:

```move
/// Validate symbol format (uppercase letters only, 2-10 characters)
fun validate_symbol(symbol: &String): bool {
    let bytes = string::bytes(symbol);
    let len = vector::length(bytes);

    // Check length (e.g., BTC, ETH, AAPL, etc.)
    if (len < 2 || len > 10) {
        return false
    };

    // Check all characters are uppercase letters
    let mut i = 0;
    while (i < len) {
        let char = *vector::borrow(bytes, i);
        // ASCII: A=65, Z=90
        if (char < 65 || char > 90) {
            return false
        };
        i = i + 1;
    };

    true
}

// Add to register_maker_symbol:
assert!(validate_symbol(&symbol), EInvalidSymbol);
```

**Pros**: Simple, no storage overhead
**Cons**: Doesn't prevent invalid but well-formatted symbols (e.g., "FAKE")

---

### **Option 3: Hybrid Approach (Most Secure)**

Combine both whitelist and format validation.

```move
public fun register_maker_symbol<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    assert!(vault.version == VERSION, EWrongVersion);

    // Step 1: Validate format
    assert!(validate_symbol(&symbol), EInvalidSymbol);

    // Step 2: Check whitelist
    assert!(table::contains(&vault.allowed_symbols, symbol), EInvalidSymbol);

    // ... rest of function
}
```

---

## Recommended Solution: Option 1 (Whitelist)

**Rationale:**
1. **Most secure**: Only explicitly allowed symbols can be used
2. **Flexible**: Admin can add/remove symbols as markets evolve
3. **Transparent**: Users can query which symbols are allowed
4. **Compatible**: Works with existing custom minimum stake system

**Deployment Steps:**
1. Deploy updated contract with `allowed_symbols` table
2. Initialize with common symbols: `["BTC", "ETH", "SOL", "USDC", etc.]`
3. Use `add_allowed_symbol()` to expand as needed
4. Existing registrations remain valid (grandfather clause)

---

## Testing Requirements

Add the following tests:

```move
#[test]
#[expected_failure(abort_code = maker_vault::EInvalidSymbol)]
public fun test_register_with_invalid_symbol_fails() {
    // Try to register with a symbol not in allowed list
}

#[test]
public fun test_register_with_allowed_symbol_succeeds() {
    // Register with a whitelisted symbol
}

#[test]
public fun test_admin_can_add_remove_symbols() {
    // Test add_allowed_symbol and remove_allowed_symbol
}

#[test]
#[expected_failure]
public fun test_non_admin_cannot_add_symbols() {
    // Verify only admin can modify allowed symbols
}
```

---

## Security Considerations

1. **Backward Compatibility**: Existing makers registered before the fix will remain valid
2. **Migration Path**: Use the `migrate()` function to add `allowed_symbols` table to existing vaults
3. **Admin Control**: Only admin can modify the symbol whitelist, preventing unauthorized additions
4. **Gas Costs**: Minimal - one table lookup per registration

---

## Summary

**Fix**: Add an `allowed_symbols` whitelist to the `MakerVault` struct and validate against it in `register_maker_symbol()`.

**Impact**:
- ✅ Prevents registration with invalid symbols
- ✅ Ensures correct minimum stake amounts are applied
- ✅ Reduces database pollution
- ✅ Maintains backward compatibility with migration support

**Effort**: Medium (requires contract upgrade and migration)
