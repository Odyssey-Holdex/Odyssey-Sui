#[test_only]
module odyssey_sui::symbol_whitelist_tests;

use sui::test_scenario::{Self, ctx};
use odyssey_sui::maker_vault::{Self, MakerVaultAdminCap};
use odyssey_sui::test_utils::{
    setup_test_scenario,
    get_test_addresses,
    cleanup_scenario,
    setup_maker_vault,
    mint_ithaca,
};
use sui::test_utils::assert_eq;
use std::option::none;
use std::string;

// ==========
// Symbol Whitelist Tests
// ==========

#[test]
public fun test_register_with_allowed_symbol_succeeds() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let btc_symbol = string::utf8(b"BTC");

    // Register maker with allowed symbol (BTC is in initial list)
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, btc_symbol, ithaca_coin, ctx(&mut scenario));

    // Verify registration succeeded
    test_scenario::next_tx(&mut scenario, maker1);
    let staked = maker_vault::get_maker_staked_ithaca(&vault, maker1, btc_symbol);
    assert_eq(staked, stake_amount);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInvalidSymbol)]
public fun test_register_with_invalid_symbol_fails() {
    let mut scenario = setup_test_scenario();
    let (_, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let invalid_symbol = string::utf8(b"INVALID");

    // Try to register with a symbol not in allowed list
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, invalid_symbol, ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_admin_can_add_symbols() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let new_symbol = string::utf8(b"AAPL");

    // Check symbol is not allowed initially
    test_scenario::next_tx(&mut scenario, governor);
    let is_allowed_before = maker_vault::is_symbol_allowed(&vault, new_symbol);
    assert_eq(is_allowed_before, false);

    // Admin adds the symbol
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, new_symbol);
    scenario.return_to_sender(admin_cap);

    // Check symbol is now allowed
    test_scenario::next_tx(&mut scenario, governor);
    let is_allowed_after = maker_vault::is_symbol_allowed(&vault, new_symbol);
    assert_eq(is_allowed_after, true);

    // Now maker can register with this symbol
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, new_symbol, ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_admin_can_remove_symbols() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let btc_symbol = string::utf8(b"BTC");

    // Check BTC is allowed initially
    test_scenario::next_tx(&mut scenario, governor);
    let is_allowed_before = maker_vault::is_symbol_allowed(&vault, btc_symbol);
    assert_eq(is_allowed_before, true);

    // Admin removes the symbol
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::remove_allowed_symbol(&admin_cap, &mut vault, btc_symbol);
    scenario.return_to_sender(admin_cap);

    // Check symbol is no longer allowed
    test_scenario::next_tx(&mut scenario, governor);
    let is_allowed_after = maker_vault::is_symbol_allowed(&vault, btc_symbol);
    assert_eq(is_allowed_after, false);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
#[expected_failure(abort_code = maker_vault::EInvalidSymbol)]
public fun test_cannot_register_after_symbol_removed() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, maker1, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, maker1);

    let btc_symbol = string::utf8(b"BTC");

    // Admin removes BTC symbol
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::remove_allowed_symbol(&admin_cap, &mut vault, btc_symbol);
    scenario.return_to_sender(admin_cap);

    // Try to register with removed symbol - should fail
    test_scenario::next_tx(&mut scenario, maker1);
    let stake_amount = 500_000_000;
    let ithaca_coin = mint_ithaca(&mut scenario, maker1, stake_amount);
    maker_vault::register_maker_symbol(&mut vault, btc_symbol, ithaca_coin, ctx(&mut scenario));

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_add_symbol_twice_is_idempotent() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    let symbol = string::utf8(b"TEST");

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();

    // Add symbol first time
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, symbol);

    // Add same symbol again (should not error)
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, symbol);

    scenario.return_to_sender(admin_cap);

    // Verify symbol is allowed
    test_scenario::next_tx(&mut scenario, governor);
    let is_allowed = maker_vault::is_symbol_allowed(&vault, symbol);
    assert_eq(is_allowed, true);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_remove_nonexistent_symbol_is_safe() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    let symbol = string::utf8(b"NONEXISTENT");

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();

    // Remove symbol that doesn't exist (should not error)
    maker_vault::remove_allowed_symbol(&admin_cap, &mut vault, symbol);

    scenario.return_to_sender(admin_cap);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}

#[test]
public fun test_multiple_symbols_can_be_managed() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (mut vault, order_cap) = setup_maker_vault(&mut scenario, none());
    transfer::public_transfer(order_cap, governor);

    let aapl = string::utf8(b"AAPL");
    let tsla = string::utf8(b"TSLA");
    let googl = string::utf8(b"GOOGL");

    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap = scenario.take_from_sender<MakerVaultAdminCap>();

    // Add multiple symbols
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, aapl);
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, tsla);
    maker_vault::add_allowed_symbol(&admin_cap, &mut vault, googl);

    scenario.return_to_sender(admin_cap);

    // Verify all are allowed
    test_scenario::next_tx(&mut scenario, governor);
    assert_eq(maker_vault::is_symbol_allowed(&vault, aapl), true);
    assert_eq(maker_vault::is_symbol_allowed(&vault, tsla), true);
    assert_eq(maker_vault::is_symbol_allowed(&vault, googl), true);

    // Remove one symbol
    test_scenario::next_tx(&mut scenario, governor);
    let admin_cap2 = scenario.take_from_sender<MakerVaultAdminCap>();
    maker_vault::remove_allowed_symbol(&admin_cap2, &mut vault, tsla);
    scenario.return_to_sender(admin_cap2);

    // Verify only TSLA is removed
    test_scenario::next_tx(&mut scenario, governor);
    assert_eq(maker_vault::is_symbol_allowed(&vault, aapl), true);
    assert_eq(maker_vault::is_symbol_allowed(&vault, tsla), false);
    assert_eq(maker_vault::is_symbol_allowed(&vault, googl), true);

    test_scenario::return_shared(vault);
    cleanup_scenario(scenario)
}
