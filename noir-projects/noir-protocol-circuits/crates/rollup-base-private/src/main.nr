use dep::rollup_lib::base::{BaseOrMergeRollupPublicInputs, PrivateBaseRollupInputs};

#[recursive]
fn main(inputs: PrivateBaseRollupInputs) -> pub BaseOrMergeRollupPublicInputs {
    inputs.execute()
}
