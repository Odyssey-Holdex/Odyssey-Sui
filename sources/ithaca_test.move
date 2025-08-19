module odyssey_sui::ithaca_test;

use sui::coin::{Self, TreasuryCap};

public struct ITHACA has drop {}

fun init(witness: ITHACA, ctx: &mut TxContext) {
		let (treasury, metadata) = coin::create_currency(
				witness,
				6,
				b"ITHACA",
				b"",
				b"",
				option::none(),
				ctx,
		);
		transfer::public_freeze_object(metadata);
		transfer::public_transfer(treasury, ctx.sender())
}

public fun mint(
		amount: u64,
		recipient: address,
		ctx: &mut TxContext,
) {
		let coin = coin::mint(treasury_cap, amount, ctx);
		transfer::public_transfer(coin, recipient)
}