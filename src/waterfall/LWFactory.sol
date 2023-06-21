// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {LibClone} from "solady/utils/LibClone.sol";
import {IWaterfallFactoryModule} from "../interfaces/IWaterfallFactoryModule.sol";
import {ISplitMainV2, SplitConfiguration} from "../interfaces/ISplitMainV2.sol";
import {ISplitFactory} from "../interfaces/ISplitFactory.sol";
import {IENSReverseRegistrar} from "../interfaces/IENSReverseRegistrar.sol";
import {LW1155} from "./token/LW1155.sol";

/// @dev Creates liquid waterfall and splitter contract contracts
contract LWFactory {
  /// -----------------------------------------------------------------------
  /// storage - constants and immutables
  /// -----------------------------------------------------------------------

  /// @dev amount of ETH required to run a validator
  uint256 internal constant ETH_STAKE = 32 ether;

  /// @dev waterfall eth token representation
  address internal constant WATERFALL_ETH_TOKEN_ADDRESS = address(0x0);

  /// @dev non waterfall recipient
  address internal constant NON_WATERFALL_TOKEN_RECIPIENT = address(0x0);

  /// @dev waterfall factory
  IWaterfallFactoryModule public immutable waterfallFactoryModule;

  /// @dev splitMain factory
  ISplitFactory public immutable splitFactory;

  /// @dev liquid waterfall implementation
  LW1155 public immutable lw1155;

  constructor(
    address _waterfallFactoryModule,
    address _splitFactory,
    string memory _ensName,
    address _ensReverseRegistrar,
    address _ensOwner,
    address _recoveryWallet
  ) {
    waterfallFactoryModule = IWaterfallFactoryModule(_waterfallFactoryModule);
    splitFactory = ISplitFactory(_splitFactory);
    lw1155 = new LW1155(ISplitFactory(_splitFactory).splitMain(), _recoveryWallet);
    IENSReverseRegistrar(_ensReverseRegistrar).setName(_ensName);
    IENSReverseRegistrar(_ensReverseRegistrar).claim(_ensOwner);
  }

  /// @dev Create reward split for ETH rewards
  /// @param _split Split configuration data
  /// @param _principal address to receive principal
  /// @return withdrawalAddress withdrawal address
  /// @return rewardSplitContract reward split contract
  function createETHRewardSplit(bytes32 _splitWalletId, SplitConfiguration calldata _split, address payable _principal)
    external
    returns (address withdrawalAddress, address rewardSplitContract)
  {
    require(_split.accounts[0] == address(lw1155), "invalid_address");

    // use factory to create split
    rewardSplitContract = splitFactory.createSplit(
      _splitWalletId,
      _split.accounts,
      _split.percentAllocations,
      _split.distributorFee,
      address(lw1155),
      _split.controller
    );

    address[] memory waterfallRecipients = new address[](2);
    waterfallRecipients[0] = address(lw1155);
    waterfallRecipients[1] = rewardSplitContract;

    uint256[] memory thresholds = new uint256[](1);
    thresholds[0] = ETH_STAKE;

    withdrawalAddress = waterfallFactoryModule.createWaterfallModule(
      WATERFALL_ETH_TOKEN_ADDRESS, NON_WATERFALL_TOKEN_RECIPIENT, waterfallRecipients, thresholds
    );

    // mint tokens to principal account
    lw1155.mint(_principal, rewardSplitContract, withdrawalAddress, _split);
  }
}
