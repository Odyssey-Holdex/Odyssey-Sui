/// Types module containing shared data structures for the trading vault system
module odyssey_sui::types;

use std::string::String;

/// Direction for trading orders
public enum Direction has copy, drop, store {
    UP,
    DOWN
}

/// Status of a trading note/order
public enum NoteStatus has copy, drop, store {
    WIN,
    LOSS,
    REFUND,
    ALMOST_WIN
}

/// Actor type in the trading system
public enum Actor has copy, drop, store {
    MAKER,
    TAKER
}

/// Trading note/order structure
public struct Note has copy, drop, store {
    taker: address,           // Trader's address
    maker: address,           // Market Maker's pool address  
    symbol: String,           // Symbol of asset being traded
    direction: Direction,     // 'up' or 'down'
    amount: u64,              // Bet amount
    starting_price: u64,      // Price at bet placement (scaled)
    spread: u64,              // Spread in USD (scaled)
    win_payout: u64,          // Payout if bet wins
    expiry_time: u64,         // Expiry timestamp
    nonce: u64,               // Unique identifier
    refund_payout: u64,       // Payout if bet results in refund
    almost_win_spread: u64,   // Spread to define almost win zone
    almost_win_payout: u64,   // Payout if bet results in almost win
    start_time: u64,          // Start time for the note
}

/// Maker information structure, per maker per asset
public struct MakerInfo has copy, drop, store {
    staked_ithaca_tokens: u64,
    collateral: u64,
}

/// Settlement information (from OrderV12) - without report field
public struct SettlementInfo has copy, drop, store {
    price: u64,
    timestamp: u64,
}

/// Fee manager structure
public struct FeeInfo has copy, drop, store {
    taker_fee_percentage: u64,
    maker_fee_percentage: u64,
    max_fee_percentage: u64,
}

// === Constants ===

const MAX_FEE_PERCENTAGE: u64 = 10000; // 1e5 (allows for 2 decimal places, e.g. 10000 = 100.00%)

// === Public functions ===

/// Create a new Note
public fun new_note(
    taker: address,
    maker: address,
    symbol: String,
    direction: Direction,
    amount: u64,
    starting_price: u64,
    spread: u64,
    win_payout: u64,
    expiry_time: u64,
    nonce: u64,
    refund_payout: u64,
    almost_win_spread: u64,
    almost_win_payout: u64,
    start_time: u64,
): Note {
    Note {
        taker,
        maker,
        symbol,
        direction,
        amount,
        starting_price,
        spread,
        win_payout,
        expiry_time,
        nonce,
        refund_payout,
        almost_win_spread,
        almost_win_payout,
        start_time,
    }
}

/// Create MakerInfo
public fun new_maker_info(
    staked_ithaca_tokens: u64,
): MakerInfo {
    MakerInfo {
        staked_ithaca_tokens,
        collateral: 0,
    }
}

/// Create SettlementInfo
public fun new_settlement_info(
    price: u64,
    timestamp: u64,
): SettlementInfo {
    SettlementInfo {
        price,
        timestamp,
    }
}

/// Create FeeInfo
public fun new_fee_info(
    taker_fee_percentage: u64,
    maker_fee_percentage: u64,
): FeeInfo {
    FeeInfo {
        taker_fee_percentage,
        maker_fee_percentage,
        max_fee_percentage: MAX_FEE_PERCENTAGE,
    }
}

// === Helper functions for creating enum variants ===

public fun direction_up(): Direction { Direction::UP }
public fun direction_down(): Direction { Direction::DOWN }

public fun note_status_win(): NoteStatus { NoteStatus::WIN }
public fun note_status_loss(): NoteStatus { NoteStatus::LOSS }
public fun note_status_refund(): NoteStatus { NoteStatus::REFUND }
public fun note_status_almost_win(): NoteStatus { NoteStatus::ALMOST_WIN }

public fun actor_maker(): Actor { Actor::MAKER }
public fun actor_taker(): Actor { Actor::TAKER }

// === Getter functions for Note ===

public fun note_taker(note: &Note): address { note.taker }
public fun note_maker(note: &Note): address { note.maker }
public fun note_symbol(note: &Note): String { note.symbol }
public fun note_direction(note: &Note): Direction { note.direction }
public fun note_amount(note: &Note): u64 { note.amount }
public fun note_starting_price(note: &Note): u64 { note.starting_price }
public fun note_spread(note: &Note): u64 { note.spread }
public fun note_win_payout(note: &Note): u64 { note.win_payout }
public fun note_expiry_time(note: &Note): u64 { note.expiry_time }
public fun note_nonce(note: &Note): u64 { note.nonce }
public fun note_refund_payout(note: &Note): u64 { note.refund_payout }
public fun note_almost_win_spread(note: &Note): u64 { note.almost_win_spread }
public fun note_almost_win_payout(note: &Note): u64 { note.almost_win_payout }
public fun note_start_time(note: &Note): u64 { note.start_time }

// === Getter functions for MakerInfo ===

public fun maker_info_staked_tokens(info: &MakerInfo): u64 { info.staked_ithaca_tokens }

public fun maker_info_collateral(info: &MakerInfo): u64 { info.collateral }

// === Setter functions for MakerInfo ===

public fun set_maker_collateral(info: &mut MakerInfo, amount: u64) {
    info.collateral = amount;
}

public fun add_maker_collateral(info: &mut MakerInfo, amount: u64) {
    info.collateral = info.collateral + amount;
}

public fun subtract_maker_collateral(info: &mut MakerInfo, amount: u64) {
    info.collateral = info.collateral - amount;
}

public fun add_staked_tokens(info: &mut MakerInfo, amount: u64) {
    info.staked_ithaca_tokens = info.staked_ithaca_tokens + amount;
}

// === Getter functions for FeeInfo ===

public fun fee_info_taker_percentage(info: &FeeInfo): u64 { info.taker_fee_percentage }
public fun fee_info_maker_percentage(info: &FeeInfo): u64 { info.maker_fee_percentage }
public fun fee_info_max_percentage(info: &FeeInfo): u64 { info.max_fee_percentage }

// === Constants access ===

public fun max_fee_percentage(): u64 { MAX_FEE_PERCENTAGE }

// === Comparison functions ===

public fun is_direction_up(direction: &Direction): bool {
    match (direction) {
        Direction::UP => true,
        Direction::DOWN => false,
    }
}

public fun is_note_status_win(status: &NoteStatus): bool {
    match (status) {
        NoteStatus::WIN => true,
        _ => false,
    }
}

public fun is_note_status_loss(status: &NoteStatus): bool {
    match (status) {
        NoteStatus::LOSS => true,
        _ => false,
    }
}

public fun is_note_status_almost_win(status: &NoteStatus): bool {
    match (status) {
        NoteStatus::ALMOST_WIN => true,
        _ => false,
    }
}

public fun is_note_status_refund(status: &NoteStatus): bool {
    match (status) {
        NoteStatus::REFUND => true,
        _ => false,
    }
}

public fun is_actor_maker(actor: &Actor): bool {
    match (actor) {
        Actor::MAKER => true,
        Actor::TAKER => false,
    }
}
