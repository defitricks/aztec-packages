use dep::rollup_lib::block_root::{BlockRootOrBlockMergePublicInputs, BlockRootRollupInputs};

#[recursive]
fn main(inputs: BlockRootRollupInputs) -> pub BlockRootOrBlockMergePublicInputs {
    inputs.block_root_rollup_circuit()
}
