/// Maker Vault module for managing maker liquidity, staking, and collateral
module odyssey_sui::maker_vault;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::event;
use odyssey_sui::types::{Self, MakerInfo};
use std::string::String;

// === Constants ===

/// Current version of the maker vault module
const VERSION: u64 = 1;

// === Errors ===

#[error]
const ENotZeroAmount: vector<u8> = b"Amount must be greater than zero";

#[error]
const EInsufficientStake: vector<u8> = b"Insufficient stake amount for maker registration";

#[error]
const EMakerAlreadyRegistered: vector<u8> = b"Maker is already registered in the vault";

#[error]
const EMakerNotAvailable: vector<u8> = b"Maker is not available or not registered";

#[error]
const EInsufficientCollateral: vector<u8> = b"Insufficient collateral for this operation";

#[error]
const ECollateralMustBeZero: vector<u8> = b"Collateral amount must be zero for this operation";

#[error]
const ENotAdmin: vector<u8> = b"Not the right admin for this maker vault";

#[error]
const ENotUpgrade: vector<u8> = b"Migration is not an upgrade";

#[error]
const EWrongVersion: vector<u8> = b"Calling functions from the wrong package version";

#[error]
const EInvalidSymbol: vector<u8> = b"Symbol is not allowed for maker registration";

// === Structs ===

/// Administrative capability for maker vault operations
public struct MakerVaultAdminCap has key, store {
    id: UID,
}

/// Order capability - allows order module to call restricted functions
public struct MakerOrderCap has key, store {
    id: UID,
}

/// Main maker vault object that holds maker information and collateral
public struct MakerVault<phantom T, phantom IthacaType> has key {
    id: UID,
    /// Current version of this maker vault instance
    version: u64,
    /// Admin capability ID that controls this vault
    admin: ID,
    /// Mapping of maker + symbol to their info
    makers: Table<MakerSymbolKey, MakerInfo>,
    /// Minimum stake amount required to become a maker
    minimum_stake_amount: u64,
    /// Custom minimum stake amounts for specific assets
    custom_min_stake_amounts: Table<String, u64>,
    /// Whitelist of allowed trading symbols
    allowed_symbols: Table<String, bool>,
    /// The actual collateral coin balance held by the vault
    collateral_balance: Balance<T>,
    /// The Ithaca token balance held by the vault for staking
    ithaca_balance: Balance<IthacaType>,
}

/// Key for maker info (maker address + symbol)
public struct MakerSymbolKey has copy, drop, store {
    maker: address,
    symbol: String,
}


// === Events ===

/// Emitted when a maker registers
public struct MakerRegistered has copy, drop {
    maker: address,
    stake_amount: u64,
}

/// Emitted when a maker unregisters
public struct MakerUnregistered has copy, drop {
    maker: address,
}

/// Emitted when a symbol is added to allowed list
public struct SymbolAdded has copy, drop {
    symbol: String,
}

/// Emitted when a symbol is removed from allowed list
public struct SymbolRemoved has copy, drop {
    symbol: String,
}

/// Emitted when maker deposits collateral
public struct CollateralDeposited has copy, drop {
    maker: address,
    symbol: String,
    amount: u64,
}

/// Emitted when maker withdraws collateral
public struct CollateralWithdrawn has copy, drop {
    maker: address,
    symbol: String,
    amount: u64,
}

/// Emitted when minimum stake amount is set
public struct MinimumStakeAmountSet has copy, drop {
    amount: u64,
}

/// Emitted when custom minimum stake amount is set
public struct CustomMinStakeAmountSet has copy, drop {
    symbol: String,
    amount: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let admin_cap = MakerVaultAdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(
        admin_cap,
        ctx.sender()
    )   
}

// === Public Functions ===

/// Initialize a new maker vault
/// Returns order capability
public fun initialize<T, IthacaType>(
    admin_cap: &MakerVaultAdminCap,
    minimum_stake_amount: u64,
    initial_symbols: vector<String>,
    ctx: &mut TxContext
): (MakerOrderCap) {
    assert!(minimum_stake_amount > 0, ENotZeroAmount);

    let order_cap = MakerOrderCap {
        id: object::new(ctx),
    };

    let mut allowed_symbols = table::new<String, bool>(ctx);

    // Add initial symbols to the allowed list
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
        minimum_stake_amount,
        custom_min_stake_amounts: table::new(ctx),
        allowed_symbols,
        collateral_balance: balance::zero<T>(),
        ithaca_balance: balance::zero<IthacaType>(),
    };

    transfer::share_object(vault);

    (order_cap)
}

/// Register as a maker by staking Ithaca tokens
public fun register_maker_symbol<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    assert!(vault.version == VERSION, EWrongVersion);

    // Validate that the symbol is allowed
    assert!(table::contains(&vault.allowed_symbols, symbol), EInvalidSymbol);

    let sender = tx_context::sender(ctx);
    let stake_amount = coin::value(&ithaca_payment);

    let key = MakerSymbolKey {
        maker: sender,
        symbol,
    };

    assert!(stake_amount > 0, ENotZeroAmount);
    assert!(!table::contains(&vault.makers, key), EMakerAlreadyRegistered);

    let symbol_min_stake = get_min_stake_amount(vault, symbol);
    assert!(stake_amount >= symbol_min_stake, EInsufficientStake);

    // Create maker info
    let maker_info = types::new_maker_info(stake_amount);
    table::add(&mut vault.makers, key, maker_info);

    // Add Ithaca tokens to vault balance
    let ithaca_balance = coin::into_balance(ithaca_payment);
    balance::join(&mut vault.ithaca_balance, ithaca_balance);

    // Emit event
    event::emit(MakerRegistered {
        maker: sender,
        stake_amount,
    });
}

/// Unregister as a maker and withdraw all staked Ithaca tokens
public fun unregister_maker<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    ctx: &mut TxContext
): Coin<IthacaType> {
    assert!(vault.version == VERSION, EWrongVersion);
    
    let sender = tx_context::sender(ctx);
    let key = MakerSymbolKey {
        maker: sender,
        symbol,
    };
    assert!(table::contains(&vault.makers, key), EMakerNotAvailable);
    
    let maker_info = table::remove(&mut vault.makers, key);
    
    // Check that the collateral is zero
    assert!(types::maker_info_collateral(&maker_info) == 0, ECollateralMustBeZero);

    let staked_amount = types::maker_info_staked_tokens(&maker_info);
    
    // Withdraw Ithaca tokens
    let withdrawn_balance = balance::split(&mut vault.ithaca_balance, staked_amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);

    // Emit event
    event::emit(MakerUnregistered {
        maker: sender,
    });

    withdrawn_coin
}

/// Deposit collateral for a specific tradable asset
public fun deposit_collateral<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    payment: Coin<T>,
    ctx: &mut TxContext
) {
    assert!(vault.version == VERSION, EWrongVersion);
    
    let sender = tx_context::sender(ctx);
    let amount = coin::value(&payment);
    let key = MakerSymbolKey {
        maker: sender,
        symbol,
    };

    assert!(amount > 0, ENotZeroAmount);
    assert!(table::contains(&vault.makers, key), EMakerNotAvailable);

    // Update collateral
    let maker_info = table::borrow_mut(&mut vault.makers, key);
    types::add_maker_collateral(maker_info, amount);

    // Add payment to vault balance
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.collateral_balance, payment_balance);

    // Emit event
    event::emit(CollateralDeposited {
        maker: sender,
        symbol,
        amount,
    });
}

/// Withdraw collateral for a specific tradable asset (order module only)
/// This considers locked amounts in orders for security
public fun withdraw_collateral<T, IthacaType>(
    _order_cap: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    maker: address,
    symbol: String,
    locked_amount: u64,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(vault.version == VERSION, EWrongVersion);
    assert!(amount > 0, ENotZeroAmount);

    let key = MakerSymbolKey {
        maker,
        symbol,
    };
    assert!(table::contains(&vault.makers, key), EMakerNotAvailable);

    let withdrawable_balance = get_withdrawable_balance_with_locked(vault, maker, symbol, locked_amount);
    assert!(amount <= withdrawable_balance, EInsufficientCollateral);

    let maker_info = table::borrow_mut(&mut vault.makers, key);
    
    // Update collateral
    types::subtract_maker_collateral(maker_info, amount);

    // Extract coin from vault balance
    let withdrawn_balance = balance::split(&mut vault.collateral_balance, amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);

    // Emit event
    event::emit(CollateralWithdrawn {
        maker,
        symbol,
        amount,
    });

    withdrawn_coin
}

// === Admin Functions ===

/// Migrate maker vault to new version (admin only)
entry fun migrate<T, IthacaType>(vault: &mut MakerVault<T, IthacaType>, admin_cap: &MakerVaultAdminCap) {
    assert!(vault.admin == object::id(admin_cap), ENotAdmin);
    assert!(vault.version < VERSION, ENotUpgrade);
    vault.version = VERSION;
}

/// Set minimum stake amount (admin only)
public fun set_minimum_stake_amount<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    amount: u64,
) {
    assert!(vault.version == VERSION, EWrongVersion);
    vault.minimum_stake_amount = amount;

    event::emit(MinimumStakeAmountSet {
        amount,
    });
}

/// Add a symbol to the allowed list (admin only)
public fun add_allowed_symbol<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
) {
    assert!(vault.version == VERSION, EWrongVersion);

    if (!table::contains(&vault.allowed_symbols, symbol)) {
        table::add(&mut vault.allowed_symbols, symbol, true);

        event::emit(SymbolAdded { symbol });
    }
}

/// Remove a symbol from the allowed list (admin only)
public fun remove_allowed_symbol<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
) {
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

/// Set custom minimum stake amount for specific asset (admin only)
public fun set_custom_min_stake_amount<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    symbol: String,
    amount: u64,
) {
    assert!(vault.version == VERSION, EWrongVersion);
    
    if (table::contains(&vault.custom_min_stake_amounts, symbol)) {
        table::remove(&mut vault.custom_min_stake_amounts, symbol);
    };
    
    table::add(&mut vault.custom_min_stake_amounts, symbol, amount);

    event::emit(CustomMinStakeAmountSet {
        symbol,
        amount,
    });
}

// === Order Module Functions (restricted) ===

/// Transfer collateral to taker vault (order module only)
public(package) fun transfer_to_taker_vault<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(vault.version == VERSION, EWrongVersion);
    let transfer_balance = balance::split(&mut vault.collateral_balance, amount);
    coin::from_balance(transfer_balance, ctx)
}

/// Adjust maker balance (order module only)
public(package) fun adjust_maker_balance<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    maker: address,
    symbol: String,
    amount: u64,
    is_win: bool,
) {
    assert!(vault.version == VERSION, EWrongVersion);
    
    let key = MakerSymbolKey {
        maker,
        symbol,
    };
    assert!(table::contains(&vault.makers, key), EMakerNotAvailable);
    
    let maker_info = table::borrow_mut(&mut vault.makers, key);
    
    if (is_win) {
        // Increase maker collateral
        types::add_maker_collateral(maker_info, amount);
    } else {
        // Decrease maker collateral
        types::subtract_maker_collateral(maker_info, amount);
    }
}

/// Transfer fee to treasury (order module only)
public(package) fun transfer_fee_to_treasury<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    maker: address,
    symbol: String,
    fee: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(vault.version == VERSION, EWrongVersion);

    let key = MakerSymbolKey {
        maker,
        symbol,
    };
    assert!(table::contains(&vault.makers, key), EMakerNotAvailable);
    
    // Reduce maker collateral
    let maker_info = table::borrow_mut(&mut vault.makers, key);
    types::subtract_maker_collateral(maker_info, fee);

    // Extract fee from vault balance
    let fee_balance = balance::split(&mut vault.collateral_balance, fee);
    coin::from_balance(fee_balance, ctx)
}

/// Add funds to vault from outside (order module only)
/// Used when funds are transferred from taker vault to maker vault
public(package) fun add_funds<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    payment: Coin<T>,
) {
    assert!(vault.version == VERSION, EWrongVersion);
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.collateral_balance, payment_balance);
    // Note: collateral balance is automatically updated via balance::join
}

// === View Functions ===

/// Get maker staked tokens for specific asset
public fun get_maker_staked_ithaca<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>,
    maker: address,
    symbol: String
): u64 {
    let key = MakerSymbolKey {
        maker,
        symbol,
    };
    if (table::contains(&vault.makers, key)) {
        let maker_info = table::borrow(&vault.makers, key);
        types::maker_info_staked_tokens(maker_info)
    } else {
        0
    }
}

/// Get maker collateral for specific asset
public fun get_maker_collateral<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
    maker: address,
    symbol: String
): u64 {
    let key = MakerSymbolKey {
        maker,
        symbol,
    };
    if (table::contains(&vault.makers, key)) {
        let maker_info = table::borrow(&vault.makers, key);
        types::maker_info_collateral(maker_info)
    } else {
        0
    }
}

/// Get withdrawable balance considering locked amounts in orders
public fun get_withdrawable_balance_with_locked<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>,
    maker: address,
    symbol: String,
    locked_amount: u64
): u64 {
    let total_collateral = get_maker_collateral(vault, maker, symbol);
    if (total_collateral >= locked_amount) {
        total_collateral - locked_amount
    } else {
        0
    }
}

/// Get minimum stake amount for a tradable asset
public fun get_min_stake_amount<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
    symbol: String
): u64 {
    if (table::contains(&vault.custom_min_stake_amounts, symbol)) {
        *table::borrow(&vault.custom_min_stake_amounts, symbol)
    } else {
        vault.minimum_stake_amount
    }
}

/// Get total asset available
public fun total_asset_available<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>
): u64 {
    balance::value(&vault.collateral_balance)
}

/// Get vault Ithaca balance value
public fun vault_ithaca_balance_value<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>
): u64 {
    balance::value(&vault.ithaca_balance)
}

/// Get minimum stake amount
public fun minimum_stake_amount<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>
): u64 {
    vault.minimum_stake_amount
}


// --------------------
// === Test Helpers ===
// --------------------
#[test_only]
use sui::test_utils::assert_eq;

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx)
}

#[test_only]
public fun assert_maker_registered_event(
    maker: address,
    stake_amount: u64,
) {
    let emitted = event::events_by_type<MakerRegistered>()[0];
    assert_eq(emitted.maker, maker);
    assert_eq(emitted.stake_amount, stake_amount);
}

#[test_only]
public fun assert_maker_unregistered_event(
    maker: address,
) {
    let emitted = event::events_by_type<MakerUnregistered>()[0];
    assert_eq(emitted.maker, maker);
}

#[test_only]
public fun assert_collateral_deposited_event(
    maker: address,
    amount: u64,
) {
    let emitted = event::events_by_type<CollateralDeposited>()[0];
    assert_eq(emitted.maker, maker);
    assert_eq(emitted.amount, amount);
}

#[test_only]
public fun assert_collateral_withdrawn_event(
    maker: address,
    amount: u64,
) {
    let emitted = event::events_by_type<CollateralWithdrawn>()[0];
    assert_eq(emitted.maker, maker);
    assert_eq(emitted.amount, amount);
}

#[test_only]
public fun assert_minimum_stake_amount_set_event(
    amount: u64,
) {
    let emitted = event::events_by_type<MinimumStakeAmountSet>()[0];
    assert_eq(emitted.amount, amount);
}

#[test_only]
public fun assert_custom_min_stake_amount_set_event(
    amount: u64,
) {
    let emitted = event::events_by_type<CustomMinStakeAmountSet>()[0];
    assert_eq(emitted.amount, amount);
}

