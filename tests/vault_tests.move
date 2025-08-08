#[test_only]
module odyssey_sui::vault_tests;

use sui::test_scenario::{Self, Scenario, ctx};
use sui::coin::{Self, Coin};
use odyssey_sui::vault::{Self, Vault, VaultAdminCap, OrderCap};
use odyssey_sui::test_utils::{Self, USDC, setup_test_scenario, mint_usdc, get_test_addresses, cleanup_scenario};
use odyssey_sui::order;
use odyssey_sui::test_utils::setup_vault;
use sui::test_utils::assert_eq;

#[test]
public fun test_initialize_success() {
    let mut scenario = setup_test_scenario();
    let (governor, _, _, _, _, _, _) = get_test_addresses();
    let (vault, order_cap) = setup_vault(&mut scenario);
    transfer::public_transfer(order_cap, governor);

    // Verify vault initialization
    test_scenario::next_tx(&mut scenario, governor);
    let total_asset = vault::total_asset_available(&vault);
    assert_eq(total_asset, 0);

    test_scenario::return_shared(vault);

    cleanup_scenario(scenario)
}
