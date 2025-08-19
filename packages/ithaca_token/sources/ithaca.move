module ithaca_token::ithaca;

use sui::coin::{Self};
use sui::url;

public struct ITHACA has drop {}

fun init(witness: ITHACA, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        witness,
        6,
        b"ITHACA",
        b"ITHACA",
        b"",
        option::none<url::Url>(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    transfer::public_share_object(treasury);
}

public fun mint(
    treasury_cap: &mut coin::TreasuryCap<ITHACA>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let c = coin::mint(treasury_cap, amount, ctx);
    transfer::public_transfer(c, recipient)
} 