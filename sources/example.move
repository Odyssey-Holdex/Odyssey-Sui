/// Example module demonstrating usage of the trading vault system
/// This shows how to initialize vaults, create orders, and manage deposits/withdrawals
module trading_vault::example {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use std::vector;
    use trading_vault::vault::{Self, Vault, VaultAdminCap};
    use trading_vault::maker_vault::{Self, MakerVault, MakerVaultAdminCap};
    use trading_vault::order::{Self, OrderManager, OrderAdminCap};
    use trading_vault::types::{Self, TradableAsset};

    /// Example initialization function
    /// This demonstrates how to set up a complete trading system
    public fun initialize_trading_system<CollateralType, IthacaType>(
        minimum_stake: u64,
        coordinator: address,
        treasury: address,
        ctx: &mut TxContext
    ): (
        VaultAdminCap,
        MakerVaultAdminCap,
        OrderAdminCap, 
        Vault<CollateralType>,
        MakerVault<CollateralType, IthacaType>,
        OrderManager<CollateralType>
    ) {
        // Initialize vault
        let (vault_admin_cap, vault_order_cap, vault) = vault::initialize<CollateralType>(ctx);
        
        // Initialize maker vault
        let (maker_vault_admin_cap, maker_order_cap, maker_vault) = maker_vault::initialize<CollateralType, IthacaType>(minimum_stake, ctx);
        
        // Initialize order manager
        let (order_admin_cap, order_manager) = order::initialize<CollateralType>(
            vault_order_cap, 
            maker_order_cap, 
            coordinator, 
            treasury, 
            ctx
        );
        
        (vault_admin_cap, maker_vault_admin_cap, order_admin_cap, vault, maker_vault, order_manager)
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
        vault: &mut Vault<T>,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<T> {
        vault::withdraw(vault, amount, ctx)
    }

    /// Example maker registration
    public fun example_register_maker<CollateralType, IthacaType>(
        maker_vault: &mut MakerVault<CollateralType, IthacaType>,
        ithaca_payment: Coin<IthacaType>,
        ctx: &mut TxContext
    ) {
        maker_vault::register_maker(maker_vault, ithaca_payment, ctx);
    }

    /// Example collateral deposit
    public fun example_deposit_collateral<CollateralType, IthacaType>(
        maker_vault: &mut MakerVault<CollateralType, IthacaType>,
        tradable_asset: TradableAsset,
        payment: Coin<CollateralType>,
        ctx: &mut TxContext
    ) {
        maker_vault::deposit_collateral(maker_vault, tradable_asset, payment, ctx);
    }

    /// Example note creation (coordinator only)
    public fun example_create_note<CollateralType, IthacaType>(
        order_manager: &mut OrderManager<CollateralType>,
        vault: &mut Vault<CollateralType>,
        maker_vault: &mut MakerVault<CollateralType, IthacaType>,
        taker: address,
        maker: address,
        amount: u64,
        starting_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): u64 {
        // Create note
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
        );

        // Create additional info
        let additional_info = types::new_note_additional_info(
            500, // almost_win_spread: $5
            amount + (amount / 2), // almost_win_payout: 1.5x
            sui::clock::timestamp_ms(clock), // start_time
            vector::empty<u8>(), // empty report
        );

        order::create_note(order_manager, vault, maker_vault, note, additional_info, clock, ctx)
    }

    /// Example note settlement (coordinator only)
    public fun example_settle_note<CollateralType, IthacaType>(
        order_manager: &mut OrderManager<CollateralType>,
        vault: &mut Vault<CollateralType>,
        maker_vault: &mut MakerVault<CollateralType, IthacaType>,
        note_id: u64,
        final_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        order::settle_note(
            order_manager, 
            vault, 
            maker_vault, 
            note_id, 
            final_price, 
            vector::empty<u8>(), // empty report
            clock, 
            ctx
        );
    }

    // === View functions for checking state ===

    public fun check_taker_balance<T>(vault: &Vault<T>, taker: address): u64 {
        vault::taker_balance(vault, taker)
    }

    public fun check_locked_balance<CollateralType>(order_manager: &OrderManager<CollateralType>, taker: address): u64 {
        order::taker_locked_balance(order_manager, taker)
    }

    public fun check_withdrawable_balance<T>(vault: &Vault<T>, taker: address): u64 {
        vault::get_withdrawable_balance(vault, taker)
    }

    public fun check_maker_collateral<CollateralType, IthacaType>(
        maker_vault: &MakerVault<CollateralType, IthacaType>, 
        maker: address, 
        asset: &TradableAsset
    ): u64 {
        maker_vault::get_maker_collateral(maker_vault, maker, asset)
    }
} 