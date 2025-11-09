#[test_only]
module odyssey_sui::additional_coverage_tests;

use sui::test_scenario::{Self, ctx};
use odyssey_sui::vault::{Self, VaultAdminCap};
use odyssey_sui::maker_vault::{Self, MakerVaultAdminCap};
use odyssey_sui::order::{Self, OrderAdminCap};
use odyssey_sui::types::{Self};
use odyssey_sui::test_utils::{
    setup_test_scenario,
    get_test_addresses,
    cleanup_scenario,
    setup_vault,
    setup_maker_vault,
    mint_usdc,
    mint_ithaca,
    USDC,
    ITHACA
};
use sui::test_utils::assert_eq;
use std::option::none;
use std::string;

// ==========
// Vault Helper Function Tests
// ==========

#[test]
public fun test_vault_check_balance_helper() {
    let mut scenario = setup_test_scenario();
    let (governor, trader1, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Test with zero balance
    test_scenario::next_tx(&mut scenario, trader1);
    let has_balance = vault::check_vault_balance(&vault, 100);
    assert_eq(has_balance, false);

    // Deposit some funds
    let amount = 1000;
    let usdc_coin = mint_usdc(&mut scenario, trader1, amount);
    vault::deposit(&mut vault, usdc_coin, ctx(&mut scenario));

    // Test with sufficient balance
    test_scenario::next_tx(&mut scenario, trader1);
    let has_balance = vault::check_vault_balance(&vault, 500);
    assert_eq(has_balance, true);

    // Test with exact balance
    let has_exact = vault::check_vault_balance(&vault, 1000);
    assert_eq(has_exact, true);

    // Test with insufficient balance
    let has_more = vault::check_vault_balance(&vault, 1001);
    assert_eq(has_more, false);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_vault_validate_amount_success() {
    vault::validate_amount(1);
    vault::validate_amount(100);
    vault::validate_amount(999999);
}

#[test]
#[expected_failure(abort_code = vault::ENotZeroAmount)]
public fun test_vault_validate_amount_zero_fails() {
    vault::validate_amount(0);
}

#[test]
public fun test_vault_validate_address_success() {
    let (_, trader1, trader2, _, _, _, _) = get_test_addresses();
    vault::validate_address(trader1);
    vault::validate_address(trader2);
    vault::validate_address(@0x1234);
}

#[test]
#[expected_failure(abort_code = vault::ENotZeroAddress)]
public fun test_vault_validate_address_zero_fails() {
    vault::validate_address(@0x0);
}

// ==========
// Types Module Coverage Tests
// ==========

#[test]
public fun test_types_direction_helpers() {
    let up = types::direction_up();
    let down = types::direction_down();

    assert_eq(types::is_direction_up(&up), true);
    assert_eq(types::is_direction_up(&down), false);
}

#[test]
public fun test_types_note_status_helpers() {
    let win = types::note_status_win();
    let loss = types::note_status_loss();
    let refund = types::note_status_refund();
    let almost_win = types::note_status_almost_win();

    assert_eq(types::is_note_status_win(&win), true);
    assert_eq(types::is_note_status_win(&loss), false);

    assert_eq(types::is_note_status_loss(&loss), true);
    assert_eq(types::is_note_status_loss(&win), false);

    assert_eq(types::is_note_status_refund(&refund), true);
    assert_eq(types::is_note_status_refund(&win), false);

    assert_eq(types::is_note_status_almost_win(&almost_win), true);
    assert_eq(types::is_note_status_almost_win(&win), false);
}

#[test]
public fun test_types_actor_helpers() {
    let maker = types::actor_maker();
    let taker = types::actor_taker();

    assert_eq(types::is_actor_maker(&maker), true);
    assert_eq(types::is_actor_maker(&taker), false);
}

#[test]
public fun test_types_note_creation_and_getters() {
    let (_, trader1, _, maker1, _, _, _) = get_test_addresses();
    let symbol = string::utf8(b"BTC");
    let direction = types::direction_up();

    let note = types::new_note(
        trader1,
        maker1,
        symbol,
        direction,
        1000,  // amount
        50000, // starting_price
        100,   // spread
        1800,  // win_payout
        10000, // expiry_time
        1,     // nonce
        900,   // refund_payout
        50,    // almost_win_spread
        1400,  // almost_win_payout
        5000   // start_time
    );

    assert_eq(types::note_taker(&note), trader1);
    assert_eq(types::note_maker(&note), maker1);
    assert_eq(types::note_symbol(&note), symbol);
    assert_eq(types::note_amount(&note), 1000);
    assert_eq(types::note_starting_price(&note), 50000);
    assert_eq(types::note_spread(&note), 100);
    assert_eq(types::note_win_payout(&note), 1800);
    assert_eq(types::note_expiry_time(&note), 10000);
    assert_eq(types::note_nonce(&note), 1);
    assert_eq(types::note_refund_payout(&note), 900);
    assert_eq(types::note_almost_win_spread(&note), 50);
    assert_eq(types::note_almost_win_payout(&note), 1400);
    assert_eq(types::note_start_time(&note), 5000);
}

#[test]
public fun test_types_maker_info_operations() {
    let mut maker_info = types::new_maker_info(1000);

    assert_eq(types::maker_info_staked_tokens(&maker_info), 1000);
    assert_eq(types::maker_info_collateral(&maker_info), 0);

    // Test set_maker_collateral
    types::set_maker_collateral(&mut maker_info, 500);
    assert_eq(types::maker_info_collateral(&maker_info), 500);

    // Test add_maker_collateral
    types::add_maker_collateral(&mut maker_info, 300);
    assert_eq(types::maker_info_collateral(&maker_info), 800);

    // Test subtract_maker_collateral
    types::subtract_maker_collateral(&mut maker_info, 200);
    assert_eq(types::maker_info_collateral(&maker_info), 600);

    // Test add_staked_tokens
    types::add_staked_tokens(&mut maker_info, 500);
    assert_eq(types::maker_info_staked_tokens(&maker_info), 1500);
}

#[test]
public fun test_types_settlement_info() {
    let _settlement = types::new_settlement_info(50000, 10000);
    // Settlement info doesn't have public getters, but we can create it
    // This tests the constructor
}

#[test]
public fun test_types_fee_info() {
    let fee_info = types::new_fee_info(100, 50);

    assert_eq(types::fee_info_taker_percentage(&fee_info), 100);
    assert_eq(types::fee_info_maker_percentage(&fee_info), 50);
    assert_eq(types::fee_info_max_percentage(&fee_info), 10000);
    assert_eq(types::max_fee_percentage(), 10000);
}

// ==========
// Maker Vault Additional Tests
// ==========

#[test]
public fun test_maker_vault_key_creation() {
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let symbol = string::utf8(b"BTC");

    // Test that we can create keys - they're used internally
    // This is tested implicitly through deposit/withdraw operations
    let mut scenario = setup_test_scenario();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    // Register maker
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, symbol, ithaca_coin, ctx(&mut scenario));

    // Deposit collateral
    test_scenario::next_tx(&mut scenario, maker1);
    let collateral_amount = 1000;
    let usdc_coin = mint_usdc(&mut scenario, maker1, collateral_amount);
    maker_vault::deposit_collateral(&mut vault, symbol, usdc_coin, ctx(&mut scenario));

    // Verify the maker exists for this symbol
    test_scenario::next_tx(&mut scenario, maker1);
    let balance = maker_vault::get_maker_collateral(&vault, maker1, symbol);
    assert_eq(balance, collateral_amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_total_collateral_view() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let symbol = string::utf8(b"BTC");

    // Register maker
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, symbol, ithaca_coin, ctx(&mut scenario));

    // Check total collateral before deposit
    test_scenario::next_tx(&mut scenario, maker1);
    let total_before = maker_vault::total_asset_available(&vault);
    assert_eq(total_before, 0);

    // Deposit collateral
    test_scenario::next_tx(&mut scenario, maker1);
    let collateral_amount = 2000;
    let usdc_coin = mint_usdc(&mut scenario, maker1, collateral_amount);
    maker_vault::deposit_collateral(&mut vault, symbol, usdc_coin, ctx(&mut scenario));

    // Check total collateral after deposit
    test_scenario::next_tx(&mut scenario, maker1);
    let total_after = maker_vault::total_asset_available(&vault);
    assert_eq(total_after, collateral_amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_get_staked_tokens() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let symbol = string::utf8(b"ETH");

    // Check staked tokens before registration
    test_scenario::next_tx(&mut scenario, maker1);
    let staked_before = maker_vault::get_maker_staked_ithaca(&vault, maker1, symbol);
    assert_eq(staked_before, 0);

    // Register maker
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 300_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, symbol, ithaca_coin, ctx(&mut scenario));

    // Check staked tokens after registration
    test_scenario::next_tx(&mut scenario, maker1);
    let staked_after = maker_vault::get_maker_staked_ithaca(&vault, maker1, symbol);
    assert_eq(staked_after, stake_amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_get_minimum_stake() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    maker_vault::test_init(ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let default_min = 200_000_000;
    let mut initial_symbols = vector::empty<string::String>();
    vector::push_back(&mut initial_symbols, string::utf8(b"BTC"));
    let order_cap = maker_vault::initialize<USDC, ITHACA>(&admin_cap, default_min, initial_symbols, ctx(&mut scenario));
    scenario.return_to_sender(admin_cap);
    transfer::public_transfer(order_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let vault = scenario.take_shared<maker_vault::MakerVault<USDC, ITHACA>>();

    // Check default minimum stake
    let min_stake = maker_vault::minimum_stake_amount(&vault);
    assert_eq(min_stake, default_min);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_set_custom_minimum_stake() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    let symbol = string::utf8(b"BTC");

    // Set custom minimum
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let custom_amount = 500_000_000;
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut vault, symbol, custom_amount);
    scenario.return_to_sender(admin_cap);

    // Test that custom minimum is respected (indirectly through registration)
    // This is already tested in maker_vault_tests, so we just verify the setter works

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

// ==========
// Order Module Additional Tests
// ==========

#[test]
public fun test_order_get_note_count() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    vault::test_init(ctx(&mut scenario));
    maker_vault::test_init(ctx(&mut scenario));
    order::test_init(ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, governor);
    let vault_admin_cap = scenario.take_from_sender<VaultAdminCap>();
    let vault_order_cap = vault::initialize<USDC>(&vault_admin_cap, ctx(&mut scenario));
    scenario.return_to_sender(vault_admin_cap);

    test_scenario::next_tx(&mut scenario, governor);
    let maker_admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let mut initial_symbols = vector::empty<string::String>();
    vector::push_back(&mut initial_symbols, string::utf8(b"BTC"));
    let maker_order_cap = maker_vault::initialize<USDC, ITHACA>(&maker_admin_cap, 200_000_000, initial_symbols, ctx(&mut scenario));
    scenario.return_to_sender(maker_admin_cap);

    test_scenario::next_tx(&mut scenario, governor);
    let order_admin_cap = scenario.take_from_sender<OrderAdminCap>();
    let (_, treasury, _, _, _, _, _) = get_test_addresses();
    let coordinator_cap = order::initialize<USDC>(&order_admin_cap, vault_order_cap, maker_order_cap, treasury, ctx(&mut scenario));
    scenario.return_to_sender(order_admin_cap);
    transfer::public_transfer(coordinator_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let order_manager = scenario.take_shared<order::OrderManager<USDC>>();

    // Check note count (should be 0)
    let count = order::note_counter(&order_manager);
    assert_eq(count, 0);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_order_get_treasury() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, treasury, _) = get_test_addresses();

    test_scenario::next_tx(&mut scenario, governor);
    vault::test_init(ctx(&mut scenario));
    maker_vault::test_init(ctx(&mut scenario));
    order::test_init(ctx(&mut scenario));

    test_scenario::next_tx(&mut scenario, governor);
    let vault_admin_cap = scenario.take_from_sender<VaultAdminCap>();
    let vault_order_cap = vault::initialize<USDC>(&vault_admin_cap, ctx(&mut scenario));
    scenario.return_to_sender(vault_admin_cap);

    test_scenario::next_tx(&mut scenario, governor);
    let maker_admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    let mut initial_symbols = vector::empty<string::String>();
    vector::push_back(&mut initial_symbols, string::utf8(b"BTC"));
    let maker_order_cap = maker_vault::initialize<USDC, ITHACA>(&maker_admin_cap, 200_000_000, initial_symbols, ctx(&mut scenario));
    scenario.return_to_sender(maker_admin_cap);

    test_scenario::next_tx(&mut scenario, governor);
    let order_admin_cap = scenario.take_from_sender<OrderAdminCap>();
    let coordinator_cap = order::initialize<USDC>(&order_admin_cap, vault_order_cap, maker_order_cap, treasury, ctx(&mut scenario));
    scenario.return_to_sender(order_admin_cap);
    transfer::public_transfer(coordinator_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let order_manager = scenario.take_shared<order::OrderManager<USDC>>();

    // Check treasury address
    let treasury_addr = order::treasury(&order_manager);
    assert_eq(treasury_addr, treasury);

    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_order_validate_address_success() {
    let (_, trader1, trader2, _, _, _, _) = get_test_addresses();
    order::validate_address(trader1);
    order::validate_address(trader2);
    order::validate_address(@0x1234);
}

#[test]
#[expected_failure(abort_code = order::ENotZeroAddress)]
public fun test_order_validate_address_zero_fails() {
    order::validate_address(@0x0);
}

// ==========
// Additional View Function Tests
// ==========

#[test]
public fun test_vault_taker_balance_for_nonexistent_taker() {
    let mut scenario = setup_test_scenario();
    let (governor, trader1, _, _, _, _, _) = get_test_addresses();
    let (vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Check balance for a taker who never deposited
    test_scenario::next_tx(&mut scenario, trader1);
    let balance = vault::taker_balance(&vault, trader1);
    assert_eq(balance, 0);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_ithaca_balance() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let symbol = string::utf8(b"BTC");

    // Check ithaca balance before registration
    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_before = maker_vault::vault_ithaca_balance_value(&vault);
    assert_eq(ithaca_before, 0);

    // Register maker
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, symbol, ithaca_coin, ctx(&mut scenario));

    // Check ithaca balance after registration
    test_scenario::next_tx(&mut scenario, maker1);
    let ithaca_after = maker_vault::vault_ithaca_balance_value(&vault);
    assert_eq(ithaca_after, stake_amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_maker_vault_get_maker_collateral_for_nonexistent() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let symbol = string::utf8(b"ETH");

    // Check collateral for a maker who never registered
    test_scenario::next_tx(&mut scenario, maker1);
    let collateral = maker_vault::get_maker_collateral(&vault, maker1, symbol);
    assert_eq(collateral, 0);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

// ==========
// Additional Order Module Tests for Coverage
// ==========

#[test]
public fun test_order_get_note_and_is_note_settled() {
    use odyssey_sui::test_utils::{
        setup_funded_scenario,
        deposit_trader_funds,
        create_test_note,
        timestamp_plus_days,
        create_test_clock
    };
    use odyssey_sui::order::CoordinatorCap;

    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader
    let amount = 1_000_000_000; // 1 USDC
    let win_payout = amount * 2;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    // Create a note
    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));

    // Test get_note
    let retrieved_note = order::get_note(&order_manager, note_id);
    assert_eq(types::note_amount(retrieved_note), amount);
    assert_eq(types::note_taker(retrieved_note), trader1);
    assert_eq(types::note_maker(retrieved_note), maker1);

    // Test is_note_settled before settlement
    let is_settled_before = order::is_note_settled(&order_manager, note_id);
    assert_eq(is_settled_before, false);

    // Settle the note
    let settle_clock = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, 90000, &settle_clock, ctx(&mut scenario));

    // Test is_note_settled after settlement
    let is_settled_after = order::is_note_settled(&order_manager, note_id);
    assert_eq(is_settled_after, true);

    transfer::public_transfer(coordinator_cap, coordinator);
    clock.destroy_for_testing();
    settle_clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = order::ENoteNotFound)]
public fun test_order_get_note_fails_for_nonexistent() {
    use odyssey_sui::test_utils::setup_complete_system;

    let mut scenario = setup_test_scenario();
    let (vault, maker_vault, order_manager) = setup_complete_system(&mut scenario, none(), none());

    // Try to get a note that doesn't exist
    test_scenario::next_tx(&mut scenario, @0x1);
    let _note = order::get_note(&order_manager, 999);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_order_is_note_settled_returns_false_for_nonexistent() {
    use odyssey_sui::test_utils::setup_complete_system;

    let mut scenario = setup_test_scenario();
    let (vault, maker_vault, order_manager) = setup_complete_system(&mut scenario, none(), none());

    // Check if non-existent note is settled (should return false)
    test_scenario::next_tx(&mut scenario, @0x1);
    let is_settled = order::is_note_settled(&order_manager, 999);
    assert_eq(is_settled, false);

    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

// ==========
// Additional Types Module Tests for Coverage
// ==========

#[test]
public fun test_types_note_status_comprehensive() {
    // Test all combinations to increase coverage of is_note_status_almost_win and is_note_status_refund
    let win = types::note_status_win();
    let loss = types::note_status_loss();
    let refund = types::note_status_refund();
    let almost_win = types::note_status_almost_win();

    // Test is_note_status_almost_win with all status types
    assert_eq(types::is_note_status_almost_win(&almost_win), true);
    assert_eq(types::is_note_status_almost_win(&win), false);
    assert_eq(types::is_note_status_almost_win(&loss), false);
    assert_eq(types::is_note_status_almost_win(&refund), false);

    // Test is_note_status_refund with all status types
    assert_eq(types::is_note_status_refund(&refund), true);
    assert_eq(types::is_note_status_refund(&win), false);
    assert_eq(types::is_note_status_refund(&loss), false);
    assert_eq(types::is_note_status_refund(&almost_win), false);
}

// ==========
// Maker/Taker Withdrawable Balance Tests
// ==========

#[test]
public fun test_order_maker_withdrawable_balance() {
    use odyssey_sui::test_utils::{
        setup_funded_scenario,
        deposit_trader_funds,
        create_test_note,
        timestamp_plus_days,
        create_test_clock
    };
    use odyssey_sui::order::CoordinatorCap;

    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader and create note
    let amount = 1_000_000_000; // 1 USDC
    let win_payout = amount * 2;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));

    // Settle note as loss (maker wins)
    let settle_clock = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, 70000, &settle_clock, ctx(&mut scenario));

    // Check maker withdrawable balance after settlement
    let withdrawable = order::maker_withdrawable_balance(&order_manager, &maker_vault, maker1, string::utf8(b"BTC"));
    assert!(withdrawable > 0, 0);

    transfer::public_transfer(coordinator_cap, coordinator);
    clock.destroy_for_testing();
    settle_clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

#[test]
public fun test_order_taker_withdrawable_balance() {
    use odyssey_sui::test_utils::{
        setup_funded_scenario,
        deposit_trader_funds,
        create_test_note,
        timestamp_plus_days,
        create_test_clock
    };
    use odyssey_sui::order::CoordinatorCap;

    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _, _) = setup_funded_scenario(&mut scenario, none());
    let (_, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Fund trader and create note
    let amount = 1_000_000_000; // 1 USDC
    let win_payout = amount * 2;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount);

    let note = create_test_note(trader1, maker1, amount, win_payout, 2);

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note, &clock, ctx(&mut scenario));

    // Settle note as win (taker wins)
    let settle_clock = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id, 90000, &settle_clock, ctx(&mut scenario));

    // Check taker withdrawable balance after settlement
    let withdrawable = order::taker_withdrawable_balance(&order_manager, &vault, trader1);
    assert!(withdrawable > 0, 0);

    transfer::public_transfer(coordinator_cap, coordinator);
    clock.destroy_for_testing();
    settle_clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

// ==========
// Additional View Functions Tests
// ==========

#[test]
public fun test_vault_total_asset_available() {
    let mut scenario = setup_test_scenario();
    let (governor, trader1, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Check total before deposits
    test_scenario::next_tx(&mut scenario, trader1);
    let total_before = vault::total_asset_available(&vault);
    assert_eq(total_before, 0);

    // Deposit from trader1
    let amount1 = 1000;
    let usdc_coin1 = mint_usdc(&mut scenario, trader1, amount1);
    vault::deposit(&mut vault, usdc_coin1, ctx(&mut scenario));

    // Check total after first deposit
    test_scenario::next_tx(&mut scenario, trader1);
    let total_after1 = vault::total_asset_available(&vault);
    assert_eq(total_after1, amount1);

    // Deposit from another trader
    let (_, _, trader2, _, _, _, _) = get_test_addresses();
    test_scenario::next_tx(&mut scenario, trader2);
    let amount2 = 2000;
    let usdc_coin2 = mint_usdc(&mut scenario, trader2, amount2);
    vault::deposit(&mut vault, usdc_coin2, ctx(&mut scenario));

    // Check total after both deposits
    test_scenario::next_tx(&mut scenario, trader2);
    let total_after2 = vault::total_asset_available(&vault);
    assert_eq(total_after2, amount1 + amount2);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

// ==========
// Settlement Tests to Cover Transfer Functions
// ==========

#[test]
public fun test_settlement_with_fees_covers_transfer_functions() {
    use odyssey_sui::test_utils::{
        setup_funded_scenario,
        deposit_trader_funds,
        timestamp_plus_days,
        create_test_clock,
        get_btc_symbol
    };
    use odyssey_sui::order::{CoordinatorCap, OrderAdminCap};

    let mut scenario = setup_test_scenario();
    let (mut vault, mut maker_vault, mut order_manager, clock, _, _) = setup_funded_scenario(&mut scenario, none());
    let (governor, trader1, _, maker1, _, _, coordinator) = get_test_addresses();

    // Set fee percentages to trigger fee transfer code
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<OrderAdminCap>();
    order::set_taker_fee_percentage(&admin_cap, &mut order_manager, 200); // 2%
    order::set_maker_fee_percentage(&admin_cap, &mut order_manager, 100); // 1%
    scenario.return_to_sender(admin_cap);

    // Fund trader and create multiple notes with different outcomes
    let amount1 = 10_000_000_000; // 10 USDC
    let win_payout1 = amount1 * 2;
    deposit_trader_funds(&mut scenario, &mut vault, trader1, amount1 * 5);

    // Create and settle note as WIN
    let note1 = types::new_note(
        trader1, maker1, get_btc_symbol(), types::direction_up(),
        amount1, 84000, 500, win_payout1,
        timestamp_plus_days(&clock, 2), 0, amount1 - 100, 200, amount1 + 5000, 1
    );

    test_scenario::next_tx(&mut scenario, coordinator);
    let coordinator_cap = scenario.take_from_sender<CoordinatorCap>();
    let note_id1 = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note1, &clock, ctx(&mut scenario));

    let settle_clock1 = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id1, 85000, &settle_clock1, ctx(&mut scenario));
    settle_clock1.destroy_for_testing();

    // Create and settle note as LOSS
    let amount2 = 5_000_000_000; // 5 USDC
    let win_payout2 = amount2 * 2;
    let note2 = types::new_note(
        trader1, maker1, get_btc_symbol(), types::direction_down(),
        amount2, 84000, 500, win_payout2,
        timestamp_plus_days(&clock, 2), 1, amount2 - 100, 200, amount2 + 3000, 1
    );

    let note_id2 = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note2, &clock, ctx(&mut scenario));

    let settle_clock2 = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id2, 85000, &settle_clock2, ctx(&mut scenario));
    settle_clock2.destroy_for_testing();

    // Create and settle note as REFUND
    let amount3 = 3_000_000_000; // 3 USDC
    let win_payout3 = amount3 * 2;
    let note3 = types::new_note(
        trader1, maker1, get_btc_symbol(), types::direction_up(),
        amount3, 84000, 500, win_payout3,
        timestamp_plus_days(&clock, 2), 2, amount3 - 100, 200, amount3 + 2000, 1
    );

    let note_id3 = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note3, &clock, ctx(&mut scenario));

    let settle_clock3 = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id3, 84000, &settle_clock3, ctx(&mut scenario));
    settle_clock3.destroy_for_testing();

    // Create and settle note as ALMOST_WIN
    let amount4 = 2_000_000_000; // 2 USDC
    let win_payout4 = amount4 * 2;
    let almost_win_payout4 = amount4 + 1_000_000_000; // 1.5x
    let note4 = types::new_note(
        trader1, maker1, get_btc_symbol(), types::direction_up(),
        amount4, 84000, 500, win_payout4,
        timestamp_plus_days(&clock, 2), 3, amount4 - 100, 200, almost_win_payout4, 1
    );

    let note_id4 = order::create_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note4, &clock, ctx(&mut scenario));

    let settle_clock4 = create_test_clock(&mut scenario, timestamp_plus_days(&clock, 3));
    order::settle_note(&coordinator_cap, &mut order_manager, &mut vault, &mut maker_vault, note_id4, 84200, &settle_clock4, ctx(&mut scenario));
    settle_clock4.destroy_for_testing();

    transfer::public_transfer(coordinator_cap, coordinator);
    clock.destroy_for_testing();
    test_scenario::return_shared(vault);
    test_scenario::return_shared(maker_vault);
    test_scenario::return_shared(order_manager);
    cleanup_scenario(scenario)
}

// ==========
// Additional tests for set_minimum_stake
// ==========

#[test]
public fun test_set_minimum_stake_amount_multiple_times() {
    use odyssey_sui::maker_vault::{MakerVaultAdminCap};

    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    // Set minimum stake multiple times
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();

    maker_vault::set_minimum_stake_amount(&admin_cap, &mut vault, 300_000_000);
    let min1 = maker_vault::minimum_stake_amount(&vault);
    assert_eq(min1, 300_000_000);

    maker_vault::set_minimum_stake_amount(&admin_cap, &mut vault, 400_000_000);
    let min2 = maker_vault::minimum_stake_amount(&vault);
    assert_eq(min2, 400_000_000);

    maker_vault::set_minimum_stake_amount(&admin_cap, &mut vault, 250_000_000);
    let min3 = maker_vault::minimum_stake_amount(&vault);
    assert_eq(min3, 250_000_000);

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_custom_minimum_stake_for_multiple_symbols() {
    use odyssey_sui::maker_vault::{MakerVaultAdminCap};

    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();

    // Set custom minimums for different symbols
    let btc_symbol = string::utf8(b"BTC");
    let eth_symbol = string::utf8(b"ETH");
    let sol_symbol = string::utf8(b"SOL");

    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut vault, btc_symbol, 600_000_000);
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut vault, eth_symbol, 400_000_000);
    maker_vault::set_custom_min_stake_amount(&admin_cap, &mut vault, sol_symbol, 200_000_000);

    // Verify get_min_stake_amount returns custom values
    let btc_min = maker_vault::get_min_stake_amount(&vault, btc_symbol);
    let eth_min = maker_vault::get_min_stake_amount(&vault, eth_symbol);
    let sol_min = maker_vault::get_min_stake_amount(&vault, sol_symbol);

    assert_eq(btc_min, 600_000_000);
    assert_eq(eth_min, 400_000_000);
    assert_eq(sol_min, 200_000_000);

    scenario.return_to_sender(admin_cap);
    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}
