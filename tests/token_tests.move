module locked_token::locked_token_tests;

use sui::balance;
use sui::coin;
use sui::event;
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils::assert_eq;
use sui::token::{Self, Token};

use locked_token::bridge_token::{Self as br, BRIDGE_TOKEN};
use locked_token::treasury::{Self as tre, Treasury, ToCoinCap, FromCoinCap};

const DEPLOYER:  address = @0xA;
const USER:      address = @0xB;
const OTHER:     address = @0xC;
const NEW_OWNER: address = @0xD;

const E: u64 = 0;

fun setup(): Scenario {
    let mut s = ts::begin(DEPLOYER);

    // Deploy the bridge token + treasury/policy, owned by DEPLOYER
    br::init_for_testing(s.ctx());

    // Treasury is shared by bridge_token::init_for_testing
    s
}

#[test]
fun owner_can_issue_caps_and_wrap_unwrap() {
    let mut s = setup();

    s.next_tx(DEPLOYER);
    {
        let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        tre::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::mint_coin_to_receiver<BRIDGE_TOKEN>(&mut t, 1_000, DEPLOYER, s.ctx());
        ts::return_shared(t);
    };

    s.next_tx(DEPLOYER);
    {
        let t   = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        let to_cap  = s.take_from_sender<ToCoinCap<BRIDGE_TOKEN>>();
        let from_cap= s.take_from_sender<FromCoinCap<BRIDGE_TOKEN>>();
        let c0      = s.take_from_sender<coin::Coin<BRIDGE_TOKEN>>();

        // Wrap coin into token (requires FromCoinCap)
        let tok: Token<BRIDGE_TOKEN> = tre::from_coin<BRIDGE_TOKEN>(&t, &from_cap, c0, s.ctx());

        // Unwrap token back to coin (requires ToCoinCap)
        let c1: coin::Coin<BRIDGE_TOKEN> = tre::to_coin<BRIDGE_TOKEN>(&t, &to_cap, tok, s.ctx());
        assert_eq(coin::value(&c1), 1_000);

        balance::destroy_for_testing(coin::into_balance(c1));

        // keep caps with sender
        s.return_to_sender(to_cap);
        s.return_to_sender(from_cap);
        ts::return_shared(t);
    };

    s.end();
}

#[test, expected_failure(abort_code = tre::ENotOwner)]
fun non_owner_cannot_issue_to_cap() {
    let mut s = setup();

    s.next_tx(OTHER);
    let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
    tre::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut t, OTHER, s.ctx());
    ts::return_shared(t);

    s.end();
}

#[test, expected_failure(abort_code = tre::ENotOwner)]
fun non_owner_cannot_mint() {
    let mut s = setup();

    s.next_tx(OTHER);
    let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
    tre::mint_coin_to_receiver<BRIDGE_TOKEN>(&mut t, 10, OTHER, s.ctx());
    ts::return_shared(t);

    s.end();
}



#[test, expected_failure(abort_code = tre::ECapNotAuthorized)]
fun to_coin_fails_after_revoke() {
    let mut s = setup();

    // Owner gives self both caps and mints some coin
    s.next_tx(DEPLOYER);
    {
        let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        tre::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::mint_coin_to_receiver<BRIDGE_TOKEN>(&mut t, 100, DEPLOYER, s.ctx());
        ts::return_shared(t);
    };

    // Convert coin -> token, then revoke ToCoinCap and try to unwrap (should abort)
    s.next_tx(DEPLOYER);
    {
        let mut t     = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        let to_cap    = s.take_from_sender<ToCoinCap<BRIDGE_TOKEN>>();
        let from_cap  = s.take_from_sender<FromCoinCap<BRIDGE_TOKEN>>();
        let coin_in   = s.take_from_sender<coin::Coin<BRIDGE_TOKEN>>();

        let tok = tre::from_coin<BRIDGE_TOKEN>(&t, &from_cap, coin_in, s.ctx());

        // Owner revokes authorization for this ToCoinCap
        let to_id = object::id(&to_cap);
        tre::revoke_authorization<BRIDGE_TOKEN>(&mut t, to_id, s.ctx());

        // Attempt to unwrap using revoked cap -> ECapNotAuthorized
        let coin = tre::to_coin<BRIDGE_TOKEN>(&t, &to_cap, tok, s.ctx());
        balance::destroy_for_testing(coin::into_balance(coin));

        s.return_to_sender(to_cap);
        s.return_to_sender(from_cap);
        ts::return_shared(t);
    };

    s.end();
}

#[test, expected_failure(abort_code = tre::ECapNotAuthorized)]
fun from_coin_fails_after_revoke() {
    let mut s = setup();

    // Owner gives self both caps and mints some coin
    s.next_tx(DEPLOYER);
    {
        let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        tre::transfer_to_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::transfer_from_coin_cap<BRIDGE_TOKEN>(&mut t, DEPLOYER, s.ctx());
        tre::mint_coin_to_receiver<BRIDGE_TOKEN>(&mut t, 50, DEPLOYER, s.ctx());
        ts::return_shared(t);
    };

    // Revoke FromCoinCap and then try to wrap a coin -> should abort
    s.next_tx(DEPLOYER);
    {
        let mut t      = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        let from_cap   = s.take_from_sender<FromCoinCap<BRIDGE_TOKEN>>();
        let coin_in    = s.take_from_sender<coin::Coin<BRIDGE_TOKEN>>();

        let from_id = object::id(&from_cap);
        tre::revoke_authorization<BRIDGE_TOKEN>(&mut t, from_id, s.ctx());

        // Attempt to wrap coin using revoked cap -> ECapNotAuthorized
        let token = tre::from_coin<BRIDGE_TOKEN>(&t, &from_cap, coin_in, s.ctx());
        token::burn_for_testing(token);

        // (unreachable)
        s.return_to_sender(from_cap);
        ts::return_shared(t);
    };

    s.end();
}

#[test]
fun two_step_ownership_transfer_works() {
    let mut s = setup();

    s.next_tx(DEPLOYER);
    {
        let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        tre::transfer_ownership<BRIDGE_TOKEN>(&mut t, NEW_OWNER, s.ctx());
        ts::return_shared(t);
    };

    s.next_tx(NEW_OWNER);
    {
        let mut t = s.take_shared<Treasury<BRIDGE_TOKEN>>();
        tre::accept_ownership<BRIDGE_TOKEN>(&mut t, s.ctx());

        // New owner should be able to mint
        tre::mint_coin_to_receiver<BRIDGE_TOKEN>(&mut t, 77, USER, s.ctx());
        ts::return_shared(t);
    };

    s.next_tx(USER);
    {
        let c = s.take_from_sender<coin::Coin<BRIDGE_TOKEN>>();
        assert_eq(coin::value(&c), 77);
        balance::destroy_for_testing(coin::into_balance(c));
    };

    s.end();
}
