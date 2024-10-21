// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./Merkle.sol";
import "../libraries/Endian.sol";

//Utility library for parsing and PHASE0 beacon chain block headers
//SSZ Spec: https://github.com/ethereum/consensus-specs/blob/dev/ssz/simple-serialize.md#merkleization
//BeaconBlockHeader Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
//BeaconState Spec: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconstate
library BeaconChainProofs {
    error BeaconChainProofs__InvalidValidatorRootandBalanceRootProof();
    error BeaconChainProofs__InvalidProofSize();
    error BeaconChainProofs__InvalidMerkleProof();

    error BeaconChainProofs__InvalidValidatorField(uint256 index);
    error BeaconChainProofs__InvalidIndicesAndFields(uint256 indexSize, uint256 fieldSize);
    error BeaconChainProofs__InvalidValidatorFieldsMerkleProof();
    error BeaconChainProofs__InvalidIndicesAndBalances();
    error BeaconChainProofs__IncorrectWithdrawalCredentials(bytes32 pubkeyHash);
    error BeaconChainProofs__InvalidValidatorRootProof();
    error BeaconChainProofs__InvalidBalanceRootProof();

    // constants are the number of fields and the heights of the different merkle trees used in merkleizing beacon chain containers
    uint256 internal constant BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT = 3;
    uint256 internal constant BEACON_STATE_TREE_HEIGHT = 5;


    uint256 internal constant BALANCE_TREE_HEIGHT = 38;
    uint256 internal constant NUM_VALIDATOR_FIELDS = 8;
    uint256 internal constant VALIDATOR_FIELD_TREE_HEIGHT = 3;

    uint256 internal constant VALIDATOR_TREE_HEIGHT = 40;

    /// @notice Number of fields in the `Validator` container
    /// (See https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator)
    uint256 internal constant VALIDATOR_FIELDS_LENGTH = 8;

    // in beacon block header https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#beaconblockheader
    uint256 internal constant STATE_ROOT_INDEX = 3;


    //  in beacon state https://github.com/ethereum/consensus-specs/blob/dev/specs/capella/beacon-chain.md#beaconstate
    uint256 internal constant VALIDATOR_LIST_INDEX = 11;
    uint256 internal constant BALANCE_LIST_ROOT_INDEX = 12;

    // in validator https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator
    uint256 internal constant VALIDATOR_PUBKEY_INDEX = 0;
    uint256 internal constant VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX = 1;
    uint256 internal constant VALIDATOR_BALANCE_INDEX = 2;
    uint256 internal constant VALIDATOR_SLASHED_INDEX = 3;
    uint256 internal constant VALIDATOR_ACTIVATION_EPOCH_INDEX = 5;
    uint256 internal constant VALIDATOR_EXIT_EPOCH_INDEX = 6;
    uint256 internal constant VALIDATOR_WITHDRAWABLE_EPOCH_INDEX = 7;

    //Misc Constants
    /// @notice Far future epoch. used as exit epoch for non-exited validators
    /// @dev https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md?plain=1#L185
    uint256 internal constant FAR_FUTURE_EPOCH = (2**64) - 1;

    /// @notice This struct contains the root and proof for verifying the state root against the oracle block root
    struct ValidatorListAndBalanceListRootProof {
        bytes32[] proof;
    }

    struct ValidatorProof {
        bytes32[] validatorFields;
        bytes proof;
        uint40 validatorIndex;
    }

    struct ValidatorsMultiProof {
        bytes32[][] validatorFields;
        bytes32[] proof;
        uint40[] validatorIndices;
    }

    struct BalanceContainerProof {
        bytes32 balanceListRoot;
        bytes proof;
    }

    struct ValidatorListContainerProof {
        bytes32 validatorListRoot;
        bytes proof;
    }

    struct BalancesMultiProof {
        bytes32[] proof;
        bytes32[] validatorPubKeyHashes;
        bytes32[] validatorBalanceRoots;
    }

    struct BalanceProof {
        bytes proof;
        bytes32 validatorPubKeyHash;
        bytes32 validatorBalanceRoot;
    }

    /// @notice Verify a merkle proof a validator field against the beacon state `validatorContainerRoot`
    /// @param validatorListRoot the merkle root of all validator fields 
    /// @param validatorFields validator fields
    function verifyValidatorFields(
        bytes32 validatorListRoot,
        bytes32[] calldata validatorFields,
        bytes calldata validatorFieldsProof,
        uint40 validatorIndex
    ) internal view {
        if (validatorFields.length != (2 ** VALIDATOR_FIELD_TREE_HEIGHT)) {
            revert BeaconChainProofs__InvalidValidatorField(0);
        }

        /// Note: the reason we use `VALIDATOR_TREE_HEIGHT + 1` here is because the merklization process for
        /// this container includes hashing the root of the validator tree with the length of the validator list
        if (validatorFieldsProof.length != (32 * (VALIDATOR_TREE_HEIGHT + 1))) {
            revert BeaconChainProofs__InvalidProofSize();
        } 

        // Merkleize `validatorFields` to get the leaf to prove
        bytes32 validatorRoot = Merkle.merkleizeSha256(validatorFields);

        if(
            Merkle.verifyInclusionSha256({
                proof: validatorFieldsProof,
                root: validatorListRoot,
                leaf: validatorRoot,
                index: validatorIndex
            }) == false
        ) {
            revert BeaconChainProofs__InvalidMerkleProof();
        }
    }

    /// @notice Verify a merkle proof of a validator's balance against the beacon state's `balanceContainerRoot`
    /// @param balanceContainerRoot the merkle root of all validators' current balances
    /// @param validatorIndex the index of the validator whose balance we are proving
    /// @param proof the validator's associated balance root and a merkle proof of inclusion under `balanceContainerRoot`
    function verifyValidatorBalance(
        bytes32 balanceContainerRoot,
        uint40 validatorIndex,
        BalanceProof calldata proof
    ) internal view {
        /// Note: the reason we use `BALANCE_TREE_HEIGHT + 1` here is because the merklization process for
        /// this container includes hashing the root of the balances tree with the length of the balances list
        if (proof.proof.length != 32 * (BALANCE_TREE_HEIGHT + 1)) {
            revert BeaconChainProofs__InvalidProofSize();
        }
        /// When merkleized, beacon chain balances are combined into groups of 4 called a `balanceRoot`. The merkle
        /// proof here verifies that this validator's `balanceRoot` is included in the `balanceContainerRoot`
        /// - balanceContainerRoot
        /// |                            HEIGHT: BALANCE_TREE_HEIGHT
        /// -- balanceRoot
        uint256 balanceIndex = uint256(validatorIndex / 4);

        if(
            Merkle.verifyInclusionSha256({
                proof: proof.proof,
                root: balanceContainerRoot,
                leaf: proof.validatorBalanceRoot,
                index: balanceIndex
            }) == false
            ) 
        {
            revert BeaconChainProofs__InvalidMerkleProof();
        }
    }
    
    /// @notice This function verifies merkle proofs of the fields of a certain validator against a beacon chain state root
    /// @param validatorListRoot is the validator list root to be proven against.
    /// @param validatorFields the claimed fields of the validators being provien
    /// @param validatorIndices the sorted indices of the proven validator
    /// @param proof is the data used in proving the validator's fields
    function verifyMultiValidatorFields(
        bytes32 validatorListRoot,
        bytes32[][] calldata validatorFields,
        bytes32[] calldata proof,
        uint40[] memory validatorIndices
    ) internal pure {
        uint256 validatorFieldsSize = validatorFields.length;
        uint256 indicesSize = validatorIndices.length;

        if (validatorIndices.length != validatorFields.length) {
            revert BeaconChainProofs__InvalidIndicesAndFields(indicesSize, validatorFieldsSize);
        }
        
        Merkle.Node[] memory validatorFieldNodes = new Merkle.Node[](validatorFieldsSize);
        for (uint256 i = 0; i < validatorFields.length; i++) {
            if (validatorFields[i].length != (2 ** VALIDATOR_FIELD_TREE_HEIGHT)) {
                revert BeaconChainProofs__InvalidValidatorField(i);
            }
            // merkleize the validatorFields to get the leaf to prove
            bytes32 validatorRoot = Merkle.merkleizeSha256(validatorFields[i]);
            validatorFieldNodes[i] = Merkle.Node(validatorRoot, validatorIndices[i]);
        }
        
        /**
         * Note: the length of the validator merkle proof is BeaconChainProofs.VALIDATOR_TREE_HEIGHT + 1.
         * There is an additional layer added by hashing the root with the length of the validator list
         */
        uint256 numLayers = VALIDATOR_TREE_HEIGHT + 1;

        if (
            Merkle.verifyMultiProofInclusionSha256(
                validatorListRoot,
                proof,
                validatorFieldNodes,
                numLayers
            ) == false) {
            revert BeaconChainProofs__InvalidValidatorFieldsMerkleProof();
        }
    }

    /// @notice This function verifies merkle proofs of the fields of a certain validator against a beacon chain state root
    /// @param balanceListRoot is the validator list root to be proven against.
    /// @param proof is the data used in proving the validator's fields
    /// @param validatorIndices the indices of the validators being provien
    /// @param validatorBalances the balances of the validators being proven
    function verifyMultiValidatorsBalance(
        bytes32 balanceListRoot,
        bytes32[] calldata proof,
        uint40[] memory validatorIndices,
        bytes32[] memory validatorBalances
    ) internal pure returns (uint256[] memory actualValidatorBalances) { 
        uint256 validatorBalancesSize = validatorBalances.length;
        if (validatorBalancesSize != validatorIndices.length) {
            revert BeaconChainProofs__InvalidIndicesAndBalances();
        }

        Merkle.Node[] memory balanceNodes = new Merkle.Node[](validatorBalancesSize);

        uint256 numLayers = BALANCE_TREE_HEIGHT + 1;

        /**
         * 
         */
        actualValidatorBalances = new uint256[](validatorBalancesSize);
        for (uint256 i = 0; i < validatorBalancesSize; i++) {
            uint256 index = validatorIndices[i] / 4;
            balanceNodes[i] = Merkle.Node(validatorBalances[i], index);

            actualValidatorBalances[i] = uint256(getBalanceAtIndex(validatorBalances[i], validatorIndices[i]));
        }

        if (
            Merkle.verifyMultiProofInclusionSha256(
                balanceListRoot,
                proof,
                balanceNodes,
                numLayers
            ) == false) {
            revert BeaconChainProofs__InvalidMerkleProof();
        }
    }

    /// @notice This function verifies validatorListRoot against the block root. 
    /// @param beaconBlockRoot merkle root of the beacon block
    /// @param proof proof
    function verifyValidatorListRootAgainstBlockRoot(
        bytes32 beaconBlockRoot,
        ValidatorListContainerProof calldata proof
    ) internal view {
        if (
            proof.proof.length != 32 * (BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT + BEACON_STATE_TREE_HEIGHT)
        ) {
            revert BeaconChainProofs__InvalidProofSize();
        }
        /// This proof combines two proofs, so its index accounts for the relative position of leaves in two trees:
        /// - beaconBlockRoot
        /// |                            HEIGHT: BEACON_BLOCK_HEADER_TREE_HEIGHT
        /// -- beaconStateRoot 
        /// |                            HEIGHT: BEACON_STATE_TREE_HEIGHT
        /// ---- validatorListRoot
        uint256 validatorIndex = (STATE_ROOT_INDEX << (BEACON_STATE_TREE_HEIGHT)) | VALIDATOR_LIST_INDEX;

        if (Merkle.verifyInclusionSha256({
                proof: proof.proof,
                root: beaconBlockRoot,
                leaf: proof.validatorListRoot,
                index: validatorIndex
        }) == false) {
            revert BeaconChainProofs__InvalidValidatorRootProof();
        }
    }

    /// @notice Verify a merkle proof of the beacon state's balances container against the beacon block root
    /// @dev This proof starts at the balance container root, proves through the beacon state root, and
    /// continues proving through the beacon block root. As a result, this proof will contain elements
    /// of a `StateRootProof` under the same block root, with the addition of proving the balances field
    /// within the beacon state.
    /// @dev This is used to make checkpoint proofs more efficient, as a checkpoint will verify multiple balances
    /// against the same balance container root.
    /// @param beaconBlockRoot merkle root of the beacon block
    /// @param proof a beacon balance container root and merkle proof of its inclusion under `beaconBlockRoot`
    function verifyBalanceRootAgainstBlockRoot(
        bytes32 beaconBlockRoot,
        BalanceContainerProof calldata proof
    ) internal view {
        if (
            proof.proof.length != 32 * (BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT + BEACON_STATE_TREE_HEIGHT)
        ) {
            revert BeaconChainProofs__InvalidProofSize();
        }

        /// This proof combines two proofs, so its index accounts for the relative position of leaves in two trees:
        /// - beaconBlockRoot
        /// |                            HEIGHT: BEACON_BLOCK_HEADER_TREE_HEIGHT
        /// -- beaconStateRoot
        /// |                            HEIGHT: BEACON_STATE_TREE_HEIGHT
        /// ---- balancesListRoot
        uint256 index = (STATE_ROOT_INDEX << (BEACON_STATE_TREE_HEIGHT)) | BALANCE_LIST_ROOT_INDEX;

        if (Merkle.verifyInclusionSha256({
                proof: proof.proof,
                root: beaconBlockRoot,
                leaf: proof.balanceListRoot,
                index: index
        }) == false) {
            revert BeaconChainProofs__InvalidBalanceRootProof();
        }
    }

    /**
     * @notice Parses a balanceRoot to get the uint64 balance of a validator.  
     * @dev During merkleization of the beacon state balance tree, four uint64 values are treated as a single 
     * leaf in the merkle tree. We use validatorIndex % 4 to determine which of the four uint64 values to 
     * extract from the balanceRoot.
     * @param balanceRoot is the combination of 4 validator balances being proven for
     * @param validatorIndex is the index of the validator being proven for
     * @return The validator's balance, in Gwei
     */
    function getBalanceAtIndex(bytes32 balanceRoot, uint40 validatorIndex) internal pure returns (uint64) {
        uint256 bitShiftAmount = (validatorIndex % 4) * 64;
        return 
            Endian.fromLittleEndianUint64(bytes32((uint256(balanceRoot) << bitShiftAmount)));
    }

    /**
     * @notice This function replicates the ssz hashing of a validator's pubkey, outlined below:
     *  hh := ssz.NewHasher()
     *  hh.PutBytes(validatorPubkey[:])
     *  validatorPubkeyHash := hh.Hash()
     *  hh.Reset()
     */
    function hashValidatorBLSPubkey(bytes memory validatorPubkey) internal pure returns (bytes32 pubkeyHash) {
        require(validatorPubkey.length == 48, "Input should be 48 bytes in length");
        return sha256(abi.encodePacked(validatorPubkey, bytes16(0)));
    }

    /**
     * @dev Retrieves a validator's pubkey hash
     */
    function getPubkeyHash(bytes32[] calldata validatorFields) internal pure returns (bytes32) {
        return 
            validatorFields[VALIDATOR_PUBKEY_INDEX];
    }

    function getWithdrawalCredentials(bytes32[] calldata validatorFields) internal pure returns (bytes32) {
        return
            validatorFields[VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX];
    }

    /**
     * @dev Retrieves a validator's effective balance (in gwei)
     */
    function getEffectiveBalanceGwei(bytes32[] calldata validatorFields) internal pure returns (uint64) {
        return 
            Endian.fromLittleEndianUint64(validatorFields[VALIDATOR_BALANCE_INDEX]);
    }

    /**
     * @dev Retrieves a validator's withdrawable epoch
     */
    function getWithdrawableEpoch(bytes32[] calldata validatorFields) internal pure returns (uint64) {
        return 
            Endian.fromLittleEndianUint64(validatorFields[VALIDATOR_WITHDRAWABLE_EPOCH_INDEX]);
    }

    function getExitEpoch(bytes32[] calldata validatorFields) internal pure returns (uint64) {
        return 
            Endian.fromLittleEndianUint64(validatorFields[VALIDATOR_EXIT_EPOCH_INDEX]);
    }

    function isValidatorSlashed(bytes32[] calldata validatorFields) internal pure returns (bool) {
        return validatorFields[VALIDATOR_SLASHED_INDEX] != bytes32(0);
    }

    /// @dev Retrieves a validator's activation epoch
    function getActivationEpoch(bytes32[] calldata validatorFields) internal pure returns (uint64) {
        return Endian.fromLittleEndianUint64(validatorFields[VALIDATOR_ACTIVATION_EPOCH_INDEX]);
    }

}
