module token::bridge_token;

use sui::coin;
use sui::token;
use token::treasury;


public struct BRIDGE_TOKEN has drop {}

#[allow(lint(share_owned))]
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

    let (policy, policy_cap) = token::new_policy<BRIDGE_TOKEN>(
        &treasury_cap,
        ctx,
    );

    let t = treasury::new(
        treasury_cap, 
        policy_cap,
        ctx.sender(),
        ctx
    );

    policy.share_policy();
    transfer::public_share_object(t);
}

