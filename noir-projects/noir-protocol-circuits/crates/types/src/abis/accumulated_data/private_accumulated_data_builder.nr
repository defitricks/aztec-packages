use crate::{
    abis::{
        accumulated_data::private_accumulated_data::PrivateAccumulatedData,
        log_hash::{NoteLogHash, ScopedEncryptedLogHash, ScopedLogHash},
        note_hash::ScopedNoteHash,
        nullifier::ScopedNullifier,
        private_call_request::PrivateCallRequest,
        public_call_request::PublicCallRequest,
    },
    constants::{
        MAX_ENCRYPTED_LOGS_PER_TX, MAX_L2_TO_L1_MSGS_PER_TX, MAX_NOTE_ENCRYPTED_LOGS_PER_TX,
        MAX_NOTE_HASHES_PER_TX, MAX_NULLIFIERS_PER_TX, MAX_PRIVATE_CALL_STACK_LENGTH_PER_TX,
        MAX_PUBLIC_CALL_STACK_LENGTH_PER_TX, MAX_UNENCRYPTED_LOGS_PER_TX,
    },
    messaging::l2_to_l1_message::ScopedL2ToL1Message,
    traits::Empty,
};

pub struct PrivateAccumulatedDataBuilder {
    note_hashes: BoundedVec<ScopedNoteHash, MAX_NOTE_HASHES_PER_TX>,
    nullifiers: BoundedVec<ScopedNullifier, MAX_NULLIFIERS_PER_TX>,
    l2_to_l1_msgs: BoundedVec<ScopedL2ToL1Message, MAX_L2_TO_L1_MSGS_PER_TX>,

    note_encrypted_logs_hashes: BoundedVec<NoteLogHash, MAX_NOTE_ENCRYPTED_LOGS_PER_TX>,
    encrypted_logs_hashes: BoundedVec<ScopedEncryptedLogHash, MAX_ENCRYPTED_LOGS_PER_TX>,
    unencrypted_logs_hashes: BoundedVec<ScopedLogHash, MAX_UNENCRYPTED_LOGS_PER_TX>,

    public_call_requests: BoundedVec<PublicCallRequest, MAX_PUBLIC_CALL_STACK_LENGTH_PER_TX>,
    private_call_stack: BoundedVec<PrivateCallRequest, MAX_PRIVATE_CALL_STACK_LENGTH_PER_TX>,
}

impl PrivateAccumulatedDataBuilder {
    pub fn finish(self) -> PrivateAccumulatedData {
        PrivateAccumulatedData {
            note_hashes: self.note_hashes.storage,
            nullifiers: self.nullifiers.storage,
            l2_to_l1_msgs: self.l2_to_l1_msgs.storage,
            note_encrypted_logs_hashes: self.note_encrypted_logs_hashes.storage,
            encrypted_logs_hashes: self.encrypted_logs_hashes.storage,
            unencrypted_logs_hashes: self.unencrypted_logs_hashes.storage,
            public_call_requests: self.public_call_requests.storage,
            private_call_stack: self.private_call_stack.storage,
        }
    }
}

impl Empty for PrivateAccumulatedDataBuilder {
    fn empty() -> Self {
        PrivateAccumulatedDataBuilder {
            note_hashes: BoundedVec::new(),
            nullifiers: BoundedVec::new(),
            l2_to_l1_msgs: BoundedVec::new(),
            note_encrypted_logs_hashes: BoundedVec::new(),
            encrypted_logs_hashes: BoundedVec::new(),
            unencrypted_logs_hashes: BoundedVec::new(),
            public_call_requests: BoundedVec::new(),
            private_call_stack: BoundedVec::new(),
        }
    }
}
