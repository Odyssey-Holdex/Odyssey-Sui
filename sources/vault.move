/// Vault module for managing trader deposits, withdrawals, and balances
module trading_vault::vault;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::event;

// === Errors ===

#[error]
const ENotZeroAmount: vector<u8> = b"Amount must be greater than zero";

#[error]
const ENotZeroAddress: vector<u8> = b"Address cannot be zero";

#[error]
const EInsufficientBalance: vector<u8> = b"Insufficient balance for this operation";

// === Structs ===

/// Administrative capability for vault operations
public struct VaultAdminCap has key, store {
    id: UID,
}

/// Order capability - allows order module to call restricted functions
public struct OrderCap has key, store {
    id: UID,
}

/// Main vault object that holds balances and assets
public struct Vault<phantom T> has key {
    id: UID,
    /// Mapping of taker address to their balance
    taker_balances: Table<address, u64>,
    /// The actual coin balance held by the vault
    balance: Balance<T>,
}

// === Events ===

/// Emitted when trader deposits assets
public struct Deposited has copy, drop {
    trader: address,
    amount: u64,
}

/// Emitted when trader withdraws assets
public struct Withdrawn has copy, drop {
    trader: address,
    amount: u64,
}





// === Public Functions ===

/// Initialize a new vault with given asset type
/// Returns admin capability and order capability
public fun initialize<T>(ctx: &mut TxContext): (VaultAdminCap, OrderCap, Vault<T>) {
    let admin_cap = VaultAdminCap {
        id: object::new(ctx),
    };
    
    let order_cap = OrderCap {
        id: object::new(ctx),
    };

    let vault = Vault<T> {
        id: object::new(ctx),
        taker_balances: table::new(ctx),
        balance: balance::zero<T>(),
    };

    (admin_cap, order_cap, vault)
}

/// Deposit assets into the vault
public fun deposit<T>(
    vault: &mut Vault<T>,
    payment: Coin<T>,
    ctx: &mut TxContext
) {
    let amount = coin::value(&payment);
    assert!(amount > 0, ENotZeroAmount);
    
    let sender = tx_context::sender(ctx);

    // Add to taker balance
    if (table::contains(&vault.taker_balances, sender)) {
        let current_balance = table::remove(&mut vault.taker_balances, sender);
        table::add(&mut vault.taker_balances, sender, current_balance + amount);
    } else {
        table::add(&mut vault.taker_balances, sender, amount);
    };

    // Add coin to vault balance
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.balance, payment_balance);

    // Emit event
    event::emit(Deposited {
        trader: sender,
        amount,
    });
}

/// Withdraw assets from the vault
public fun withdraw<T>(
    order_cap: &OrderCap, // Order capability to restrict access
    vault: &mut Vault<T>,
    amount: u64,
    locked_amount: u64, // Amount locked in orders
    ctx: &mut TxContext
): Coin<T> {
    assert!(amount > 0, ENotZeroAmount);
    
    let sender = tx_context::sender(ctx);
    let withdrawable_balance = get_withdrawable_balance_with_locked(order_cap, vault, sender, locked_amount);
    
    assert!(amount <= withdrawable_balance, EInsufficientBalance);

    // Update taker balance
    let current_balance = table::remove(&mut vault.taker_balances, sender);
    if (current_balance > amount) {
        table::add(&mut vault.taker_balances, sender, current_balance - amount);
    };

    

    // Extract coin from vault balance
    let withdrawn_balance = balance::split(&mut vault.balance, amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);

    // Emit event
    event::emit(Withdrawn {
        trader: sender,
        amount,
    });

    withdrawn_coin
}

// === Admin Functions ===
// Note: Asset type changes not supported in Move - types are immutable after creation

// === Order Module Functions (restricted) ===

/// Transfer assets to maker vault (order module only)
public fun transfer_to_maker_vault<T>(
    _: &OrderCap,
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    let transfer_balance = balance::split(&mut vault.balance, amount);
    coin::from_balance(transfer_balance, ctx)
}

/// Adjust taker balance (order module only)
/// Used to credit/debit taker balance based on trade outcomes
public fun adjust_taker_balance<T>(
    _: &OrderCap,
    vault: &mut Vault<T>,
    taker: address,
    amount: u64,
    is_win: bool,
) {
    if (is_win) {
        // Increase taker balance (taker won)
        if (table::contains(&vault.taker_balances, taker)) {
            let current_balance = table::remove(&mut vault.taker_balances, taker);
            table::add(&mut vault.taker_balances, taker, current_balance + amount);
        } else {
            table::add(&mut vault.taker_balances, taker, amount);
        };
    } else {
        // Decrease taker balance (taker lost)
        if (table::contains(&vault.taker_balances, taker)) {
            let current_balance = table::remove(&mut vault.taker_balances, taker);
            if (current_balance > amount) {
                table::add(&mut vault.taker_balances, taker, current_balance - amount);
            };
        };
    }
}

/// Transfer fee to treasury (order module only)
public fun transfer_fee_to_treasury<T>(
    _: &OrderCap,
    vault: &mut Vault<T>,
    taker: address,
    fee: u64,
    ctx: &mut TxContext
): Coin<T> {
    // Reduce taker balance
    if (table::contains(&vault.taker_balances, taker)) {
        let current_balance = table::remove(&mut vault.taker_balances, taker);
        if (current_balance > fee) {
            table::add(&mut vault.taker_balances, taker, current_balance - fee);
        };
    };

    // Extract fee from vault balance
    let fee_balance = balance::split(&mut vault.balance, fee);
    coin::from_balance(fee_balance, ctx)
}

/// Add funds to vault from outside (order module only)
/// Used when funds are transferred from maker vault to trader vault
public fun add_funds<T>(
    _: &OrderCap,
    vault: &mut Vault<T>,
    payment: Coin<T>,
) {
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.balance, payment_balance);
    // Note: vault balance is automatically updated via balance::join
}

// === View Functions ===

/// Get taker balance
public fun taker_balance<T>(vault: &Vault<T>, taker: address): u64 {
    if (table::contains(&vault.taker_balances, taker)) {
        *table::borrow(&vault.taker_balances, taker)
    } else {
        0
    }
}

/// Get total asset available
public fun total_asset_available<T>(vault: &Vault<T>): u64 {
    balance::value(&vault.balance)
}

/// Get withdrawable balance considering locked amounts in orders
public fun get_withdrawable_balance_with_locked<T>(
    _: &OrderCap, // Order capability to restrict access
    vault: &Vault<T>, 
    taker: address, 
    locked_amount: u64
): u64 {
    let total_balance = taker_balance(vault, taker);
    if (total_balance >= locked_amount) {
        total_balance - locked_amount
    } else {
        0
    }
}


// === Helper Functions ===

/// Check if vault has sufficient balance for withdrawal
public fun check_vault_balance<T>(vault: &Vault<T>, amount: u64): bool {
    balance::value(&vault.balance) >= amount
}

/// Validate that amount is not zero
public fun validate_amount(amount: u64) {
    assert!(amount > 0, ENotZeroAmount);
}

/// Validate that address is not zero
public fun validate_address(addr: address) {
    assert!(addr != @0x0, ENotZeroAddress);
}
