// docs:start:token_all
// docs:start:imports
mod types;
mod test;

use dep::aztec::macros::aztec;

// Minimal token implementation that supports `AuthWit` accounts.
// The auth message follows a similar pattern to the cross-chain message and includes a designated caller.
// The designated caller is ALWAYS used here, and not based on a flag as cross-chain.
// message hash = H([caller, contract, selector, ...args])
// To be read as `caller` calls function at `contract` defined by `selector` with `args`
// Including a nonce in the message hash ensures that the message can only be used once.
#[aztec]
contract Token {
    // Libs
    use std::meta::derive;

    use dep::compressed_string::FieldCompressedString;

    use dep::aztec::{
        context::{PrivateCallInterface, PrivateContext},
        encrypted_logs::{
            encrypted_event_emission::encode_and_encrypt_event_unconstrained,
            encrypted_note_emission::{
                encode_and_encrypt_note, encode_and_encrypt_note_unconstrained,
            },
        },
        hash::compute_secret_hash,
        keys::getters::get_public_keys,
        macros::{
            events::event,
            functions::{initializer, internal, private, public, view},
            storage::storage,
        },
        oracle::random::random,
        prelude::{
            AztecAddress, FunctionSelector, Map, NoteGetterOptions, PrivateSet, PublicMutable,
            SharedImmutable,
        },
        protocol_types::{point::Point, traits::Serialize},
        utils::comparison::Comparator,
    };

    use dep::uint_note::uint_note::UintNote;

    // docs:start:import_authwit
    use dep::authwit::auth::{
        assert_current_call_valid_authwit, assert_current_call_valid_authwit_public,
        compute_authwit_nullifier,
    };
    // docs:end:import_authwit

    use crate::types::{balance_set::BalanceSet, transparent_note::TransparentNote};

    // docs:end::imports

    // In the first transfer iteration we are computing a lot of additional information (validating inputs, retrieving
    // keys, etc.), so the gate count is already relatively high. We therefore only read a few notes to keep the happy
    // case with few constraints.
    global INITIAL_TRANSFER_CALL_MAX_NOTES: u32 = 2;
    // All the recursive call does is nullify notes, meaning the gate count is low, but it is all constant overhead. We
    // therefore read more notes than in the base case to increase the efficiency of the overhead, since this results in
    // an overall small circuit regardless.
    global RECURSIVE_TRANSFER_CALL_MAX_NOTES: u32 = 8;

    #[derive(Serialize)]
    #[event]
    struct Transfer {
        from: AztecAddress,
        to: AztecAddress,
        amount: Field,
    }

    // docs:start:storage_struct
    #[storage]
    struct Storage<Context> {
        // docs:start:storage_admin
        admin: PublicMutable<AztecAddress, Context>,
        // docs:end:storage_admin
        // docs:start:storage_minters
        minters: Map<AztecAddress, PublicMutable<bool, Context>, Context>,
        // docs:end:storage_minters
        // docs:start:storage_balances
        balances: Map<AztecAddress, BalanceSet<Context>, Context>,
        // docs:end:storage_balances
        total_supply: PublicMutable<U128, Context>,
        // docs:start:storage_pending_shields
        pending_shields: PrivateSet<TransparentNote, Context>,
        // docs:end:storage_pending_shields
        public_balances: Map<AztecAddress, PublicMutable<U128, Context>, Context>,
        symbol: SharedImmutable<FieldCompressedString, Context>,
        name: SharedImmutable<FieldCompressedString, Context>,
        // docs:start:storage_decimals
        decimals: SharedImmutable<u8, Context>,
        // docs:end:storage_decimals
    }
    // docs:end:storage_struct

    // docs:start:constructor
    #[public]
    #[initializer]
    fn constructor(admin: AztecAddress, name: str<31>, symbol: str<31>, decimals: u8) {
        assert(!admin.is_zero(), "invalid admin");
        storage.admin.write(admin);
        storage.minters.at(admin).write(true);
        storage.name.initialize(FieldCompressedString::from_string(name));
        storage.symbol.initialize(FieldCompressedString::from_string(symbol));
        // docs:start:initialize_decimals
        storage.decimals.initialize(decimals);
        // docs:end:initialize_decimals
    }
    // docs:end:constructor
    // docs:start:set_admin
    #[public]
    fn set_admin(new_admin: AztecAddress) {
        assert(storage.admin.read().eq(context.msg_sender()), "caller is not admin");
        // docs:start:write_admin
        storage.admin.write(new_admin);
        // docs:end:write_admin
    }
    // docs:end:set_admin
    #[public]
    #[view]
    fn public_get_name() -> FieldCompressedString {
        storage.name.read_public()
    }

    #[private]
    #[view]
    fn private_get_name() -> FieldCompressedString {
        storage.name.read_private()
    }
    #[public]
    #[view]
    fn public_get_symbol() -> pub FieldCompressedString {
        storage.symbol.read_public()
    }
    #[private]
    #[view]
    fn private_get_symbol() -> pub FieldCompressedString {
        storage.symbol.read_private()
    }
    #[public]
    #[view]
    fn public_get_decimals() -> pub u8 {
        // docs:start:read_decimals_public
        storage.decimals.read_public()
        // docs:end:read_decimals_public
    }
    #[private]
    #[view]
    fn private_get_decimals() -> pub u8 {
        // docs:start:read_decimals_private
        storage.decimals.read_private()
        // docs:end:read_decimals_private
    }
    // docs:start:admin
    #[public]
    #[view]
    fn get_admin() -> Field {
        storage.admin.read().to_field()
    }
    // docs:end:admin
    // docs:start:is_minter
    #[public]
    #[view]
    fn is_minter(minter: AztecAddress) -> bool {
        storage.minters.at(minter).read()
    }
    // docs:end:is_minter
    // docs:start:total_supply
    #[public]
    #[view]
    fn total_supply() -> Field {
        storage.total_supply.read().to_integer()
    }
    // docs:end:total_supply
    // docs:start:balance_of_public
    #[public]
    #[view]
    fn balance_of_public(owner: AztecAddress) -> Field {
        storage.public_balances.at(owner).read().to_integer()
    }
    // docs:end:balance_of_public
    // docs:start:set_minter
    #[public]
    fn set_minter(minter: AztecAddress, approve: bool) {
        // docs:start:read_admin
        assert(storage.admin.read().eq(context.msg_sender()), "caller is not admin");
        // docs:end:read_admin
        // docs:start:write_minter
        storage.minters.at(minter).write(approve);
        // docs:end:write_minter
    }
    // docs:end:set_minter
    // docs:start:mint_public
    #[public]
    fn mint_public(to: AztecAddress, amount: Field) {
        // docs:start:read_minter
        assert(storage.minters.at(context.msg_sender()).read(), "caller is not minter");
        // docs:end:read_minter
        let amount = U128::from_integer(amount);
        let new_balance = storage.public_balances.at(to).read().add(amount);
        let supply = storage.total_supply.read().add(amount);
        storage.public_balances.at(to).write(new_balance);
        storage.total_supply.write(supply);
    }
    // docs:end:mint_public
    // docs:start:mint_private
    #[public]
    fn mint_private(amount: Field, secret_hash: Field) {
        assert(storage.minters.at(context.msg_sender()).read(), "caller is not minter");
        let pending_shields = storage.pending_shields;
        let mut note = TransparentNote::new(amount, secret_hash);
        let supply = storage.total_supply.read().add(U128::from_integer(amount));
        storage.total_supply.write(supply);
        // docs:start:insert_from_public
        pending_shields.insert_from_public(&mut note);
        // docs:end:insert_from_public
    }
    // docs:end:mint_private
    // TODO: Nuke this - test functions do not belong to token contract!
    #[private]
    fn privately_mint_private_note(amount: Field) {
        let caller = context.msg_sender();
        let caller_ovpk_m = get_public_keys(caller).ovpk_m;
        storage.balances.at(caller).add(caller, U128::from_integer(amount)).emit(
            encode_and_encrypt_note(&mut context, caller_ovpk_m, caller),
        );
        Token::at(context.this_address())
            .assert_minter_and_mint(context.msg_sender(), amount)
            .enqueue(&mut context);
    }
    #[public]
    #[internal]
    fn assert_minter_and_mint(minter: AztecAddress, amount: Field) {
        assert(storage.minters.at(minter).read(), "caller is not minter");
        let supply = storage.total_supply.read() + U128::from_integer(amount);
        storage.total_supply.write(supply);
    }
    // docs:start:shield
    #[public]
    fn shield(from: AztecAddress, amount: Field, secret_hash: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            // The redeem is only spendable once, so we need to ensure that you cannot insert multiple shields from the same message.
            assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        let amount = U128::from_integer(amount);
        let from_balance = storage.public_balances.at(from).read().sub(amount);
        let pending_shields = storage.pending_shields;
        let mut note = TransparentNote::new(amount.to_field(), secret_hash);
        storage.public_balances.at(from).write(from_balance);
        pending_shields.insert_from_public(&mut note);
    }
    // docs:end:shield
    // docs:start:transfer_public
    #[public]
    fn transfer_public(from: AztecAddress, to: AztecAddress, amount: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        let amount = U128::from_integer(amount);
        let from_balance = storage.public_balances.at(from).read().sub(amount);
        storage.public_balances.at(from).write(from_balance);
        let to_balance = storage.public_balances.at(to).read().add(amount);
        storage.public_balances.at(to).write(to_balance);
    }
    // docs:end:transfer_public
    // docs:start:burn_public
    #[public]
    fn burn_public(from: AztecAddress, amount: Field, nonce: Field) {
        // docs:start:assert_current_call_valid_authwit_public
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit_public(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        // docs:end:assert_current_call_valid_authwit_public
        let amount = U128::from_integer(amount);
        let from_balance = storage.public_balances.at(from).read().sub(amount);
        storage.public_balances.at(from).write(from_balance);
        let new_supply = storage.total_supply.read().sub(amount);
        storage.total_supply.write(new_supply);
    }
    // docs:end:burn_public
    // docs:start:redeem_shield
    #[private]
    fn redeem_shield(to: AztecAddress, amount: Field, secret: Field) {
        let secret_hash = compute_secret_hash(secret);
        // Pop 1 note (set_limit(1)) which has an amount stored in a field with index 0 (select(0, amount)) and
        // a secret_hash stored in a field with index 1 (select(1, secret_hash)).
        let mut options = NoteGetterOptions::new();
        options = options
            .select(TransparentNote::properties().amount, Comparator.EQ, amount)
            .select(TransparentNote::properties().secret_hash, Comparator.EQ, secret_hash)
            .set_limit(1);
        let notes = storage.pending_shields.pop_notes(options);
        assert(notes.len() == 1, "note not popped");
        // Add the token note to user's balances set
        // Note: Using context.msg_sender() as a sender below makes this incompatible with escrows because we send
        // outgoing logs to that address and to send outgoing logs you need to get a hold of ovsk_m.
        let from = context.msg_sender();
        let from_ovpk_m = get_public_keys(from).ovpk_m;
        storage.balances.at(to).add(to, U128::from_integer(amount)).emit(encode_and_encrypt_note(
            &mut context,
            from_ovpk_m,
            to,
        ));
    }
    // docs:end:redeem_shield
    // docs:start:unshield
    #[private]
    fn unshield(from: AztecAddress, to: AztecAddress, amount: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }

        let from_ovpk_m = get_public_keys(from).ovpk_m;
        // TODO: constrain encryption below - we are using unconstrained here only becuase of the following Noir issue
        // https://github.com/noir-lang/noir/issues/5771
        storage.balances.at(from).sub(from, U128::from_integer(amount)).emit(
            encode_and_encrypt_note_unconstrained(&mut context, from_ovpk_m, from),
        );
        Token::at(context.this_address())._increase_public_balance(to, amount).enqueue(&mut context);
    }
    // docs:end:unshield
    // docs:start:transfer
    #[private]
    fn transfer(to: AztecAddress, amount: Field) {
        let from = context.msg_sender();

        let from_ovpk_m = get_public_keys(from).ovpk_m;

        let amount = U128::from_integer(amount);
        // We reduce `from`'s balance by amount by recursively removing notes over potentially multiple calls. This
        // method keeps the gate count for each individual call low - reading too many notes at once could result in
        // circuits in which proving is not feasible.
        // Since the sum of the amounts in the notes we nullified was potentially larger than amount, we create a new
        // note for `from` with the change amount, e.g. if `amount` is 10 and two notes are nullified with amounts 8 and
        // 5, then the change will be 3 (since 8 + 5 - 10 = 3).
        let change = subtract_balance(
            &mut context,
            storage,
            from,
            amount,
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );
        storage.balances.at(from).add(from, change).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            from_ovpk_m,
            from,
        ));
        storage.balances.at(to).add(to, amount).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            from_ovpk_m,
            to,
        ));
        // We don't constrain encryption of the note log in `transfer` (unlike in `transfer_from`) because the transfer
        // function is only designed to be used in situations where the event is not strictly necessary (e.g. payment to
        // another person where the payment is considered to be successful when the other party successfully decrypts a
        // note).
        Transfer { from, to, amount: amount.to_field() }.emit(
            encode_and_encrypt_event_unconstrained(&mut context, from_ovpk_m, to),
        );
    }
    // docs:end:transfer
    #[contract_library_method]
    fn subtract_balance(
        context: &mut PrivateContext,
        storage: Storage<&mut PrivateContext>,
        account: AztecAddress,
        amount: U128,
        max_notes: u32,
    ) -> U128 {
        let subtracted = storage.balances.at(account).try_sub(amount, max_notes);
        // Failing to subtract any amount means that the owner was unable to produce more notes that could be nullified.
        // We could in some cases fail early inside try_sub if we detected that fewer notes than the maximum were
        // returned and we were still unable to reach the target amount, but that'd make the code more complicated, and
        // optimizing for the failure scenario is not as important.
        assert(subtracted > U128::from_integer(0), "Balance too low");
        if subtracted >= amount {
            // We have achieved our goal of nullifying notes that add up to more than amount, so we return the change
            subtracted - amount
        } else {
            // try_sub failed to nullify enough notes to reach the target amount, so we compute the amount remaining
            // and try again.
            let remaining = amount - subtracted;
            compute_recurse_subtract_balance_call(*context, account, remaining).call(context)
        }
    }
    // TODO(#7729): apply no_predicates to the contract interface method directly instead of having to use a wrapper
    // like we do here.
    #[no_predicates]
    #[contract_library_method]
    fn compute_recurse_subtract_balance_call(
        context: PrivateContext,
        account: AztecAddress,
        remaining: U128,
    ) -> PrivateCallInterface<25, U128> {
        Token::at(context.this_address())._recurse_subtract_balance(account, remaining.to_field())
    }
    // TODO(#7728): even though the amount should be a U128, we can't have that type in a contract interface due to
    // serialization issues.
    #[internal]
    #[private]
    fn _recurse_subtract_balance(account: AztecAddress, amount: Field) -> U128 {
        subtract_balance(
            &mut context,
            storage,
            account,
            U128::from_integer(amount),
            RECURSIVE_TRANSFER_CALL_MAX_NOTES,
        )
    }
    /**
     * Cancel a private authentication witness.
     * @param inner_hash The inner hash of the authwit to cancel.
     */
    // docs:start:cancel_authwit
    #[private]
    fn cancel_authwit(inner_hash: Field) {
        let on_behalf_of = context.msg_sender();
        let nullifier = compute_authwit_nullifier(on_behalf_of, inner_hash);
        context.push_nullifier(nullifier);
    }
    // docs:end:cancel_authwit
    // docs:start:transfer_from
    #[private]
    fn transfer_from(from: AztecAddress, to: AztecAddress, amount: Field, nonce: Field) {
        // docs:start:assert_current_call_valid_authwit
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        // docs:end:assert_current_call_valid_authwit
        let from_ovpk_m = get_public_keys(from).ovpk_m;

        let amount = U128::from_integer(amount);
        // docs:start:increase_private_balance
        // docs:start:encrypted
        // TODO: constrain encryption below - we are using unconstrained here only becuase of the following Noir issue
        // https://github.com/noir-lang/noir/issues/5771
        storage.balances.at(from).sub(from, amount).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            from_ovpk_m,
            from,
        ));
        // docs:end:encrypted
        // docs:end:increase_private_balance
        // TODO: constrain encryption below - we are using unconstrained here only becuase of the following Noir issue
        // https://github.com/noir-lang/noir/issues/5771
        storage.balances.at(to).add(to, amount).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            from_ovpk_m,
            to,
        ));
    }
    // docs:end:transfer_from
    // docs:start:burn
    #[private]
    fn burn(from: AztecAddress, amount: Field, nonce: Field) {
        if (!from.eq(context.msg_sender())) {
            assert_current_call_valid_authwit(&mut context, from);
        } else {
            assert(nonce == 0, "invalid nonce");
        }
        let from_ovpk_m = get_public_keys(from).ovpk_m;
        // TODO: constrain encryption below - we are using unconstrained here only becuase of the following Noir issue
        // https://github.com/noir-lang/noir/issues/5771
        storage.balances.at(from).sub(from, U128::from_integer(amount)).emit(
            encode_and_encrypt_note_unconstrained(&mut context, from_ovpk_m, from),
        );
        Token::at(context.this_address())._reduce_total_supply(amount).enqueue(&mut context);
    }
    // docs:end:burn
    /// We need to use different randomness for the user and for the fee payer notes because if the randomness values
    /// were the same we could fingerprint the user by doing the following:
    ///      1) randomness_influence = fee_payer_point - G_npk * fee_payer_npk =
    ///                              = (G_npk * fee_payer_npk + G_rnd * randomness + G_slot * fee_payer_slot)
    ///                                - G_npk * fee_payer_npk - G_slot * fee_payer_slot =
    ///                              = G_rnd * randomness
    ///      2) user_fingerprint = user_point - randomness_influence =
    ///                          = (G_npk * user_npk + G_rnd * randomness + G_slot * user_slot) - G_rnd * randomness =
    ///                          = G_npk * user_npk + G_slot * user_slot
    ///      3) Then the second time the user would use this fee paying contract we would recover the same fingerprint
    ///         and link that the 2 transactions were made by the same user. Given that it's expected that only
    ///         a limited set of fee paying contracts will be used and they will be known, searching for fingerprints
    ///         by trying different fee payers is a feasible attack.
    ///
    /// Note 1: fee_payer_npk is part of the fee_payer address preimage derivation, and is assumed to be known. So
    //          if we have a known set of fee payer contract addresses getting fee_payer_npk and fee_payer_slot is
    //          trivial (slot is derived in a `Map<...>` as a hash of balances map slot and a fee payer address).
    /// Note 2: fee_payer_point and user_point above are public information because they are passed as args to
    ///         the public `complete_refund(...)` function.
    // docs:start:setup_refund
    #[private]
    fn setup_refund(
        fee_payer: AztecAddress, // Address of the entity which will receive the fee note.
        user: AztecAddress, // A user for which we are setting up the fee refund.
        funded_amount: Field, // The amount the user funded the fee payer with (represents fee limit).
    ) {
        // 1. This function is called by fee paying contract (fee_payer) when setting up a refund so we need to support
        // the authwit flow here and check that the user really permitted fee_payer to set up a refund on their behalf.
        assert_current_call_valid_authwit(&mut context, user);

        // 2. Since user is the logical sender of all the notes we get user's ovpk and use that in all of them.
        let user_ovpk = get_public_keys(user).ovpk_m;

        // 3. Deduct the funded amount from the user's balance - this is a maximum fee a user is willing to pay
        // (called fee limit in aztec spec). The difference between fee limit and the actual tx fee will be refunded
        // to the user in the `complete_refund(...)` function.
        let change = subtract_balance(
            &mut context,
            storage,
            user,
            U128::from_integer(funded_amount),
            INITIAL_TRANSFER_CALL_MAX_NOTES,
        );
        storage.balances.at(user).add(user, change).emit(encode_and_encrypt_note_unconstrained(
            &mut context,
            user_ovpk,
            user,
        ));

        // 4. Now we get the partial payloads
        // TODO(#7775): Manually fetching the randomness here is not great. If we decide to include randomness in all
        // notes we could just inject it in macros.
        let fee_payer_randomness = unsafe { random() };
        let user_randomness = unsafe { random() };

        let fee_payer_setup_payload = UintNote::setup_payload().new(
            fee_payer,
            fee_payer_randomness,
            storage.balances.at(fee_payer).set.storage_slot,
        );

        let user_setup_payload = UintNote::setup_payload().new(
            user,
            user_randomness,
            storage.balances.at(user).set.storage_slot,
        );

        // 5. We get transient storage slots
        // Using the x-coordinate as a hiding point slot is safe against someone else interfering with it because
        // we have a guarantee that the public functions of the transaction are executed right after the private ones
        // and for this reason the protocol guarantees that nobody can front-run us in consuming the hiding point.
        // This guarantee would break if `finalize_transfer_to_private` was not called in the same transaction. This
        // however is not the flow we are currently concerned with. To support the multi-transaction flow we could
        // introduce a `from` function argument, hash the x-coordinate with it and then repeat the hashing in
        // `finalize_transfer_to_private`.
        //
        // We can also be sure that the `hiding_point_slot` will not overwrite any other value in the storage because
        // in our state variables we derive slots using a different hash function from multi scalar multiplication
        // (MSM).
        let fee_payer_point_slot = fee_payer_setup_payload.hiding_point.x;
        let user_point_slot = user_setup_payload.hiding_point.x;

        // 6. We compute setup logs
        let fee_payer_setup_log =
            fee_payer_setup_payload.encrypt_log(&mut context, user_ovpk, fee_payer);
        let user_setup_log = user_setup_payload.encrypt_log(&mut context, user_ovpk, user);

        // 7. We store the hiding points an logs in transients storage
        Token::at(context.this_address())
            ._store_payload_in_transient_storage_unsafe(
                fee_payer_point_slot,
                fee_payer_setup_payload.hiding_point,
                fee_payer_setup_log,
            )
            .enqueue(&mut context);
        Token::at(context.this_address())
            ._store_payload_in_transient_storage_unsafe(
                user_point_slot,
                user_setup_payload.hiding_point,
                user_setup_log,
            )
            .enqueue(&mut context);

        // 8. Set the public teardown function to `complete_refund(...)`. Public teardown is the only time when a public
        // function has access to the final transaction fee, which is needed to compute the actual refund amount.
        context.set_public_teardown_function(
            context.this_address(),
            comptime { FunctionSelector::from_signature("complete_refund(Field,Field,Field)") },
            [fee_payer_point_slot, user_point_slot, funded_amount],
        );
    }
    // docs:end:setup_refund

    // TODO(#9375): Having to define the note log length here is very unfortunate as it's basically impossible for
    // users to derive manually. This will however go away once we have a real transient storage since we will not need
    // the public call and instead we would do something like `context.transient_storage_write(slot, payload)` and that
    // will allow us to use generics and hence user will not need to define it explicitly. We cannot use generics here
    // as it is an entrypoint function.
    #[public]
    #[internal]
    fn _store_payload_in_transient_storage_unsafe(
        slot: Field,
        point: Point,
        setup_log: [Field; 16],
    ) {
        context.storage_write(slot, point);
        context.storage_write(slot + aztec::protocol_types::point::POINT_LENGTH as Field, setup_log);
    }

    // TODO(#7728): even though the funded_amount should be a U128, we can't have that type in a contract interface due
    // to serialization issues.
    // docs:start:complete_refund
    #[public]
    #[internal]
    fn complete_refund(fee_payer_slot: Field, user_slot: Field, funded_amount: Field) {
        // TODO(#7728): Remove the next line
        let funded_amount = U128::from_integer(funded_amount);
        let tx_fee = U128::from_integer(context.transaction_fee());

        // 1. We check that user funded the fee payer contract with at least the transaction fee.
        // TODO(#7796): we should try to prevent reverts here
        assert(funded_amount >= tx_fee, "funded amount not enough to cover tx fee");

        // 2. We compute the refund amount as the difference between funded amount and tx fee.
        let refund_amount = funded_amount - tx_fee;

        // 3. We construct the note finalization payloads with the correct amounts and hiding points to get the note
        // hashes and unencrypted logs.
        let fee_payer_finalization_payload =
            UintNote::finalization_payload().new(&mut context, fee_payer_slot, tx_fee);
        let user_finalization_payload =
            UintNote::finalization_payload().new(&mut context, user_slot, refund_amount);

        // 4. At last we emit the note hashes and the final note logs.
        fee_payer_finalization_payload.emit();
        user_finalization_payload.emit();
        // --> Once the tx is settled user and fee recipient can add the notes to their pixies.
    }
    // docs:end:complete_refund

    /// Internal ///
    // docs:start:increase_public_balance
    #[public]
    #[internal]
    fn _increase_public_balance(to: AztecAddress, amount: Field) {
        let new_balance = storage.public_balances.at(to).read().add(U128::from_integer(amount));
        storage.public_balances.at(to).write(new_balance);
    }
    // docs:end:increase_public_balance
    // docs:start:reduce_total_supply
    #[public]
    #[internal]
    fn _reduce_total_supply(amount: Field) {
        // Only to be called from burn.
        let new_supply = storage.total_supply.read().sub(U128::from_integer(amount));
        storage.total_supply.write(new_supply);
    }
    // docs:end:reduce_total_supply
    /// Unconstrained ///
    // docs:start:balance_of_private
    pub(crate) unconstrained fn balance_of_private(owner: AztecAddress) -> pub Field {
        storage.balances.at(owner).balance_of().to_field()
    }
    // docs:end:balance_of_private
}

// docs:end:token_all
