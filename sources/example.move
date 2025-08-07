/// Example module demonstrating usage of the trading vault system
/// This shows how to initialize vaults, create orders, and manage deposits/withdrawals
module trading_vault::example;

use sui::coin::{Coin};
use sui::clock::Clock;
use trading_vault::vault::{Self, Vault, VaultAdminCap};
use trading_vault::maker_vault::{Self, MakerVault, MakerVaultAdminCap};
use trading_vault::order::{Self, OrderManager, OrderAdminCap, CoordinatorCap};
use trading_vault::types::{Self, TradableAsset};

/// Example function to initialize the entire trading system
public fun initialize_trading_system<T, IthacaType>(
    minimum_stake: u64,
    treasury: address,
    ctx: &mut TxContext
): (
    VaultAdminCap,
    OrderAdminCap,
    CoordinatorCap,
    MakerVaultAdminCap,
    Vault<T>,
    MakerVault<T, IthacaType>,
    OrderManager<T>
) {
    // Initialize vault
    let (vault_admin_cap, vault_order_cap, vault) = vault::initialize<T>(ctx);
    
    // Initialize maker vault  
    let (maker_vault_admin_cap, maker_order_cap, maker_vault) = maker_vault::initialize<T, IthacaType>(minimum_stake, ctx);
    
    // Initialize order manager
    let (order_admin_cap, coordinator_cap, order_manager) = order::initialize<T>(
        vault_order_cap,
        maker_order_cap,
        treasury,
        ctx
    );

    (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap, vault, maker_vault, order_manager)
}

/// Example deposit function
public fun example_deposit<T>(
    vault: &mut Vault<T>,
    payment: Coin<T>,
    ctx: &mut TxContext
) {
    vault::deposit(vault, payment, ctx);
}

/// Example withdrawal function  
public fun example_withdraw<T>(
    order_manager: &mut OrderManager<T>,
    vault: &mut Vault<T>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    order::taker_withdraw(order_manager, vault, amount, ctx)
}

/// Example maker registration
public fun example_register_maker<T, IthacaType>(
    maker_vault: &mut MakerVault<T, IthacaType>,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    maker_vault::register_maker(maker_vault, ithaca_payment, ctx);
}

/// Example collateral deposit
public fun example_deposit_collateral<T, IthacaType>(
    maker_vault: &mut MakerVault<T, IthacaType>,
    asset: TradableAsset,
    payment: Coin<T>,
    ctx: &mut TxContext
) {
    maker_vault::deposit_collateral(maker_vault, asset, payment, ctx);
}

/// Example maker withdrawal with locked balance check
public fun example_maker_withdraw<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    maker_vault: &mut MakerVault<T, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    order::maker_withdraw(order_manager, maker_vault, tradable_asset, amount, ctx)
}

/// Example note creation (coordinator only)
public fun example_create_note<T, IthacaType>(
    coordinator_cap: &CoordinatorCap,
    order_manager: &mut OrderManager<T>,
    vault: &mut Vault<T>,
    maker_vault: &mut MakerVault<T, IthacaType>,
    taker: address,
    maker: address,
    amount: u64,
    starting_price: u64,
    clock: &Clock,
    ctx: &mut TxContext
): u64 {
    // Create note with all fields including additional info
    let note = types::new_note(
        taker,
        maker,
        types::tradable_asset_btc(),
        types::direction_up(),
        amount,
        starting_price,
        1000, // spread: $10 (assuming 2 decimal places)
        amount * 2, // win_payout: 2x
        sui::clock::timestamp_ms(clock) + 1000000, // expiry_time: future timestamp
        1, // nonce
        amount, // refund_payout: return original amount
        500, // almost_win_spread: $5
        amount + (amount / 2), // almost_win_payout: 1.5x
        sui::clock::timestamp_ms(clock), // start_time
    );

    order::create_note(coordinator_cap, order_manager, vault, maker_vault, note, clock, ctx)
}

/// Example note settlement (coordinator only)
public fun example_settle_note<T, IthacaType>(
    coordinator_cap: &CoordinatorCap,
    order_manager: &mut OrderManager<T>,
    vault: &mut Vault<T>,
    maker_vault: &mut MakerVault<T, IthacaType>,
    note_id: u64,
    spot_price: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    order::settle_note(
        coordinator_cap,
        order_manager, 
        vault, 
        maker_vault, 
        note_id, 
        spot_price, 
        clock, 
        ctx
    );
}

// === View functions for checking state ===

public fun check_taker_balance<T>(vault: &Vault<T>, taker: address): u64 {
    vault::taker_balance(vault, taker)
}

public fun check_locked_balance<T>(order_manager: &OrderManager<T>, taker: address): u64 {
    order::taker_locked_balance(order_manager, taker)
}

public fun check_withdrawable_balance<T>(
    order_manager: &OrderManager<T>, 
    vault: &Vault<T>, 
    taker: address
): u64 {
    order::taker_withdrawable_balance(order_manager, vault, taker)
}

public fun check_maker_withdrawable_balance<T, IthacaType>(
    order_manager: &OrderManager<T>,
    maker_vault: &MakerVault<T, IthacaType>,
    maker: address,
    tradable_asset: TradableAsset
): u64 {
    order::maker_withdrawable_balance(order_manager, maker_vault, maker, tradable_asset)
}

public fun check_maker_collateral<T, IthacaType>(
    maker_vault: &MakerVault<T, IthacaType>, 
    maker: address, 
    asset: &TradableAsset
): u64 {
    maker_vault::get_maker_collateral(maker_vault, maker, asset)
}
