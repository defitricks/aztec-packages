// Sample escrow contract that stores a balance of a private token on behalf of an owner.
use dep::aztec::macros::aztec;

#[aztec]
contract Escrow {
    use dep::aztec::{
        encrypted_logs::encrypted_note_emission::encode_and_encrypt_note,
        keys::getters::get_public_keys,
        macros::{functions::{initializer, private}, storage::storage},
    };
    use dep::aztec::prelude::{AztecAddress, PrivateImmutable};

    // docs:start:addressnote_import
    use dep::address_note::address_note::AddressNote;
    // docs:end:addressnote_import
    use dep::token::Token;

    #[storage]
    struct Storage<Context> {
        owner: PrivateImmutable<AddressNote, Context>,
    }

    // Creates a new instance
    #[private]
    #[initializer]
    fn constructor(owner: AztecAddress) {
        // docs:start:addressnote_new
        let mut note = AddressNote::new(owner, owner);
        // docs:end:addressnote_new
        let msg_sender_ovpk_m = get_public_keys(context.msg_sender()).ovpk_m;
        storage.owner.initialize(&mut note).emit(encode_and_encrypt_note(
            &mut context,
            msg_sender_ovpk_m,
            owner,
        ));
    }

    // Withdraws balance. Requires that msg.sender is the owner.
    #[private]
    fn withdraw(token: AztecAddress, amount: Field, recipient: AztecAddress) {
        let sender = context.msg_sender();

        let note = storage.owner.get_note();
        assert(note.address == sender);

        Token::at(token).transfer(recipient, amount).call(&mut context);
    }
}
