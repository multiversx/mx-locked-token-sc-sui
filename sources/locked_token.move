module locked_token::bridge_token;

use locked_token::treasury;
use locked_token::upgrade_service_token;
use sui::coin;
use sui::token;

public struct BRIDGE_TOKEN has drop {}

#[allow(lint(share_owned))]
fun init(witness: BRIDGE_TOKEN, ctx: &mut TxContext) {
    let (upgrade_service_token, witness) = upgrade_service_token::new(
        witness,
        ctx.sender(),
        ctx,
    );

    let (treasury_cap, metadata) = coin::create_currency<BRIDGE_TOKEN>(
        witness,
        6,
        b"LXMN",
        b"LXMN",
        b"Locked representation of 0x97c7571f4406cdd7a95f3027075ab80d3e9c937c2a567690d31e14ab1872ccee::xmn::XMN",
        option::none(),
        ctx,
    );
    transfer::public_freeze_object(metadata);

    let (policy, policy_cap) = token::new_policy<BRIDGE_TOKEN>(
        &treasury_cap,
        ctx,
    );

    let t = treasury::new(
        treasury_cap,
        policy_cap,
        ctx.sender(),
        ctx,
    );

    policy.share_policy();
    transfer::public_share_object(t);
    transfer::public_share_object(upgrade_service_token);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(BRIDGE_TOKEN {}, ctx) // calls the real init that does create_currency, policy, etc.
}
