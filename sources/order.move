/// Order module for managing trading notes, orders, and settlements
module trading_vault::order;

use sui::table::{Self, Table};
use sui::event;
use sui::clock::{Self, Clock};
use sui::coin::{Coin};
use trading_vault::types::{Self, Note, NoteAdditionalInfo, NoteStatus, TradableAsset, Actor, SettlementInfo, FeeInfo};
use trading_vault::vault::{Self, OrderCap};
use trading_vault::maker_vault::{Self, MakerOrderCap};

// === Errors ===

#[error]
const EInvalidNote: vector<u8> = b"Invalid note data provided";

#[error]
const ENoteNotFound: vector<u8> = b"Note with given ID does not exist";

#[error]
const ENoteAlreadySettled: vector<u8> = b"Note has already been settled";

#[error]
const ENoteNotExpired: vector<u8> = b"Note has not yet expired and cannot be settled";

#[error]
const EOnlyByCoordinator: vector<u8> = b"Only coordinator can perform this action";

#[error]
const EInsufficientTakerBalance: vector<u8> = b"Taker has insufficient balance for this note";

#[error]
const EInsufficientMakerBalance: vector<u8> = b"Maker has insufficient balance for this note";

#[error]
const EInvalidExpiryTime: vector<u8> = b"Expiry time must be in the future";

#[error]
const EInvalidPayout: vector<u8> = b"Invalid payout amount specified";

#[error]
const EInvalidFeePercentage: vector<u8> = b"Fee percentage exceeds maximum allowed";

#[error]
const EInvalidSpread: vector<u8> = b"Invalid spread value provided";

#[error]
const ENotSameAddress: vector<u8> = b"Address is already set to this value";

// === Structs ===

/// Administrative capability for order operations
public struct OrderAdminCap has key, store {
    id: UID,
}

/// Order manager that tracks all trading notes and locked balances
public struct OrderManager<phantom T> has key {
    id: UID,
    /// Counter for generating unique note IDs
    note_counter: u64,
    /// Mapping of note ID to note data
    notes: Table<u64, StoredNote>,
    /// Mapping of note ID to settlement info
    settlement_infos: Table<u64, SettlementInfo>,
    /// Mapping of taker address to their locked balance
    taker_locked_balances: Table<address, u64>,
    /// Mapping of maker and asset to locked balance
    maker_locked_balances: Table<MakerAssetKey, u64>,
    /// Mapping of note ID to settled status
    is_note_settled: Table<u64, bool>,
    /// Order capability for interacting with vaults
    vault_order_cap: OrderCap,
    /// Maker order capability for interacting with maker vault
    maker_order_cap: MakerOrderCap,
    /// Coordinator address
    coordinator: address,
    /// Treasury address
    treasury: address,
    /// Fee information
    fee_info: FeeInfo,
}

/// Internal storage structure for notes
public struct StoredNote has store {
    note: Note,
    additional_info: NoteAdditionalInfo,
    created_at: u64,
}

/// Key for maker locked balances (maker address + asset)
public struct MakerAssetKey has copy, drop, store {
    maker: address,
    asset: TradableAsset,
}

// === Events ===

/// Emitted when a new note is created
public struct NoteCreated has copy, drop {
    note_id: u64,
    taker: address,
    maker: address,
    asset: TradableAsset,
    amount: u64,
    expiry_time: u64,
}

/// Emitted when a note is settled
public struct NoteSettled has copy, drop {
    note_id: u64,
    status: NoteStatus,
    settlement_price: u64,
    payout: u64,
    fee: u64,
}

/// Emitted when coordinator is changed
public struct CoordinatorChanged has copy, drop {
    new_coordinator: address,
}

/// Emitted when fee percentages are changed
public struct TakerFeePercentageChanged has copy, drop {
    taker_fee_percentage: u64,
}

public struct MakerFeePercentageChanged has copy, drop {
    maker_fee_percentage: u64,
}

// === Public Functions ===

/// Initialize the order manager
public fun initialize<T>(
    vault_order_cap: OrderCap,
    maker_order_cap: MakerOrderCap,
    coordinator: address,
    treasury: address,
    ctx: &mut TxContext
): (OrderAdminCap, OrderManager<T>) {
    let admin_cap = OrderAdminCap {
        id: object::new(ctx),
    };

    let fee_info = types::new_fee_info(0, 0); // Default 0% fees

    let order_manager = OrderManager<T> {
        id: object::new(ctx),
        note_counter: 0,
        notes: table::new(ctx),
        settlement_infos: table::new(ctx),
        taker_locked_balances: table::new(ctx),
        maker_locked_balances: table::new(ctx),
        is_note_settled: table::new(ctx),
        vault_order_cap,
        maker_order_cap,
        coordinator,
        treasury,
        fee_info,
    };

    (admin_cap, order_manager)
}

/// Create a new trading note (coordinator only)
public fun create_note<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note: Note,
    additional_info: NoteAdditionalInfo,
    clock: &Clock,
    ctx: &mut TxContext
): u64 {
    let sender = tx_context::sender(ctx);
    
    // Only coordinator can create notes
    assert!(sender == order_manager.coordinator, EOnlyByCoordinator);
    
    // Validate note data
    let amount = types::note_amount(&note);
    let win_payout = types::note_win_payout(&note);
    let refund_payout = types::note_refund_payout(&note);
    let expiry_time = types::note_expiry_time(&note);
    let taker = types::note_taker(&note);
    let maker = types::note_maker(&note);
    let asset = types::note_asset(&note);
    let spread = types::note_spread(&note);

    assert!(amount > 0, EInvalidNote);
    assert!(taker != @0x0, EInvalidNote);
    assert!(maker != @0x0, EInvalidNote);
    assert!(expiry_time > clock::timestamp_ms(clock), EInvalidExpiryTime);
    
    // Validate payouts
    assert!(win_payout > amount, EInvalidPayout);
    assert!(refund_payout <= amount, EInvalidPayout);
    let almost_win_payout = types::note_additional_info_almost_win_payout(&additional_info);
    let almost_win_spread = types::note_additional_info_almost_win_spread(&additional_info);
    let start_time = types::note_additional_info_start_time(&additional_info);
    assert!(almost_win_payout > 0 && almost_win_payout <= win_payout, EInvalidPayout);
    assert!(almost_win_spread <= spread, EInvalidSpread);
    assert!(start_time <= expiry_time, EInvalidExpiryTime);

    // Check balances
    let taker_balance = vault::taker_balance(vault, taker) - taker_locked_balance(order_manager, taker);
    let win_amount = win_payout - amount;
    let maker_balance = maker_vault::get_maker_collateral(maker_vault, maker, asset) - 
                        maker_locked_balance(order_manager, maker, *asset);

    assert!(taker_balance >= amount, EInsufficientTakerBalance);
    assert!(maker_balance >= win_amount, EInsufficientMakerBalance);

    // Generate note ID
    let note_id = order_manager.note_counter;
    order_manager.note_counter = order_manager.note_counter + 1;

    // Store note
    let stored_note = StoredNote {
        note: copy note,
        additional_info,
        created_at: clock::timestamp_ms(clock),
    };
    
    table::add(&mut order_manager.notes, note_id, stored_note);
    table::add(&mut order_manager.is_note_settled, note_id, false);

    // Lock balances
    update_taker_locked_balance(order_manager, taker, amount, true);
    update_maker_locked_balance(order_manager, maker, *asset, win_amount, true);

    // Emit event
    event::emit(NoteCreated {
        note_id,
        taker,
        maker,
        asset: *asset,
        amount,
        expiry_time,
    });

    note_id
}

/// Settle a note with the final spot price (coordinator only)
public fun settle_note<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note_id: u64,
    spot_price: u64,
    report: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = tx_context::sender(ctx);
    assert!(sender == order_manager.coordinator, EOnlyByCoordinator);
    assert!(table::contains(&order_manager.notes, note_id), ENoteNotFound);
    
    let is_settled = *table::borrow(&order_manager.is_note_settled, note_id);
    assert!(!is_settled, ENoteAlreadySettled);
    
    let stored_note = table::borrow(&order_manager.notes, note_id);
    let note_copy = stored_note.note; // Copy the entire note
    let additional_info_copy = stored_note.additional_info; // Copy additional info
    
    // Check if note has expired
    assert!(clock::timestamp_ms(clock) >= types::note_expiry_time(&note_copy), ENoteNotExpired);

    // Determine outcome
    let (status, payout, fee) = determine_settlement_outcome(
        &note_copy, // Pass reference to the copied note
        &additional_info_copy, // Pass reference to the copied additional info
        spot_price,
        &order_manager.fee_info
    );

    // Mark as settled
    table::remove(&mut order_manager.is_note_settled, note_id);
    table::add(&mut order_manager.is_note_settled, note_id, true);

    // Store settlement info
    let settlement_info = types::new_settlement_info(spot_price, clock::timestamp_ms(clock), report);
    table::add(&mut order_manager.settlement_infos, note_id, settlement_info);

    // Process settlement
    process_settlement(
        order_manager,
        vault,
        maker_vault,
        &note_copy, // Pass reference to the copied note
        status,
        payout,
        fee,
        ctx
    );

    // Emit event
    event::emit(NoteSettled {
        note_id,
        status,
        settlement_price: spot_price,
        payout,
        fee,
    });
}

/// Change coordinator (admin only)
public fun change_coordinator<T>(
    _: &OrderAdminCap,
    order_manager: &mut OrderManager<T>,
    new_coordinator: address,
) {
    assert!(new_coordinator != @0x0, EInvalidNote);
    assert!(new_coordinator != order_manager.coordinator, ENotSameAddress);
    order_manager.coordinator = new_coordinator;

    event::emit(CoordinatorChanged {
        new_coordinator,
    });
}

/// Set taker fee percentage (admin only)
public fun set_taker_fee_percentage<T>(
    _: &OrderAdminCap,
    order_manager: &mut OrderManager<T>,
    taker_fee_percentage: u64,
) {
    assert!(taker_fee_percentage <= types::max_fee_percentage(), EInvalidFeePercentage);
    order_manager.fee_info = types::new_fee_info(
        taker_fee_percentage,
        types::fee_info_maker_percentage(&order_manager.fee_info)
    );

    event::emit(TakerFeePercentageChanged {
        taker_fee_percentage,
    });
}

/// Set maker fee percentage (admin only)
public fun set_maker_fee_percentage<T>(
    _: &OrderAdminCap,
    order_manager: &mut OrderManager<T>,
    maker_fee_percentage: u64,
) {
    assert!(maker_fee_percentage <= types::max_fee_percentage(), EInvalidFeePercentage);
    order_manager.fee_info = types::new_fee_info(
        types::fee_info_taker_percentage(&order_manager.fee_info),
        maker_fee_percentage
    );

    event::emit(MakerFeePercentageChanged {
        maker_fee_percentage,
    });
}

public fun taker_withdraw<T>(
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    let locked_amount = taker_locked_balance(order_manager, tx_context::sender(ctx));
    vault::withdraw(&order_manager.vault_order_cap, vault, amount, locked_amount, ctx)
}

public fun maker_withdraw<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    let sender = tx_context::sender(ctx);
    let locked_amount = maker_locked_balance(order_manager, sender, tradable_asset);
    maker_vault::withdraw_collateral(&order_manager.maker_order_cap, maker_vault, sender, tradable_asset, locked_amount, amount, ctx)
}

// === View Functions ===

/// Get taker locked balance
public fun taker_locked_balance<T>(order_manager: &OrderManager<T>, taker: address): u64 {
    if (table::contains(&order_manager.taker_locked_balances, taker)) {
        *table::borrow(&order_manager.taker_locked_balances, taker)
    } else {
        0
    }
}

public fun taker_withdrawable_balance<T>(
    order_manager: &OrderManager<T>,
    vault: &vault::Vault<T>,
    taker: address
): u64 {
    let locked_amount = taker_locked_balance(order_manager, taker);
    vault::get_withdrawable_balance_with_locked(&order_manager.vault_order_cap, vault, taker, locked_amount)
}

public fun maker_withdrawable_balance<T, IthacaType>(
    order_manager: &OrderManager<T>,
    maker_vault: &maker_vault::MakerVault<T, IthacaType>,
    maker: address,
    tradable_asset: TradableAsset
): u64 {
    let locked_amount = maker_locked_balance(order_manager, maker, tradable_asset);
    maker_vault::get_withdrawable_balance_with_locked(&order_manager.maker_order_cap, maker_vault, maker, &tradable_asset, locked_amount)
}

/// Get maker locked balance for specific asset
public fun maker_locked_balance<T>(
    order_manager: &OrderManager<T>, 
    maker: address, 
    asset: TradableAsset
): u64 {
    let key = MakerAssetKey { maker, asset };
    if (table::contains(&order_manager.maker_locked_balances, key)) {
        *table::borrow(&order_manager.maker_locked_balances, key)
    } else {
        0
    }
}

/// Get note by ID
public fun get_note<T>(order_manager: &OrderManager<T>, note_id: u64): &Note {
    assert!(table::contains(&order_manager.notes, note_id), ENoteNotFound);
    let stored_note = table::borrow(&order_manager.notes, note_id);
    &stored_note.note
}

/// Check if note is settled
public fun is_note_settled<T>(order_manager: &OrderManager<T>, note_id: u64): bool {
    if (table::contains(&order_manager.is_note_settled, note_id)) {
        *table::borrow(&order_manager.is_note_settled, note_id)
    } else {
        false
    }
}

/// Get note counter
public fun note_counter<T>(order_manager: &OrderManager<T>): u64 {
    order_manager.note_counter
}

/// Get coordinator
public fun coordinator<T>(order_manager: &OrderManager<T>): address {
    order_manager.coordinator
}

/// Get treasury
public fun treasury<T>(order_manager: &OrderManager<T>): address {
    order_manager.treasury
}

// === Helper Functions ===

/// Update taker locked balance
fun update_taker_locked_balance<T>(
    order_manager: &mut OrderManager<T>,
    taker: address,
    amount: u64,
    is_lock: bool,
) {
    let current_locked = if (table::contains(&order_manager.taker_locked_balances, taker)) {
        table::remove(&mut order_manager.taker_locked_balances, taker)
    } else {
        0
    };

    let new_locked = if (is_lock) {
        current_locked + amount
    } else {
        if (current_locked >= amount) current_locked - amount else 0
    };

    if (new_locked > 0) {
        table::add(&mut order_manager.taker_locked_balances, taker, new_locked);
    };
}

/// Update maker locked balance
fun update_maker_locked_balance<T>(
    order_manager: &mut OrderManager<T>,
    maker: address,
    asset: TradableAsset,
    amount: u64,
    is_lock: bool,
) {
    let key = MakerAssetKey { maker, asset };
    let current_locked = if (table::contains(&order_manager.maker_locked_balances, key)) {
        table::remove(&mut order_manager.maker_locked_balances, key)
    } else {
        0
    };

    let new_locked = if (is_lock) {
        current_locked + amount
    } else {
        if (current_locked >= amount) current_locked - amount else 0
    };

    if (new_locked > 0) {
        table::add(&mut order_manager.maker_locked_balances, key, new_locked);
    };
}

/// Determine settlement outcome based on note parameters and spot price
fun determine_settlement_outcome(
    note: &Note,
    additional_info: &NoteAdditionalInfo,
    spot_price: u64,
    fee_info: &FeeInfo,
): (NoteStatus, u64, u64) {
    let starting_price = types::note_starting_price(note);
    let spread = types::note_spread(note);
    let direction = types::note_direction(note);
    let amount = types::note_amount(note);
    let win_payout = types::note_win_payout(note);
    let refund_payout = types::note_refund_payout(note);
    let almost_win_spread = types::note_additional_info_almost_win_spread(additional_info);
    let almost_win_payout = types::note_additional_info_almost_win_payout(additional_info);

    let (status, payout) = if (types::is_direction_up(&direction)) {
        if (spot_price > starting_price + spread) {
            (types::note_status_win(), win_payout)
        } else if (spot_price > starting_price + almost_win_spread) {
            (types::note_status_almost_win(), almost_win_payout)
        } else if (spot_price > starting_price) {
            (types::note_status_loss(), amount)
        } else {
            (types::note_status_refund(), refund_payout)
        }
    } else { // Direction::DOWN
        if (spot_price < starting_price - spread) {
            (types::note_status_win(), win_payout)
        } else if (spot_price < starting_price - almost_win_spread) {
            (types::note_status_almost_win(), almost_win_payout)
        } else if (spot_price < starting_price) {
            (types::note_status_loss(), amount)
        } else {
            (types::note_status_refund(), refund_payout)
        }
    };

    // Calculate fee
    let fee = if (types::is_note_status_win(&status)) {
        let transferred_amount = win_payout - amount;
        calculate_fee(transferred_amount, types::actor_taker(), fee_info)
    } else if (types::is_note_status_loss(&status)) {
        calculate_fee(amount, types::actor_maker(), fee_info)
    } else if (types::is_note_status_almost_win(&status)) {
        if (almost_win_payout > amount) {
            let transferred_amount = almost_win_payout - amount;
            calculate_fee(transferred_amount, types::actor_taker(), fee_info)
        } else {
            let transferred_amount = amount - almost_win_payout;
            calculate_fee(transferred_amount, types::actor_maker(), fee_info)
        }
    } else {
        0 // No fee for refunds
    };

    (status, payout, fee)
}

/// Process the settlement by transferring funds and fees
fun process_settlement<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note: &Note,
    status: NoteStatus,
    payout: u64,
    fee: u64,
    ctx: &mut TxContext
) {
    let taker = types::note_taker(note);
    let maker = types::note_maker(note);
    let asset = *types::note_asset(note);
    let amount = types::note_amount(note);
    let win_payout = types::note_win_payout(note);
    let win_amount = win_payout - amount;

    // Release locked balances
    update_taker_locked_balance(order_manager, taker, amount, false);
    update_maker_locked_balance(order_manager, maker, asset, win_amount, false);

    if (types::is_note_status_win(&status)) {
        // Taker wins
        let transferred_amount = payout - amount;
        
        // Transfer from maker to taker
        vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, transferred_amount, true);
        maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, transferred_amount, false);
        
        let maker_payment = maker_vault::transfer_to_taker_vault(&order_manager.maker_order_cap, maker_vault, transferred_amount, ctx);
        vault::add_funds(&order_manager.vault_order_cap, vault, maker_payment);

        // Handle fee (deducted from taker)
        if (fee > 0) {
            let fee_payment = vault::transfer_fee_to_treasury(&order_manager.vault_order_cap, vault, taker, fee, ctx);
            transfer::public_transfer(fee_payment, order_manager.treasury);
        };
    } else if (types::is_note_status_loss(&status)) {
        // Maker wins
        
        // Transfer from taker to maker
        vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, amount, false);
        maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, amount, true);
        
        let taker_payment = vault::transfer_to_maker_vault(&order_manager.vault_order_cap, vault, amount, ctx);
        maker_vault::add_funds(&order_manager.maker_order_cap, maker_vault, taker_payment);

        // Handle fee (deducted from maker)
        if (fee > 0) {
            let fee_payment = maker_vault::transfer_fee_to_treasury(&order_manager.maker_order_cap, maker_vault, maker, asset, fee, ctx);
            transfer::public_transfer(fee_payment, order_manager.treasury);
        };
    } else if (types::is_note_status_almost_win(&status)) {
        // Almost win case
        if (payout > amount) {
            // Taker gets some profit
            let transferred_amount = payout - amount;
            vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, transferred_amount, true);
            maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, transferred_amount, false);
            
            let maker_payment = maker_vault::transfer_to_taker_vault(&order_manager.maker_order_cap, maker_vault, transferred_amount, ctx);
            vault::add_funds(&order_manager.vault_order_cap, vault, maker_payment);

            // Fee from taker
            if (fee > 0) {
                let fee_payment = vault::transfer_fee_to_treasury(&order_manager.vault_order_cap, vault, taker, fee, ctx);
                transfer::public_transfer(fee_payment, order_manager.treasury);
            };
        } else {
            // Maker gets some profit
            let transferred_amount = amount - payout;
            vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, transferred_amount, false);
            maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, transferred_amount, true);
            
            let taker_payment = vault::transfer_to_maker_vault(&order_manager.vault_order_cap, vault, transferred_amount, ctx);
            maker_vault::add_funds(&order_manager.maker_order_cap, maker_vault, taker_payment);

            // Fee from maker
            if (fee > 0) {
                let fee_payment = maker_vault::transfer_fee_to_treasury(&order_manager.maker_order_cap, maker_vault, maker, asset, fee, ctx);
                transfer::public_transfer(fee_payment, order_manager.treasury);
            };
        };
    } else {
        // Refund case
        if (amount > payout) {
            let transferred_amount = amount - payout;
            // Transfer refund cost to maker
            vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, transferred_amount, false);
            maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, transferred_amount, true);
            
            let taker_payment = vault::transfer_to_maker_vault(&order_manager.vault_order_cap, vault, transferred_amount, ctx);
            maker_vault::add_funds(&order_manager.maker_order_cap, maker_vault, taker_payment);
        };
        // No fees in refund case
    }
}

/// Calculate fee based on amount and actor
fun calculate_fee(amount: u64, winner: Actor, fee_info: &FeeInfo): u64 {
    let max_fee = types::max_fee_percentage();
    if (types::is_actor_maker(&winner)) {
        (amount * types::fee_info_maker_percentage(fee_info)) / max_fee
    } else {
        (amount * types::fee_info_taker_percentage(fee_info)) / max_fee
    }
}
