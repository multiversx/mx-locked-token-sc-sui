module token::bridge_token;

use sui::coin::{Self, TreasuryCap, Coin};
use sui::token::{Self, TokenPolicy, Token, TokenPolicyCap};
use token::from_coin_rule::{Self, FromCoinRule};
use token::to_coin_rule::{Self, ToCoinRule};

public struct BRIDGE_TOKEN has drop {}

public struct BRIDGE_TOKEN_MANAGER has key {
    id: UID,
    policy_cap: TokenPolicyCap<BRIDGE_TOKEN>,
    treasury_cap: TreasuryCap<BRIDGE_TOKEN>,
}

fun init(witness: BRIDGE_TOKEN, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency<BRIDGE_TOKEN>(
        witness,
        6,
        b"TKN",
        b"TKN",
        b"Our bridge token",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    let (mut policy, policy_cap) = token::new_policy<BRIDGE_TOKEN>(
        &treasury_cap,
        ctx,
    );
    token::add_rule_for_action<BRIDGE_TOKEN, ToCoinRule>(
        &mut policy,
        &policy_cap,
        token::to_coin_action(),
        ctx,
    );
    token::add_rule_for_action<BRIDGE_TOKEN, FromCoinRule>(
        &mut policy,
        &policy_cap,
        token::from_coin_action(),
        ctx,
    );

    from_coin_rule::init_config<BRIDGE_TOKEN>(
        &mut policy,
        &policy_cap,
        option::none(),
        ctx,
    );

    to_coin_rule::init_config<BRIDGE_TOKEN>(
        &mut policy,
        &policy_cap,
        option::none(),
        ctx,
    );

    let manager = BRIDGE_TOKEN_MANAGER {
        id: object::new(ctx),
        policy_cap,
        treasury_cap,
    };

    policy.share_policy();
    transfer::share_object(manager);
}

public fun mint_and_transfer(
    treasury_cap: &mut TreasuryCap<BRIDGE_TOKEN>,
    policy_cap: &mut TokenPolicyCap<BRIDGE_TOKEN>,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = treasury_cap.mint(amount, ctx);
    let (token, req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(treasury_cap, req, ctx);

    let request = token::transfer(token, recipient, ctx);
    token::confirm_with_policy_cap(policy_cap, request, ctx);
}

public fun transfer_to_coin_with_policy(
    policy: &TokenPolicy<BRIDGE_TOKEN>,
    token: Token<BRIDGE_TOKEN>,
    ctx: &mut TxContext,
) {
    let (coin, mut req) = token::to_coin(token, ctx);
    to_coin_rule::verify(&mut req, policy, ctx);

    token::confirm_request(policy, req, ctx);

    transfer::public_transfer(coin, ctx.sender());
}

public fun set_to_coin_allowed(
    policy: &mut TokenPolicy<BRIDGE_TOKEN>,
    cap: &TokenPolicyCap<BRIDGE_TOKEN>,
    allowed: address,
) {
    to_coin_rule::set_to_coin_allowed<BRIDGE_TOKEN>(policy, cap, option::some(allowed))
}

public fun set_from_coin_allowed(
    policy: &mut TokenPolicy<BRIDGE_TOKEN>,
    cap: &TokenPolicyCap<BRIDGE_TOKEN>,
    allowed: address,
) {
    from_coin_rule::set_from_coin_allowed<BRIDGE_TOKEN>(policy, cap, option::some(allowed))
}

public fun burn_coin() {}
