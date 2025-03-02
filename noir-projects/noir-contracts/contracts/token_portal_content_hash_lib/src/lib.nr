// docs:start:mint_public_content_hash_nr
use dep::aztec::prelude::{AztecAddress, EthAddress};
use dep::aztec::protocol_types::hash::sha256_to_field;

// Computes a content hash of a deposit/mint_public message.
// Refer TokenPortal.sol for reference on L1.
pub fn get_mint_public_content_hash(owner: AztecAddress, amount: Field) -> Field {
    let mut hash_bytes = [0; 68];
    let recipient_bytes:[u8; 32] = owner.to_field().to_be_bytes();
    let amount_bytes:[u8; 32] = amount.to_be_bytes();

    for i in 0..32 {
        hash_bytes[i + 4] = recipient_bytes[i];
        hash_bytes[i + 36] = amount_bytes[i];
    }

    // Function selector: 0x3e87b9be keccak256('mint_public(bytes32,uint256)')
    hash_bytes[0] = 0x3e;
    hash_bytes[1] = 0x87;
    hash_bytes[2] = 0xb9;
    hash_bytes[3] = 0xbe;

    let content_hash = sha256_to_field(hash_bytes);
    content_hash
}
// docs:end:mint_public_content_hash_nr

// docs:start:get_mint_private_content_hash
// Computes a content hash of a deposit/mint_private message.
// Refer TokenPortal.sol for reference on L1.
pub fn get_mint_private_content_hash(
    secret_hash_for_redeeming_minted_notes: Field,
    amount: Field
) -> Field {
    let mut hash_bytes = [0; 68];
    let secret_hash_bytes:[u8; 32] = secret_hash_for_redeeming_minted_notes.to_be_bytes();
    let amount_bytes:[u8; 32] = amount.to_be_bytes();

    for i in 0..32 {
        hash_bytes[i + 4] = secret_hash_bytes[i];
        hash_bytes[i + 36] = amount_bytes[i];
    }

    // Function selector: 0xefa012c1 keccak256('mint_private(bytes32,uint256)')
    hash_bytes[0] = 0xef;
    hash_bytes[1] = 0xa0;
    hash_bytes[2] = 0x12;
    hash_bytes[3] = 0xc1;

    let content_hash = sha256_to_field(hash_bytes);
    content_hash
}
// docs:end:get_mint_private_content_hash

// docs:start:get_withdraw_content_hash
// Computes a content hash of a withdraw message.
pub fn get_withdraw_content_hash(recipient: EthAddress, amount: Field, caller_on_l1: EthAddress) -> Field {
    // Compute the content hash
    // Compute sha256(selector || amount || recipient)
    // then convert to a single field element
    // add that to the l2 to l1 messages
    let mut hash_bytes: [u8; 100] = [0; 100];
    let recipient_bytes: [u8; 32] = recipient.to_field().to_be_bytes();
    let amount_bytes: [u8; 32] = amount.to_be_bytes();
    let caller_on_l1_bytes: [u8; 32] = caller_on_l1.to_field().to_be_bytes();

    //  0x69328dec, selector for "withdraw(address,uint256,address)"
    hash_bytes[0] = 0x69;
    hash_bytes[1] = 0x32;
    hash_bytes[2] = 0x8d;
    hash_bytes[3] = 0xec;

    for i in 0..32 {
        hash_bytes[i + 4] = recipient_bytes[i];
        hash_bytes[i + 36] = amount_bytes[i];
        hash_bytes[i + 68] = caller_on_l1_bytes[i];
    }
    let content_hash = sha256_to_field(hash_bytes);
    content_hash
}
// docs:end:get_withdraw_content_hash
