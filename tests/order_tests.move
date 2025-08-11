#[test_only]
module odyssey_sui::order_tests;

use sui::test_scenario::{Self, ctx};
use sui::test_utils::assert_eq;
use std::option::none;
use std::option::some;

use odyssey_sui::test_utils::{
    Self,
    setup_test_scenario,
    get_test_addresses,
    cleanup_scenario,
    setup_complete_system,
    setup_funded_scenario,
    create_test_note,
    create_custom_note,
    deposit_trader_funds,
    get_minimum_stake,
    mint_ithaca,
    mint_usdc,
    create_test_clock,
    advance_time,
    timestamp_plus_days,
};
use odyssey_sui::types;
use odyssey_sui::order::{Self, CoordinatorCap};
use odyssey_sui::maker_vault;
use odyssey_sui::vault;

// ==========
// Initialization Tests
// ==========
#[test]
#[expected_failure(abort_code = order::ENotZeroAddress)]
public fun test_initialize_fails_with_zero_treasury() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();

    let zero_address = @0x0;
    test_scenario::next_tx(&mut scenario, governor);
    let (vault, maker_vault, order_manager) = setup_complete_system(&mut scenario, none(), some(zero_address));
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);


    cleanup_scenario(scenario)
}

// ==========
// Create Note Tests
// ==========

#[test]
public fun test_create_note_success_and_event_and_locks() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());

    // Fund actors
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();
    let amount1 = 1_000;
    let win_payout1 = amount1 * 3;

    // Register maker and fund balances
    let stake_amount = get_minimum_stake();
    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker(&mut maker_vault, ithaca, ctx(&mut scenario));

    // Ensure maker collateral sufficient and taker funds available
    test_scenario::next_tx(&mut scenario, maker1);
    let maker_collateral = 10_000;
    let usdc_for_maker = mint_usdc(&mut scenario, maker1, maker_collateral);
    maker_vault::deposit_collateral(&mut maker_vault, types::tradable_asset_btc(), usdc_for_maker, ctx(&mut scenario));

    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount1);

    // Create note
    let clock = create_test_clock(&mut scenario, 1);
    let note = create_test_note(trader1, maker1, amount1, win_payout1, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Assert event
    order::assert_note_created_event(note_id, trader1, maker1, types::tradable_asset_btc(), amount1, types::note_expiry_time(&note));

    // Locks
    test_scenario::next_tx(&mut scenario, trader1);
    let taker_locked = order::taker_locked_balance(&order_manager, trader1);
    assert_eq(taker_locked, amount1);

    test_scenario::next_tx(&mut scenario, maker1);
    let maker_locked = order::maker_locked_balance(&order_manager, maker1, types::tradable_asset_btc());
    assert_eq(maker_locked, win_payout1 - amount1);

    // Create another note and validate cumulative locks
    let amount2 = 300;
    let win_payout2 = amount2 * 10;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount2);

    let note2 = create_test_note(trader1, maker1, amount2, win_payout2, 2);
    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap2 = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap2, &mut order_manager, &mut vault, &mut maker_vault, note2, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap2);

    test_scenario::next_tx(&mut scenario, trader1);
    let taker_locked_after = order::taker_locked_balance(&order_manager, trader1);
    assert_eq(taker_locked_after, amount1 + amount2);

    test_scenario::next_tx(&mut scenario, maker1);
    let maker_locked_after = order::maker_locked_balance(&order_manager, maker1, types::tradable_asset_btc());
    assert_eq(maker_locked_after, (win_payout1 - amount1) + (win_payout2 - amount2));

    // destroy clock
    clock.destroy_for_testing();

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidNote)]
public fun test_cannot_create_note_with_zero_amount() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Ensure trader funded
    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1);

    // amount = 0
    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 0, 84000, 15, 100, timestamp_plus_days(&clock, 2), 0, 0, 10, 1, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidNote)]
public fun test_cannot_create_note_with_zero_taker_or_maker() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader
    deposit_trader_funds(&mut scenario, &mut vault, trader1, 100);

    // taker is zero address
    let note1 = types::new_note(@0x0, maker1, types::tradable_asset_btc(), types::direction_up(), 10, 84000, 15, 30, timestamp_plus_days(&clock, 2), 0, 10, 10, 20, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note1, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidPayout)]
public fun test_cannot_create_note_with_invalid_payouts() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1000);

    // win_payout <= amount
    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 100, timestamp_plus_days(&clock, 2), 0, 100, 10, 0, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidPayout)]
public fun test_cannot_create_note_with_refund_payout_bigger_than_amount() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1000);

    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 200, timestamp_plus_days(&clock, 2), 0, 101, 10, 100, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidPayout)]
public fun test_cannot_create_note_with_almost_win_payout_zero() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1000);

    // almost win payout = 0
    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 200, timestamp_plus_days(&clock, 2), 0, 100, 10, 0, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidPayout)]
public fun test_cannot_create_note_with_almost_win_payout_zero_more_than_win() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1000);

    // almost win payout = 201, win payout = 200
    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 200, timestamp_plus_days(&clock, 2), 0, 100, 10, 201, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidSpread)]
public fun test_cannot_create_note_with_almost_win_spread_more_than_spread() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 1000);

    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 200, timestamp_plus_days(&clock, 2), 0, 100, 16, 100, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInsufficientTakerBalance)]
public fun test_cannot_create_note_if_taker_balance_less_than_amount() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader less than amount
    deposit_trader_funds(&mut scenario, &mut vault, trader1, 99);

    let note = create_custom_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 300, timestamp_plus_days(&clock, 2), 100, 10, 100);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInsufficientMakerBalance)]
public fun test_cannot_create_note_if_maker_balance_less_than_win_amount() {
    let mut scenario = setup_test_scenario();
    // Use clean system to avoid pre-funded maker collateral
    let (mut vault, mut maker_vault, mut order_manager) = setup_complete_system(&mut scenario, none(), none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader sufficiently
    deposit_trader_funds(&mut scenario, &mut vault, trader1, 100);

    // Note requires maker win collateral of 800 (900 - 100) but maker has 0 -> should fail
    let clock = create_test_clock(&mut scenario, 1);
    let note = create_custom_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 900, timestamp_plus_days(&clock, 2), 100, 10, 100);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Cleanup
    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidExpiryTime)]
public fun test_cannot_create_note_if_expiry_not_in_future() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader sufficiently
    deposit_trader_funds(&mut scenario, &mut vault, trader1, 100);

    // expiry <= now
    let note = create_custom_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 300, /* expiry */ timestamp_plus_days(&clock, 0), 100, 10, 100);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidExpiryTime)]
public fun test_cannot_create_note_if_start_more_than_expiry() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    deposit_trader_funds(&mut scenario, &mut vault, trader1, 100);

    // Manually craft note with start_time > expiry_time
    let expiry = test_utils::timestamp_plus_days(&clock, 1);
    let start_time = expiry + 1;
    let note = types::new_note(trader1, maker1, types::tradable_asset_btc(), types::direction_up(), 100, 84000, 15, 300, expiry, 0, 100, 10, 150, start_time);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let _ = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

// ==========
// Settle Note Tests
// ==========

#[test]
public fun test_settle_win_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set taker fee percentage to 5%
    let taker_fee_percentage = 50000000u64; // 5% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, taker_fee_percentage, 0);

    // Prepare note
    let amount = 1_000;
    let win_payout = amount * 3; // win_amount = 2000
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // Advance time past expiry
    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    test_scenario::next_tx(&mut scenario, coordinator);
    let spot_price = 84000 + 16; // > start + spread -> win
    let coordinator_cap2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coordinator_cap2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap2);

    // Calculate expected fee: 5% of winning amount (2000)
    let winning_amount = win_payout - amount; // 2000
    let expected_fee = (winning_amount * taker_fee_percentage) / types::max_fee_percentage(); // 100

    // Assert event with fee
    order::assert_note_settled_event(note_id, 0, spot_price, win_payout, expected_fee);

    let amount_after_fee = winning_amount - expected_fee; // 1900

    // Verify taker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance + amount_after_fee); // Taker gets amount after fee

    // Verify maker balance
    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance - winning_amount); // Maker loses the full winning amount

    // Verify vault total asset availability
    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance + amount_after_fee); // Vault has amount after fee

    // Verify maker vault total asset availability
    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance - winning_amount);

    // Locks reduced
    test_scenario::next_tx(&mut scenario, trader1);
    assert_eq(order::taker_locked_balance(&order_manager, trader1), 0);
    test_scenario::next_tx(&mut scenario, maker1);
    assert_eq(order::maker_locked_balance(&order_manager, maker1, types::tradable_asset_btc()), 0);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
public fun test_settle_loss_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set maker fee percentage to 10%
    let maker_fee_percentage = 100000000u64; // 10% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, 0, maker_fee_percentage);

    let amount = 1_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    
    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    // expire then settle with price just above start -> LOSS
    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 + 1; // > start and <= start+almost_win_spread => LOSS

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coordinator_cap2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap2);

    // Calculate expected fee: 10% of loss amount (1000)
    let expected_fee = (amount * maker_fee_percentage) / types::max_fee_percentage(); // 100

    order::assert_note_settled_event(note_id, 1, spot_price, amount, expected_fee);

    let amount_after_fee = amount - expected_fee; // 900
    
    // Verify taker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance - amount);

    // Verify maker balance
    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance + amount_after_fee); // Maker gets amount after fee

    // Verify vault total asset availability
    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance - amount);

    // Verify maker vault total asset availability
    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance + amount_after_fee); // Maker vault has amount after fee

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
public fun test_settle_refund_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set both fee percentages to make sure no fees are applied on refund
    let fee_percentage = 50000000u64; // 5% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, fee_percentage, fee_percentage);

    let amount = 1_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    
    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 - 1; // < start => REFUND

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coordinator_cap2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap2);

    // Assert event (no fee for refund)
    order::assert_note_settled_event(note_id, 2, spot_price, amount, 0);
    
    // Verify taker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance); // Taker gets full refund

    // Verify maker balance
    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance); // Maker gets nothing (no fees)

    // Verify vault total asset availability
    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance); // Vault has the refund amount

    // Verify maker vault total asset availability
    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance); // Maker vault has same amount

    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}


#[test]
public fun test_settle_refund_less_than_amount_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fees should not apply on refund
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, 999, 888);

    let amount = 1_000_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());

    let refund_payout = amount - 123_456; // maker gains 123_456

    let note = create_custom_note(
        trader1,
        maker1,
        types::tradable_asset_btc(),
        types::direction_up(),
        amount,
        84000,
        15,
        win_payout,
        timestamp_plus_days(&clock, 2),
        /* refund */ refund_payout,
        /* almost_win_spread */ 10,
        /* almost_win_payout */ amount // not used in refund
    );

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coord, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 - 1; // refund band

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    order::assert_note_settled_event(note_id, 2, spot_price, refund_payout, 0);

    let transferred = amount - refund_payout; // maker gains this

    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance - transferred);

    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance + transferred);

    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance - transferred);

    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance + transferred);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
public fun test_settle_almost_win_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set both fee percentages to test almost win scenario
    let fee_percentage = 75000000u64; // 7.5% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, fee_percentage, fee_percentage);

    let amount = 1_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    
    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 + 11; // > start + almost_win_spread (10) and <= spread (15)

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coordinator_cap2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap2);

    // For almost win, the payout is greater than amount, so taker gains and pays fee
    // almost_win_payout = 2000, amount = 1000, transfer = 1000
    let transfer_amount = types::note_almost_win_payout(&note) - amount; // 1000
    let expected_fee = (transfer_amount * fee_percentage) / types::max_fee_percentage(); // 75

    order::assert_note_settled_event(note_id, 3, spot_price, types::note_almost_win_payout(&note), expected_fee);

    let almost_win_payout = types::note_almost_win_payout(&note);
    let transfer_amount = almost_win_payout - amount; // 1000
    let amount_after_fee = transfer_amount - expected_fee; // 925

    // Verify taker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance + amount_after_fee); // Taker gets transfer amount after fee

    // Verify maker balance
    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance - transfer_amount); // Maker loses the transfer amount

    // Verify vault total asset availability
    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance + amount_after_fee); // Vault has transfer amount after fee

    // Verify maker vault total asset availability
    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance - transfer_amount); // Maker vault has reduced amount

    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_settle_almost_win_equal_amount_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set fees (should not apply when no transfer)
    let fee_percentage = 60000000u64; // 6% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, fee_percentage, fee_percentage);

    let amount = 1_000_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());

    let note = create_custom_note(
        trader1,
        maker1,
        types::tradable_asset_btc(),
        types::direction_up(),
        amount,
        84000,
        15,
        win_payout,
        timestamp_plus_days(&clock, 2),
        /* refund */ amount,
        /* almost_win_spread */ 10,
        /* almost_win_payout */ amount
    );

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coord, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 + 11; // almost win band

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    // Fee must be zero; payout equals amount
    order::assert_note_settled_event(note_id, 3, spot_price, amount, 0);

    // No net transfers
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance);

    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance);

    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance);

    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
public fun test_settle_almost_win_less_than_amount_up_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Maker fee will apply when maker gains
    let maker_fee_percentage = 80000000u64; // 8% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, 0, maker_fee_percentage);

    let amount = 1_000_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());

    let almost_win_payout = amount - 100_000; // maker gains 100_000

    let note = create_custom_note(
        trader1,
        maker1,
        types::tradable_asset_btc(),
        types::direction_up(),
        amount,
        84000,
        15,
        win_payout,
        timestamp_plus_days(&clock, 2),
        /* refund */ amount,
        /* almost_win_spread */ 10,
        /* almost_win_payout */ almost_win_payout
    );

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coord, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    let spot_price = 84000 + 11; // almost win band

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    let transferred = amount - almost_win_payout; // 100_000
    let expected_fee = (transferred * maker_fee_percentage) / types::max_fee_percentage(); // 8000

    order::assert_note_settled_event(note_id, 3, spot_price, almost_win_payout, expected_fee);

    let amount_after_fee = transferred - expected_fee;

    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance - transferred);

    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance + amount_after_fee);

    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance - transferred);

    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance + amount_after_fee);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}


#[test]
public fun test_settle_variants_down_direction() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set taker fee percentage for win scenario
    let taker_fee_percentage = 90000000u64; // 9% (1e9 precision)
    test_utils::set_fee_percentages(&mut scenario, &mut order_manager, taker_fee_percentage, 0);

    let amount = 1_000;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let prev_taker_balance = vault::taker_balance(&vault, trader1);
    let prev_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    let note = create_custom_note(
        trader1,
        maker1,
        types::tradable_asset_btc(),
        types::direction_down(),
        amount,
        84000,
        15,
        win_payout,
        test_utils::timestamp_plus_days(&clock, 2),
        amount,
        10,
        amount + (win_payout - amount) / 2,
    );

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::next_tx(&mut scenario, coordinator);
    advance_time(&mut clock, 3 * 24 * 60 * 60 * 1000);

    // Win for DOWN: spot < start - spread
    let spot_price_win = 84000 - 16;
    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price_win, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    // Calculate expected fee: 9% of winning amount (2000)
    let winning_amount = win_payout - amount; // 2000
    let expected_fee = (winning_amount * taker_fee_percentage) / types::max_fee_percentage(); // 180

    // Assert event with fee
    order::assert_note_settled_event(note_id, 0, spot_price_win, win_payout, expected_fee);

    let amount_after_fee = winning_amount - expected_fee; // 1820

    // Verify taker balance
    test_scenario::next_tx(&mut scenario, trader1);
    let final_taker_balance = vault::taker_balance(&vault, trader1);
    assert_eq(final_taker_balance, prev_taker_balance + amount_after_fee); // Taker gets amount after fee

    // Verify maker balance
    test_scenario::next_tx(&mut scenario, maker1);
    let final_maker_balance = maker_vault::get_maker_collateral(&maker_vault, maker1, &types::tradable_asset_btc());
    assert_eq(final_maker_balance, prev_maker_balance - winning_amount); // Maker loses the full winning amount

    // Verify vault total asset availability
    let final_vault_asset = vault::total_asset_available(&vault);
    assert_eq(final_vault_asset, prev_taker_balance + amount_after_fee); // Vault has amount after fee

    // Verify maker vault total asset availability
    let final_maker_vault_asset = maker_vault::total_asset_available(&maker_vault);
    assert_eq(final_maker_vault_asset, prev_maker_balance - winning_amount); // Maker vault has reduced amount

    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::ENoteNotFound)]
public fun test_cannot_settle_nonexistent_note() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, _, _, _, _, _, coordinator) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, 999, 83000, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coordinator_cap);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::ENoteAlreadySettled)]
public fun test_cannot_settle_same_note_twice() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, mut clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    let amount = 500;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    let note = create_test_note(trader1, maker1, amount, win_payout, 1);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coord, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord);

    advance_time(&mut clock, 2 * 24 * 60 * 60 * 1000);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, 84000 + 16, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    // Second settle should fail
    test_scenario::next_tx(&mut scenario, coordinator);
    let coord3 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord3, &mut order_manager, &mut vault, &mut maker_vault, note_id, 84000 + 16, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord3);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::ENoteNotExpired)]
public fun test_cannot_settle_before_expiry() {
    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    let amount = 500;
    let win_payout = amount * 3;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coord = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coord, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord);

    // No time advance
    test_scenario::next_tx(&mut scenario, coordinator);
    let coord2 = scenario.take_from_sender<CoordinatorCap>();
    order::settle_note(&coord2, &mut order_manager, &mut vault, &mut maker_vault, note_id, 84000 + 16, &clock, ctx(&mut scenario));
    scenario.return_to_sender(coord2);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    clock.destroy_for_testing();
    cleanup_scenario(scenario)
}

// ==========
// Fee Percentage Tests
// ==========

#[test]
public fun test_set_maker_fee_percentage_success_and_event() {
    let mut scenario = setup_test_scenario();
    let (mut order_manager) = {
        let (vault, maker_vault, om) = setup_complete_system(&mut scenario, none(), none());
        test_scenario::return_shared(vault);
        test_scenario::return_shared(maker_vault);
        (om)
    };

    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let new_percentage = 123;

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<order::OrderAdminCap>();
    order::set_maker_fee_percentage(&admin_cap, &mut order_manager, new_percentage);
    order::assert_maker_fee_percentage_changed_event(new_percentage);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidFeePercentage)]
public fun test_cannot_set_maker_fee_percentage_above_max() {
    let mut scenario = setup_test_scenario();
    let (mut order_manager) = {
        let (vault, maker_vault, om) = setup_complete_system(&mut scenario, none(), none());
        test_scenario::return_shared(vault);
        test_scenario::return_shared(maker_vault);
        (om)
    };

    let (governor, _, _, _, _, _, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<order::OrderAdminCap>();
    let too_high = types::max_fee_percentage() + 1;
    order::set_maker_fee_percentage(&admin_cap, &mut order_manager, too_high);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_set_taker_fee_percentage_success_and_event() {
    let mut scenario = setup_test_scenario();
    let (mut order_manager) = {
        let (vault, maker_vault, om) = setup_complete_system(&mut scenario, none(), none());
        test_scenario::return_shared(vault);
        test_scenario::return_shared(maker_vault);
        (om)
    };

    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let new_percentage = 456;

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<order::OrderAdminCap>();
    order::set_taker_fee_percentage(&admin_cap, &mut order_manager, new_percentage);
    order::assert_taker_fee_percentage_changed_event(new_percentage);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::EInvalidFeePercentage)]
public fun test_cannot_set_taker_fee_percentage_above_max() {
    let mut scenario = setup_test_scenario();
    let (mut order_manager) = {
        let (vault, maker_vault, om) = setup_complete_system(&mut scenario, none(), none());
        test_scenario::return_shared(vault);
        test_scenario::return_shared(maker_vault);
        (om)
    };

    let (governor, _, _, _, _, _, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<order::OrderAdminCap>();
    let too_high = types::max_fee_percentage() + 1;
    order::set_taker_fee_percentage(&admin_cap, &mut order_manager, too_high);
    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}
