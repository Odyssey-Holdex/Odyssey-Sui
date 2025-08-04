/// Maker Vault module for managing maker liquidity, staking, and collateral
module trading_vault::maker_vault;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::object::{Self, UID};
use sui::transfer;
use sui::tx_context::{Self, TxContext};
use sui::table::{Self, Table};
use sui::event;
use trading_vault::types::{Self, TradableAsset, MakerInfo};

// === Errors ===

const ENotZeroAmount: u64 = 1;
const ENotZeroAddress: u64 = 2;
const EOnlyByMaker: u64 = 3;
const EOnlyByOrder: u64 = 4;
const EInsufficientStake: u64 = 5;
const EMakerAlreadyRegistered: u64 = 6;
const EMakerNotAvailable: u64 = 7;
const EInsufficientCollateral: u64 = 8;
const ECollateralMustBeZero: u64 = 9;
const ENotZeroTotalAssetAvailable: u64 = 10;
const ESameValue: u64 = 11;
const EUnauthorized: u64 = 12;

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
public struct MakerVault<phantom CollateralType, phantom IthacaType> has key {
    id: UID,
    /// Total available collateral assets in the vault
    total_asset_available: u64,
    /// Mapping of maker address to their info
    makers: Table<address, MakerInfo>,
    /// Minimum stake amount required to become a maker
    minimum_stake_amount: u64,
    /// Custom minimum stake amounts for specific assets
    custom_min_stake_amounts: Table<TradableAsset, u64>,
    /// The actual collateral coin balance held by the vault
    collateral_balance: Balance<CollateralType>,
    /// The Ithaca token balance held by the vault for staking
    ithaca_balance: Balance<IthacaType>,
    /// Address of the order module that can call restricted functions
    order_module: address,
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

/// Emitted when maker deposits collateral
public struct CollateralDeposited has copy, drop {
    maker: address,
    tradable_asset: TradableAsset,
    amount: u64,
}

/// Emitted when maker withdraws collateral
public struct CollateralWithdrawn has copy, drop {
    maker: address,
    tradable_asset: TradableAsset,
    amount: u64,
}

/// Emitted when maker stakes more Ithaca tokens
public struct IthacaStaked has copy, drop {
    maker: address,
    amount: u64,
}

/// Emitted when minimum stake amount is set
public struct MinimumStakeAmountSet has copy, drop {
    amount: u64,
}

/// Emitted when custom minimum stake amount is set
public struct CustomMinStakeAmountSet has copy, drop {
    tradable_asset: TradableAsset,
    amount: u64,
}

/// Emitted when order module is updated
public struct OrderModuleSet has copy, drop {
    old_order_module: address,
    new_order_module: address,
}

// === Public Functions ===

/// Initialize a new maker vault
/// Returns admin capability and order capability
public fun initialize<CollateralType, IthacaType>(
    minimum_stake_amount: u64,
    ctx: &mut TxContext
): (MakerVaultAdminCap, MakerOrderCap, MakerVault<CollateralType, IthacaType>) {
    assert!(minimum_stake_amount > 0, ENotZeroAmount);

    let admin_cap = MakerVaultAdminCap {
        id: object::new(ctx),
    };
    
    let order_cap = MakerOrderCap {
        id: object::new(ctx),
    };

    let vault = MakerVault<CollateralType, IthacaType> {
        id: object::new(ctx),
        total_asset_available: 0,
        makers: table::new(ctx),
        minimum_stake_amount,
        custom_min_stake_amounts: table::new(ctx),
        collateral_balance: balance::zero<CollateralType>(),
        ithaca_balance: balance::zero<IthacaType>(),
        order_module: @0x0, // Will be set later
    };

    (admin_cap, order_cap, vault)
}

/// Register as a maker by staking Ithaca tokens
public fun register_maker<CollateralType, IthacaType>(
    vault: &mut MakerVault<CollateralType, IthacaType>,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    let stake_amount = coin::value(&ithaca_payment);
    
    assert!(stake_amount > 0, ENotZeroAmount);
    assert!(!table::contains(&vault.makers, sender), EMakerAlreadyRegistered);
    assert!(stake_amount >= vault.minimum_stake_amount, EInsufficientStake);

    // Create maker info
    let maker_info = types::new_maker_info(stake_amount);
    table::add(&mut vault.makers, sender, maker_info);

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
public fun unregister_maker<CollateralType, IthacaType>(
    vault: &mut MakerVault<CollateralType, IthacaType>,
    ctx: &mut TxContext
): Coin<IthacaType> {
    let sender = tx_context::sender(ctx);
    
    assert!(table::contains(&vault.makers, sender), EMakerNotAvailable);
    
    let maker_info = table::remove(&mut vault.makers, sender);
    
    // Check that all collateral is zero
    assert!(types::maker_info_collateral(&maker_info, &types::tradable_asset_btc()) == 0, ECollateralMustBeZero);
    assert!(types::maker_info_collateral(&maker_info, &types::tradable_asset_eth()) == 0, ECollateralMustBeZero);
    assert!(types::maker_info_collateral(&maker_info, &types::tradable_asset_sol()) == 0, ECollateralMustBeZero);
    assert!(types::maker_info_collateral(&maker_info, &types::tradable_asset_xau()) == 0, ECollateralMustBeZero);
    assert!(types::maker_info_collateral(&maker_info, &types::tradable_asset_mstr()) == 0, ECollateralMustBeZero);

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
public fun deposit_collateral<CollateralType, IthacaType>(
    vault: &mut MakerVault<CollateralType, IthacaType>,
    tradable_asset: TradableAsset,
    payment: Coin<CollateralType>,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    let amount = coin::value(&payment);
    
    assert!(amount > 0, ENotZeroAmount);
    assert!(table::contains(&vault.makers, sender), EMakerNotAvailable);

    // Check minimum stake requirement for this asset (do this before mutable borrow)
    let min_stake = get_min_stake_amount(vault, &tradable_asset);
    
    let maker_info = table::borrow_mut(&mut vault.makers, sender);
    let staked_tokens = types::maker_info_staked_tokens(maker_info);
    assert!(staked_tokens >= min_stake, EInsufficientStake);

    // Update collateral
    types::add_maker_collateral(maker_info, &tradable_asset, amount);
    vault.total_asset_available = vault.total_asset_available + amount;

    // Add payment to vault balance
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.collateral_balance, payment_balance);

    // Emit event
    event::emit(CollateralDeposited {
        maker: sender,
        tradable_asset,
        amount,
    });
}

/// Withdraw collateral for a specific tradable asset
public fun withdraw_collateral<CollateralType, IthacaType>(
    vault: &mut MakerVault<CollateralType, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
    ctx: &mut TxContext
): Coin<CollateralType> {
    let sender = tx_context::sender(ctx);
    
    assert!(amount > 0, ENotZeroAmount);
    assert!(table::contains(&vault.makers, sender), EMakerNotAvailable);

    let withdrawable_balance = get_withdrawable_balance(vault, sender, &tradable_asset);
    assert!(amount <= withdrawable_balance, EInsufficientCollateral);

    let maker_info = table::borrow_mut(&mut vault.makers, sender);
    
    // Update collateral
    types::subtract_maker_collateral(maker_info, &tradable_asset, amount);
    vault.total_asset_available = vault.total_asset_available - amount;

    // Extract coin from vault balance
    let withdrawn_balance = balance::split(&mut vault.collateral_balance, amount);
    let withdrawn_coin = coin::from_balance(withdrawn_balance, ctx);

    // Emit event
    event::emit(CollateralWithdrawn {
        maker: sender,
        tradable_asset,
        amount,
    });

    withdrawn_coin
}

/// Stake additional Ithaca tokens
public fun stake_ithaca<CollateralType, IthacaType>(
    vault: &mut MakerVault<CollateralType, IthacaType>,
    ithaca_payment: Coin<IthacaType>,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    let amount = coin::value(&ithaca_payment);
    
    assert!(amount > 0, ENotZeroAmount);
    assert!(table::contains(&vault.makers, sender), EMakerNotAvailable);

    let maker_info = table::borrow_mut(&mut vault.makers, sender);
    types::add_staked_tokens(maker_info, amount);

    // Add Ithaca tokens to vault balance
    let ithaca_balance = coin::into_balance(ithaca_payment);
    balance::join(&mut vault.ithaca_balance, ithaca_balance);

    // Emit event
    event::emit(IthacaStaked {
        maker: sender,
        amount,
    });
}

/// Set the order module address (admin only)
public fun set_order_module<CollateralType, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    new_order_module: address,
) {
    assert!(new_order_module != @0x0, ENotZeroAddress);
    let old_order_module = vault.order_module;
    vault.order_module = new_order_module;

    event::emit(OrderModuleSet {
        old_order_module,
        new_order_module,
    });
}

/// Set minimum stake amount (admin only)
public fun set_minimum_stake_amount<CollateralType, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    amount: u64,
) {
    assert!(amount > 0, ENotZeroAmount);
    vault.minimum_stake_amount = amount;

    event::emit(MinimumStakeAmountSet {
        amount,
    });
}

/// Set custom minimum stake amount for specific asset (admin only)
public fun set_custom_min_stake_amount<CollateralType, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
) {
    if (table::contains(&vault.custom_min_stake_amounts, tradable_asset)) {
        table::remove(&mut vault.custom_min_stake_amounts, tradable_asset);
    };
    
    if (amount > 0) {
        table::add(&mut vault.custom_min_stake_amounts, tradable_asset, amount);
    };

    event::emit(CustomMinStakeAmountSet {
        tradable_asset,
        amount,
    });
}

// === Order Module Functions (restricted) ===

/// Transfer collateral to taker vault (order module only)
public fun transfer_to_taker_vault<CollateralType, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    amount: u64,
    ctx: &mut TxContext
): Coin<CollateralType> {
    let transfer_balance = balance::split(&mut vault.collateral_balance, amount);
    coin::from_balance(transfer_balance, ctx)
}

/// Adjust maker balance (order module only)
public fun adjust_maker_balance<CollateralType, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    maker: address,
    tradable_asset: TradableAsset,
    amount: u64,
    is_win: bool,
) {
    assert!(table::contains(&vault.makers, maker), EMakerNotAvailable);
    
    let maker_info = table::borrow_mut(&mut vault.makers, maker);
    
    if (is_win) {
        // Increase maker collateral
        types::add_maker_collateral(maker_info, &tradable_asset, amount);
        vault.total_asset_available = vault.total_asset_available + amount;
    } else {
        // Decrease maker collateral
        types::subtract_maker_collateral(maker_info, &tradable_asset, amount);
        vault.total_asset_available = vault.total_asset_available - amount;
    }
}

/// Transfer fee to treasury (order module only)
public fun transfer_fee_to_treasury<CollateralType, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    maker: address,
    tradable_asset: TradableAsset,
    fee: u64,
    ctx: &mut TxContext
): Coin<CollateralType> {
    assert!(table::contains(&vault.makers, maker), EMakerNotAvailable);
    
    // Reduce maker collateral
    let maker_info = table::borrow_mut(&mut vault.makers, maker);
    types::subtract_maker_collateral(maker_info, &tradable_asset, fee);
    vault.total_asset_available = vault.total_asset_available - fee;

    // Extract fee from vault balance
    let fee_balance = balance::split(&mut vault.collateral_balance, fee);
    coin::from_balance(fee_balance, ctx)
}

/// Add funds to vault from outside (order module only)
/// Used when funds are transferred from taker vault to maker vault
public fun add_funds<CollateralType, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<CollateralType, IthacaType>,
    payment: Coin<CollateralType>,
) {
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.collateral_balance, payment_balance);
    // Note: total_asset_available is updated via adjust_maker_balance
}

// === View Functions ===

/// Get maker info
public fun get_maker_info<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>, 
    maker: address
): u64 {
    if (table::contains(&vault.makers, maker)) {
        let maker_info = table::borrow(&vault.makers, maker);
        types::maker_info_staked_tokens(maker_info)
    } else {
        0
    }
}

/// Get maker collateral for specific asset
public fun get_maker_collateral<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>, 
    maker: address, 
    tradable_asset: &TradableAsset
): u64 {
    if (table::contains(&vault.makers, maker)) {
        let maker_info = table::borrow(&vault.makers, maker);
        types::maker_info_collateral(maker_info, tradable_asset)
    } else {
        0
    }
}

/// Get withdrawable balance for a maker considering locked amounts
public fun get_withdrawable_balance<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>, 
    maker: address, 
    tradable_asset: &TradableAsset
): u64 {
    // For now, return the full collateral
    // In full implementation, this would subtract locked amounts from orders
    get_maker_collateral(vault, maker, tradable_asset)
}

/// Get withdrawable balance considering locked amounts in orders
public fun get_withdrawable_balance_with_locked<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>, 
    maker: address, 
    tradable_asset: &TradableAsset,
    locked_amount: u64
): u64 {
    let total_collateral = get_maker_collateral(vault, maker, tradable_asset);
    if (total_collateral >= locked_amount) {
        total_collateral - locked_amount
    } else {
        0
    }
}

/// Get minimum stake amount for a tradable asset
public fun get_min_stake_amount<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>, 
    tradable_asset: &TradableAsset
): u64 {
    if (table::contains(&vault.custom_min_stake_amounts, *tradable_asset)) {
        *table::borrow(&vault.custom_min_stake_amounts, *tradable_asset)
    } else {
        vault.minimum_stake_amount
    }
}

/// Get total asset available
public fun total_asset_available<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>
): u64 {
    vault.total_asset_available
}

/// Get vault collateral balance value
public fun vault_collateral_balance_value<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>
): u64 {
    balance::value(&vault.collateral_balance)
}

/// Get vault Ithaca balance value
public fun vault_ithaca_balance_value<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>
): u64 {
    balance::value(&vault.ithaca_balance)
}

/// Get order module address
public fun order_module<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>
): address {
    vault.order_module
}

/// Get minimum stake amount
public fun minimum_stake_amount<CollateralType, IthacaType>(
    vault: &MakerVault<CollateralType, IthacaType>
): u64 {
    vault.minimum_stake_amount
}
 