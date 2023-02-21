// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {ISplitMain, SplitConfiguration} from "../interfaces/ISplitMain.sol";
import {IENSReverseRegistrar} from "../interfaces/IENSReverseRegistrar.sol";
import {ValidatorRewardSplitFactory} from "../factory/ValidatorRewardSplitFactory.sol";
import {IWaterfallFactoryModule} from "../interfaces/IWaterfallFactoryModule.sol";

contract ValidatorRewardSplitFactoryTest is Test {
  ValidatorRewardSplitFactory public factory;
  address public ensReverseRegistrar = 0x084b1c3C81545d370f3634392De611CaaBFf8148;

  address internal WATERFALL_FACTORY_MODULE_GOERLI = 0xd647B9bE093Ec237be72bB17f54b0C5Ada886A25;
  address internal SPLIT_MAIN_GOERLI = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;

  function setUp() public {
    uint256 goerliBlock = 8529931;
    
    vm.createSelectFork(getChain("goerli").rpcUrl, goerliBlock);
    // for local tests, mock the ENS reverse registrar at its goerli address.
    vm.mockCall(
      ensReverseRegistrar, abi.encodeWithSelector(IENSReverseRegistrar.setName.selector), bytes.concat(bytes32(0))
    );
    vm.mockCall(
      ensReverseRegistrar, abi.encodeWithSelector(IENSReverseRegistrar.claim.selector), bytes.concat(bytes32(0))
    );

    factory = new ValidatorRewardSplitFactory(
            WATERFALL_FACTORY_MODULE_GOERLI,
            SPLIT_MAIN_GOERLI,
            "launchpad.obol.tech",
            ensReverseRegistrar,
            address(0)
        );
  }

  function testCreateRewardSplit() external {
    address[] memory accounts = new address[](2);
    accounts[0] = makeAddr("accounts0");
    accounts[1] = makeAddr("accounts1");

    uint32[] memory percentAllocations = new uint32[](2);
    percentAllocations[0] = 400_000;
    percentAllocations[1] = 600_000;

    SplitConfiguration memory splitConfig = SplitConfiguration(accounts, percentAllocations, 0, address(0x0));

    address payable principal = payable(makeAddr("accounts2"));
    uint256 numberOfValidators = 10;

    (address[] memory withdrawAddresses, address splitRecipient) =
      factory.createETHRewardSplit(splitConfig, principal, numberOfValidators);

    // confirm expected splitrecipient address
    address expectedSplitRecipient =
      ISplitMain(SPLIT_MAIN_GOERLI).predictImmutableSplitAddress(accounts, percentAllocations, 0);
    assertEq(splitRecipient, expectedSplitRecipient, "invalid split configuration");

    address[] memory expectedRecipients = new address[](2);
    expectedRecipients[0] = principal;
    expectedRecipients[1] = splitRecipient;

    uint256[] memory expectedThresholds = new uint256[](1);
    expectedThresholds[0] = 32 ether;

    for (uint256 i = 0; i < withdrawAddresses.length; i++) {
      (address[] memory recipients, uint256[] memory thresholds) =
        IWaterfallFactoryModule(withdrawAddresses[i]).getTranches();

      assertEq(recipients, expectedRecipients, "invalid recipients");
      assertEq(thresholds, expectedThresholds, "invalid thresholds");
    }
  }
}
