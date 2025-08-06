#[test_only]
module trading_vault::order_tests;

use sui::test_scenario::{Self, ctx};
use sui::coin::{Self};
use sui::clock::{Self};
use trading_vault::order::{Self, OrderManager, OrderAdminCap, CoordinatorCap};
use trading_vault::vault::{Self, Vault};
use trading_vault::maker_vault::{Self, MakerVault};
use trading_vault::types::{Self, Note};
use trading_vault::test_utils::{Self, USDC, ITHACA, setup_test_scenario, get_test_addresses, cleanup_scenario, 
    create_test_note, create_custom_note, timestamp_plus_days, advance_time};

#[test]
fun test_initialize_order_manager() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, treasury, coordinator) = get_test_addresses();
    
    // Setup prerequisites
    test_scenario::next_tx(&mut scenario, governor);
    let (vault_admin_cap, vault_order_cap, vault) = vault::initialize<USDC>(ctx(&mut scenario));
    let (maker_vault_admin_cap, maker_order_cap, maker_vault) = maker_vault::initialize<USDC, ITHACA>(200_000_000, ctx(&mut scenario));
    
    // Initialize order manager
    test_scenario::next_tx(&mut scenario, governor);
    let (order_admin_cap, coordinator_cap, order_manager) = order::initialize<USDC>(
        vault_order_cap, maker_order_cap, treasury, ctx(&mut scenario)
    );
    
    // Verify initialization
    assert!(order::note_counter(&order_manager) == 0);
    assert!(order::treasury(&order_manager) == treasury);
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, coordinator);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_create_note_success() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000; // 2 USDC
    let win_payout = 6_000_000; // 6 USDC (3x return)
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Verify note creation
    assert!(note_id == 0); // First note should have ID 0
    assert!(order::note_counter(&order_manager) == 1);
    assert!(!order::is_note_settled(&order_manager, note_id));
    
    // Verify locked balances
    assert!(order::taker_locked_balance(&order_manager, trader_1) == amount);
    assert!(order::maker_locked_balance(&order_manager, maker_1, types::tradable_asset_btc()) == win_payout - amount);
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::EInvalidNote)]
fun test_create_note_zero_amount_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note with zero amount
    let amount = 0; // Invalid: zero amount
    let win_payout = 6_000_000;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::EInvalidExpiryTime)]
fun test_create_note_expired_time_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note with expiry time in the past
    let amount = 2_000_000;
    let win_payout = 6_000_000;
    let expiry_time = clock::timestamp_ms(&clock) - 1000; // 1 second ago
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::EInvalidPayout)]
fun test_create_note_invalid_win_payout_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note with invalid win payout (less than amount)
    let amount = 2_000_000;
    let win_payout = 1_000_000; // Invalid: less than amount
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::EInsufficientTakerBalance)]
fun test_create_note_insufficient_taker_balance_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note with amount exceeding taker balance
    let amount = 10_000_000; // 10 USDC (taker only has 5 USDC)
    let win_payout = 20_000_000; // 20 USDC
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::EInsufficientMakerBalance)]
fun test_create_note_insufficient_maker_balance_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note with win amount exceeding maker balance
    let amount = 2_000_000; // 2 USDC
    let win_payout = 20_000_000; // 20 USDC (maker only has 10 USDC, so win_amount = 18 USDC exceeds balance)
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_settle_note_taker_wins() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000; // 2 USDC
    let win_payout = 6_000_000; // 6 USDC
    let starting_price = 84000;
    let spread = 15;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_custom_note(
        trader_1, maker_1, types::tradable_asset_btc(), types::direction_up(),
        amount, starting_price, spread, win_payout, expiry_time, amount, 10, 4_000_000
    );
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Advance time to expiry
    advance_time(&mut clock, 24 * 60 * 60 * 1000); // 1 day
    
    // Settle with winning price (starting_price + spread + 1)
    let spot_price = starting_price + spread + 1; // 84016 (taker wins)
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    
    // Verify settlement
    assert!(order::is_note_settled(&order_manager, note_id));
    
    // Check that balances changed (taker should have won)
    // Note: Exact balance verification would require checking vault balances
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_settle_note_taker_loses() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000; // 2 USDC
    let win_payout = 6_000_000; // 6 USDC
    let starting_price = 84000;
    let spread = 15;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_custom_note(
        trader_1, maker_1, types::tradable_asset_btc(), types::direction_up(),
        amount, starting_price, spread, win_payout, expiry_time, amount, 10, 4_000_000
    );
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Advance time to expiry
    advance_time(&mut clock, 24 * 60 * 60 * 1000); // 1 day
    
    // Settle with losing price (starting_price + 1, between starting_price and starting_price + spread)
    let spot_price = starting_price + 1; // 84001 (taker loses)
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    
    // Verify settlement
    assert!(order::is_note_settled(&order_manager, note_id));
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_settle_note_refund() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000; // 2 USDC
    let win_payout = 6_000_000; // 6 USDC
    let starting_price = 84000;
    let spread = 15;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_custom_note(
        trader_1, maker_1, types::tradable_asset_btc(), types::direction_up(),
        amount, starting_price, spread, win_payout, expiry_time, amount, 10, 4_000_000
    );
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Advance time to expiry
    advance_time(&mut clock, 24 * 60 * 60 * 1000); // 1 day
    
    // Settle with refund price (below starting price)
    let spot_price = starting_price - 1; // 83999 (refund case)
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    
    // Verify settlement
    assert!(order::is_note_settled(&order_manager, note_id));
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::ENoteNotFound)]
fun test_settle_nonexistent_note_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Try to settle non-existent note
    let non_existent_note_id = 999;
    let spot_price = 84000;
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, non_existent_note_id, spot_price, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::ENoteNotExpired)]
fun test_settle_note_before_expiry_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000;
    let win_payout = 6_000_000;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Try to settle before expiry (don't advance time)
    let spot_price = 84000;
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
#[expected_failure(abort_code = order::ENoteAlreadySettled)]
fun test_settle_note_twice_fails() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Create note
    let amount = 2_000_000;
    let win_payout = 6_000_000;
    let expiry_time = timestamp_plus_days(&clock, 1);
    
    let note = create_test_note(trader_1, maker_1, amount, win_payout, expiry_time);
    
    test_scenario::next_tx(&mut scenario, coordinator);
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));
    
    // Advance time to expiry and settle
    advance_time(&mut clock, 24 * 60 * 60 * 1000);
    let spot_price = 84000;
    
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario));
    
    // Try to settle again
    test_scenario::next_tx(&mut scenario, coordinator);
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, spot_price, &clock, ctx(&mut scenario)); // Should fail
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_set_fee_percentages() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Set taker fee percentage
    let taker_fee = 50_000_000_000_000_000; // 5% (5e16 out of 1e18)
    test_scenario::next_tx(&mut scenario, governor);
    order::set_taker_fee_percentage(&order_admin_cap, &mut order_manager, taker_fee);
    
    // Set maker fee percentage
    let maker_fee = 100_000_000_000_000_000; // 10% (1e17 out of 1e18)
    test_scenario::next_tx(&mut scenario, governor);
    order::set_maker_fee_percentage(&order_admin_cap, &mut order_manager, maker_fee);
    
    // Note: We can't directly verify the fee percentages as they're internal to the fee_info structure
    // but the calls should succeed without error
    
    // Cleanup
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_taker_withdraw() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system  
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Trader should be able to withdraw unlocked funds
    let withdraw_amount = 1_000_000; // 1 USDC (trader has 5 USDC total)
    
    test_scenario::next_tx(&mut scenario, trader_1);
    let withdrawn_coin = order::taker_withdraw(&mut order_manager, &mut vault, withdraw_amount, ctx(&mut scenario));
    
    // Verify withdrawal
    assert!(coin::value(&withdrawn_coin) == withdraw_amount);
    
    // Cleanup
    coin::burn_for_testing(withdrawn_coin);
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
}

#[test]
fun test_maker_withdraw() {
    let mut scenario = setup_test_scenario();
    let (governor, trader_1, _, maker_1, _, treasury, coordinator) = get_test_addresses();
    
    // Setup complete system
    let (vault_admin_cap, order_admin_cap, coordinator_cap, maker_vault_admin_cap,
         mut vault, mut maker_vault, mut order_manager, mut clock) = test_utils::setup_funded_scenario(&mut scenario);
    
    // Maker should be able to withdraw unlocked collateral
    let withdraw_amount = 1_000_000; // 1 USDC (maker has 10 USDC total)
    let asset = types::tradable_asset_btc();
    
    test_scenario::next_tx(&mut scenario, maker_1);
    let withdrawn_coin = order::maker_withdraw(&mut order_manager, &mut maker_vault, asset, withdraw_amount, ctx(&mut scenario));
    
    // Verify withdrawal
    assert!(coin::value(&withdrawn_coin) == withdraw_amount);
    
    // Cleanup
    coin::burn_for_testing(withdrawn_coin);
    test_scenario::next_tx(&mut scenario, governor);
    transfer::public_transfer(vault_admin_cap, governor);
    transfer::public_transfer(order_admin_cap, governor);
    transfer::public_transfer(coordinator_cap, governor);
    transfer::public_transfer(maker_vault_admin_cap, governor);
    transfer::public_share_object(vault);
    transfer::public_share_object(maker_vault);
    transfer::public_share_object(order_manager);
    clock::destroy_for_testing(clock);
    
    cleanup_scenario(scenario);
} 