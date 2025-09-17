module token::bridge_token;

use sui::coin::{Self, TreasuryCap};
use sui::token::{Self, TokenPolicy, Token, TokenPolicyCap};
use token::from_coin_rule::{Self, FromCoinRule};
use token::to_coin_rule::{Self, ToCoinRule};

const EInvalidSender: u64 = 0;

public struct BRIDGE_TOKEN has drop {}

public struct Bridge_Token_Manager has key {
    id: UID,
    policy_cap: TokenPolicyCap<BRIDGE_TOKEN>,
    treasury_cap: TreasuryCap<BRIDGE_TOKEN>,
    safe_address: Option<address>,
    stake_address: Option<address>,
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

    let manager = Bridge_Token_Manager {
        id: object::new(ctx),
        policy_cap,
        treasury_cap,
        safe_address: option::none(),
        stake_address: option::none(),
    };

    policy.share_policy();
    transfer::share_object(manager);
}

public fun mint_and_transfer(
    manager: &mut Bridge_Token_Manager,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let coin = manager.treasury_cap.mint(amount, ctx);
    let (token, req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(&mut manager.treasury_cap, req, ctx);

    let request = token::transfer(token, recipient, ctx);
    token::confirm_with_policy_cap(&manager.policy_cap, request, ctx);
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

public fun mint_token_transfer(
    manager: &mut Bridge_Token_Manager,
    amount: u64,
    recipient: address,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    if (sender != option::borrow(&manager.safe_address)) {
        abort EInvalidSender
    };

    let coin = manager.treasury_cap.mint(amount, ctx);
    let (token, req) = token::from_coin(coin, ctx);
    token::confirm_with_treasury_cap(&mut manager.treasury_cap, req, ctx);

    let request = token::transfer(token, recipient, ctx);
    token::confirm_with_policy_cap(&manager.policy_cap, request, ctx);
}

public fun burn_token(
    manager: &mut Bridge_Token_Manager,
    token: Token<BRIDGE_TOKEN>,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    if (sender != option::borrow(&manager.stake_address)) {
        abort EInvalidSender
    };
    token::burn(&mut manager.treasury_cap, token);
}

public fun set_safe_address(manager: &mut Bridge_Token_Manager, addr: address) {
    manager.safe_address = option::some(addr);
}

public fun set_stake_address(
    manager: &mut Bridge_Token_Manager,
    addr: address,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    if (sender != option::borrow(&manager.stake_address)) {
        abort EInvalidSender
    };
    manager.stake_address = option::some(addr);
}
