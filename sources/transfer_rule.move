module token::transfer_rule {
    use std::option;
    use sui::tx_context::TxContext;
    use sui::token::{Self as token, ActionRequest, TokenPolicy, TokenPolicyCap};

    const EWrongRecipient: u64 = 1;

    public struct TransferRule has drop {}

    public struct TransferRuleConfig has store { allowed: address }

    public fun add_config<T>(
        policy: &mut TokenPolicy<T>,
        cap: &TokenPolicyCap<T>,
        allowed: address,
        ctx: &mut TxContext
    ) {
        token::add_rule_config<T, TransferRule, TransferRuleConfig>(
            TransferRule {}, policy, cap, TransferRuleConfig { allowed }, ctx
        );
    }

    public fun update_config<T>(
        policy: &mut TokenPolicy<T>,
        cap: &TokenPolicyCap<T>,
        allowed: address
    ) {
        let cfg = token::rule_config_mut<T, TransferRule, TransferRuleConfig>(TransferRule {}, policy, cap);
        cfg.allowed = allowed;
    }

    fun allowed_addr<T>(policy: &TokenPolicy<T>): address {
        let cfg = token::rule_config<T, TransferRule, TransferRuleConfig>(TransferRule {}, policy);
        cfg.allowed
    }

    
    public fun verify<T>(
        policy: &TokenPolicy<T>,
        req: &mut ActionRequest<T>,
        ctx: &mut TxContext
    ) {
        
        let mut rec_opt = token::recipient(req);
        let to = option::extract(&mut rec_opt);
        assert!(to == allowed_addr(policy), EWrongRecipient);

        token::add_approval<T, TransferRule>(TransferRule {}, req, ctx);
    }
}