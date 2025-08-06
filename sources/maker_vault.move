/// Maker Vault module for managing maker liquidity, staking, and collateral
module trading_vault::maker_vault;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::event;
use trading_vault::types::{Self, TradableAsset, MakerInfo};

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
    /// Mapping of maker address to their info
    makers: Table<address, MakerInfo>,
    /// Minimum stake amount required to become a maker
    minimum_stake_amount: u64,
    /// Custom minimum stake amounts for specific assets
    custom_min_stake_amounts: Table<TradableAsset, u64>,
    /// The actual collateral coin balance held by the vault
    collateral_balance: Balance<T>,
    /// The Ithaca token balance held by the vault for staking
    ithaca_balance: Balance<IthacaType>,
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

// === Public Functions ===

/// Initialize a new maker vault
/// Returns admin capability and order capability
public fun initialize<T, IthacaType>(
    minimum_stake_amount: u64,
    ctx: &mut TxContext
): (MakerVaultAdminCap, MakerOrderCap, MakerVault<T, IthacaType>) {
    assert!(minimum_stake_amount > 0, ENotZeroAmount);

    let admin_cap = MakerVaultAdminCap {
        id: object::new(ctx),
    };
    
    let order_cap = MakerOrderCap {
        id: object::new(ctx),
    };

    let vault = MakerVault<T, IthacaType> {
        id: object::new(ctx),
        makers: table::new(ctx),
        minimum_stake_amount,
        custom_min_stake_amounts: table::new(ctx),
        collateral_balance: balance::zero<T>(),
        ithaca_balance: balance::zero<IthacaType>(),
    };

    (admin_cap, order_cap, vault)
}

/// Register as a maker by staking Ithaca tokens
public fun register_maker<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
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
public fun unregister_maker<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
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
public fun deposit_collateral<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    tradable_asset: TradableAsset,
    payment: Coin<T>,
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
public fun withdraw_collateral<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    let sender = tx_context::sender(ctx);
    
    assert!(amount > 0, ENotZeroAmount);
    assert!(table::contains(&vault.makers, sender), EMakerNotAvailable);

    let withdrawable_balance = get_withdrawable_balance(vault, sender, &tradable_asset);
    assert!(amount <= withdrawable_balance, EInsufficientCollateral);

    let maker_info = table::borrow_mut(&mut vault.makers, sender);
    
    // Update collateral
    types::subtract_maker_collateral(maker_info, &tradable_asset, amount);

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
public fun stake_ithaca<T, IthacaType>(
    vault: &mut MakerVault<T, IthacaType>,
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

/// Set minimum stake amount (admin only)
public fun set_minimum_stake_amount<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
    amount: u64,
) {
    assert!(amount > 0, ENotZeroAmount);
    vault.minimum_stake_amount = amount;

    event::emit(MinimumStakeAmountSet {
        amount,
    });
}

/// Set custom minimum stake amount for specific asset (admin only)
public fun set_custom_min_stake_amount<T, IthacaType>(
    _: &MakerVaultAdminCap,
    vault: &mut MakerVault<T, IthacaType>,
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
public fun transfer_to_taker_vault<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    let transfer_balance = balance::split(&mut vault.collateral_balance, amount);
    coin::from_balance(transfer_balance, ctx)
}

/// Adjust maker balance (order module only)
public fun adjust_maker_balance<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
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
    } else {
        // Decrease maker collateral
        types::subtract_maker_collateral(maker_info, &tradable_asset, amount);
    }
}

/// Transfer fee to treasury (order module only)
public fun transfer_fee_to_treasury<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    maker: address,
    tradable_asset: TradableAsset,
    fee: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(table::contains(&vault.makers, maker), EMakerNotAvailable);
    
    // Reduce maker collateral
    let maker_info = table::borrow_mut(&mut vault.makers, maker);
    types::subtract_maker_collateral(maker_info, &tradable_asset, fee);

    // Extract fee from vault balance
    let fee_balance = balance::split(&mut vault.collateral_balance, fee);
    coin::from_balance(fee_balance, ctx)
}

/// Add funds to vault from outside (order module only)
/// Used when funds are transferred from taker vault to maker vault
public fun add_funds<T, IthacaType>(
    _: &MakerOrderCap,
    vault: &mut MakerVault<T, IthacaType>,
    payment: Coin<T>,
) {
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.collateral_balance, payment_balance);
    // Note: collateral balance is automatically updated via balance::join
}

// === View Functions ===

/// Get maker info
public fun get_maker_info<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
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
public fun get_maker_collateral<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
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
public fun get_withdrawable_balance<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
    maker: address, 
    tradable_asset: &TradableAsset
): u64 {
    // For now, return the full collateral
    // In full implementation, this would subtract locked amounts from orders
    get_maker_collateral(vault, maker, tradable_asset)
}

/// Get withdrawable balance considering locked amounts in orders
public fun get_withdrawable_balance_with_locked<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
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
public fun get_min_stake_amount<T, IthacaType>(
    vault: &MakerVault<T, IthacaType>, 
    tradable_asset: &TradableAsset
): u64 {
    if (table::contains(&vault.custom_min_stake_amounts, *tradable_asset)) {
        *table::borrow(&vault.custom_min_stake_amounts, *tradable_asset)
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

/// Get vault collateral balance value
public fun vault_collateral_balance_value<T, IthacaType>(
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
 