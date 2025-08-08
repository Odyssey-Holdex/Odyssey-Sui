/// Order module for managing trading notes, orders, and settlements
module odyssey_sui::order;

use sui::table::{Self, Table};
use sui::event;
use sui::clock::{Self, Clock};
use sui::coin::{Coin};
use odyssey_sui::types::{Self, Note, NoteStatus, TradableAsset, Actor, SettlementInfo, FeeInfo};
use odyssey_sui::vault::{Self, OrderCap};
use odyssey_sui::maker_vault::{Self, MakerOrderCap};

// === Constants ===

/// Current version of the order module
const VERSION: u64 = 1;

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
const ENotAdmin: vector<u8> = b"Not the right admin for this order manager";

#[error]
const ENotUpgrade: vector<u8> = b"Migration is not an upgrade";

#[error]
const EWrongVersion: vector<u8> = b"Calling functions from the wrong package version";

// === Structs ===

/// Administrative capability for order operations
public struct OrderAdminCap has key, store {
    id: UID,
}

/// Coordinator capability for creating and settling notes
public struct CoordinatorCap has key, store {
    id: UID,
}

/// Order manager that tracks all trading notes and locked balances
public struct OrderManager<phantom T> has key {
    id: UID,
    /// Current version of this order manager instance
    version: u64,
    /// Admin capability ID that controls this order manager
    admin: ID,
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
    /// Treasury address
    treasury: address,
    /// Fee information
    fee_info: FeeInfo,
}

/// Internal storage structure for notes
public struct StoredNote has store {
    note: Note,
    created_at: u64,
}

/// Key for maker locked balances (maker address + asset)
public struct MakerAssetKey has copy, drop, store {
    maker: address,
    asset: TradableAsset,
}

/// Settlement action to eliminate duplication between outcome determination and processing
public struct SettlementAction has drop {
    status: NoteStatus,
    payout: u64,
    fee: u64,
    balance_change: u64,          // Amount transferred between parties
    taker_gains: bool,            // true if taker gains balance, false if maker gains
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

/// Emitted when fee percentages are changed
public struct TakerFeePercentageChanged has copy, drop {
    taker_fee_percentage: u64,
}

public struct MakerFeePercentageChanged has copy, drop {
    maker_fee_percentage: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let admin_cap = OrderAdminCap {
        id: object::new(ctx),
    };
    transfer::transfer(
        admin_cap,
        ctx.sender()
    )   
}

// === Public Functions ===

/// Initialize the order manager
public fun initialize<T>(
    admin_cap: &OrderAdminCap,
    vault_order_cap: OrderCap,
    maker_order_cap: MakerOrderCap,
    treasury: address,
    ctx: &mut TxContext
): (CoordinatorCap) {
    let coordinator_cap = CoordinatorCap {
        id: object::new(ctx),
    };

    let fee_info = types::new_fee_info(0, 0); // Default 0% fees

    let order_manager = OrderManager<T> {
        id: object::new(ctx),
        version: VERSION,
        admin: object::id(admin_cap),
        note_counter: 0,
        notes: table::new(ctx),
        settlement_infos: table::new(ctx),
        taker_locked_balances: table::new(ctx),
        maker_locked_balances: table::new(ctx),
        is_note_settled: table::new(ctx),
        vault_order_cap,
        maker_order_cap,
        treasury,
        fee_info,
    };

    transfer::share_object(order_manager);

    (coordinator_cap)
}

/// Create a new trading note (coordinator only)
public fun create_note<T, IthacaType>(
    _: &CoordinatorCap,
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note: Note,
    clock: &Clock,
    _: &mut TxContext
): u64 {
    assert!(order_manager.version == VERSION, EWrongVersion);
    
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
    let almost_win_payout = types::note_almost_win_payout(&note);
    let almost_win_spread = types::note_almost_win_spread(&note);
    let start_time = types::note_start_time(&note);
    assert!(almost_win_payout > 0 && almost_win_payout <= win_payout, EInvalidPayout);
    assert!(almost_win_spread <= spread, EInvalidSpread);
    assert!(start_time <= expiry_time, EInvalidExpiryTime);

    // Check balances
    let taker_balance = taker_withdrawable_balance(order_manager, vault, taker);
    let win_amount = win_payout - amount;
    let maker_balance = maker_withdrawable_balance(order_manager, maker_vault, maker, *asset);

    assert!(taker_balance >= amount, EInsufficientTakerBalance);
    assert!(maker_balance >= win_amount, EInsufficientMakerBalance);

    // Generate note ID
    let note_id = order_manager.note_counter;
    order_manager.note_counter = order_manager.note_counter + 1;

    // Store note
    let stored_note = StoredNote {
        note: copy note,
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
    _: &CoordinatorCap,
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note_id: u64,
    spot_price: u64,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(order_manager.version == VERSION, EWrongVersion);
    assert!(table::contains(&order_manager.notes, note_id), ENoteNotFound);
    
    let is_settled = *table::borrow(&order_manager.is_note_settled, note_id);
    assert!(!is_settled, ENoteAlreadySettled);
    
    let stored_note = table::borrow(&order_manager.notes, note_id);
    let note_copy = stored_note.note; // Copy the entire note
    
    // Check if note has expired
    assert!(clock::timestamp_ms(clock) >= types::note_expiry_time(&note_copy), ENoteNotExpired);

    // Determine outcome
    let settlement_action = determine_settlement_outcome(
        &note_copy, // Pass reference to the copied note
        spot_price,
        &order_manager.fee_info
    );

    // Mark as settled
    table::remove(&mut order_manager.is_note_settled, note_id);
    table::add(&mut order_manager.is_note_settled, note_id, true);

    // Store settlement info
    let settlement_info = types::new_settlement_info(spot_price, clock::timestamp_ms(clock));
    table::add(&mut order_manager.settlement_infos, note_id, settlement_info);

    // Save values for event before moving settlement_action
    let final_status = settlement_action.status;
    let final_payout = settlement_action.payout;
    let final_fee = settlement_action.fee;

    // Process settlement
    process_settlement(
        order_manager,
        vault,
        maker_vault,
        &note_copy, // Pass reference to the copied note
        settlement_action,
        ctx
    );

    // Emit event
    event::emit(NoteSettled {
        note_id,
        status: final_status,
        settlement_price: spot_price,
        payout: final_payout,
        fee: final_fee,
    });
}

/// Migrate order manager to new version (admin only)
entry fun migrate<T>(order_manager: &mut OrderManager<T>, admin_cap: &OrderAdminCap) {
    assert!(order_manager.admin == object::id(admin_cap), ENotAdmin);
    assert!(order_manager.version < VERSION, ENotUpgrade);
    order_manager.version = VERSION;
}

/// Set taker fee percentage (admin only)
public fun set_taker_fee_percentage<T>(
    _: &OrderAdminCap,
    order_manager: &mut OrderManager<T>,
    taker_fee_percentage: u64,
) {
    assert!(order_manager.version == VERSION, EWrongVersion);
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
    assert!(order_manager.version == VERSION, EWrongVersion);
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
    assert!(order_manager.version == VERSION, EWrongVersion);
    let sender = tx_context::sender(ctx);
    let locked_amount = taker_locked_balance(order_manager, sender);
    vault::withdraw(&order_manager.vault_order_cap, vault, sender, amount, locked_amount, ctx)
}

public fun maker_withdraw<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    tradable_asset: TradableAsset,
    amount: u64,
    ctx: &mut TxContext
): Coin<T> {
    assert!(order_manager.version == VERSION, EWrongVersion);
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
    spot_price: u64,
    fee_info: &FeeInfo,
): SettlementAction {
    let starting_price = types::note_starting_price(note);
    let spread = types::note_spread(note);
    let direction = types::note_direction(note);
    let amount = types::note_amount(note);
    let win_payout = types::note_win_payout(note);
    let refund_payout = types::note_refund_payout(note);
    let almost_win_spread = types::note_almost_win_spread(note);
    let almost_win_payout = types::note_almost_win_payout(note);

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

    // Calculate fee and determine settlement actions
    if (types::is_note_status_win(&status)) {
        // Taker wins
        let transferred_amount = win_payout - amount;
        let fee = calculate_fee(transferred_amount, types::actor_taker(), fee_info);
        SettlementAction {
            status,
            payout,
            fee,
            balance_change: transferred_amount,
            taker_gains: true,
        }
    } else if (types::is_note_status_loss(&status)) {
        // Maker wins
        let fee = calculate_fee(amount, types::actor_maker(), fee_info);
        SettlementAction {
            status,
            payout,
            fee,
            balance_change: amount,
            taker_gains: false,
        }
    } else if (types::is_note_status_almost_win(&status)) {
        // Almost win case
        if (almost_win_payout > amount) {
            // Taker gets some profit
            let transferred_amount = almost_win_payout - amount;
            let fee = calculate_fee(transferred_amount, types::actor_taker(), fee_info);
            SettlementAction {
                status,
                payout,
                fee,
                balance_change: transferred_amount,
                taker_gains: true,
            }
        } else {
            // Maker gets some profit
            let transferred_amount = amount - almost_win_payout;
            let fee = calculate_fee(transferred_amount, types::actor_maker(), fee_info);
            SettlementAction {
                status,
                payout,
                fee,
                balance_change: transferred_amount,
                taker_gains: false,
            }
        }
    } else {
        // Refund case
        let balance_change = if (amount > payout) {
            amount - payout
        } else {
            0
        };
        SettlementAction {
            status,
            payout,
            fee: 0, // No fees in refund case
            balance_change,
            taker_gains: false,
        }
    }
}

/// Process the settlement by transferring funds and fees
fun process_settlement<T, IthacaType>(
    order_manager: &mut OrderManager<T>,
    vault: &mut vault::Vault<T>,
    maker_vault: &mut maker_vault::MakerVault<T, IthacaType>,
    note: &Note,
    settlement_action: SettlementAction,
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

    // Execute settlement based on action
    if (settlement_action.balance_change > 0) {
        if (settlement_action.taker_gains) {
            // Transfer from maker to taker - credit full amount to taker
            vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, settlement_action.balance_change, true);
            maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, settlement_action.balance_change, false);
            
            let maker_payment = maker_vault::transfer_to_taker_vault(&order_manager.maker_order_cap, maker_vault, settlement_action.balance_change, ctx);
            vault::add_funds(&order_manager.vault_order_cap, vault, maker_payment);
        } else {
            // Transfer from taker to maker - credit full amount to maker
            vault::adjust_taker_balance(&order_manager.vault_order_cap, vault, taker, settlement_action.balance_change, false);
            maker_vault::adjust_maker_balance(&order_manager.maker_order_cap, maker_vault, maker, asset, settlement_action.balance_change, true);
            
            let taker_payment = vault::transfer_to_maker_vault(&order_manager.vault_order_cap, vault, settlement_action.balance_change, ctx);
            maker_vault::add_funds(&order_manager.maker_order_cap, maker_vault, taker_payment);
        };
    };

    // Handle fees - deduct separately from the winner's balance
    if (settlement_action.fee > 0) {
        if (settlement_action.taker_gains) {
            let fee_payment = vault::transfer_fee_to_treasury(&order_manager.vault_order_cap, vault, taker, settlement_action.fee, ctx);
            transfer::public_transfer(fee_payment, order_manager.treasury);
        } else {
            let fee_payment = maker_vault::transfer_fee_to_treasury(&order_manager.maker_order_cap, maker_vault, maker, asset, settlement_action.fee, ctx);
            transfer::public_transfer(fee_payment, order_manager.treasury);
        };
    };
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

#[test_only]
public fun test_init(ctx: &mut TxContext) {
    init(ctx);
}
