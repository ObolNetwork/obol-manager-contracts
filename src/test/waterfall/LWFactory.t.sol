// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {SplitFactory} from "src/splitter/SplitFactory.sol";
import {SplitWallet} from "src/splitter/SplitWallet.sol";
import {AddressBook} from "./LW1155.t.sol";
import {LWFactory} from "../../waterfall/LWFactory.sol";
import {IENSReverseRegistrar} from "../../interfaces/IENSReverseRegistrar.sol";
import {SplitConfiguration} from "../../interfaces/ISplitMainV2.sol";
import {IWaterfallModule} from "../../interfaces/IWaterfallModule.sol";

contract LWFactoryTest is Test, AddressBook {
  LWFactory lwFactory;
  SplitFactory splitFactory;
  SplitWallet splitWallet;
  bytes32 splitWalletId;

  function setUp() public {
    uint256 goerliBlock = 8_529_931;

    vm.createSelectFork(getChain("goerli").rpcUrl, goerliBlock);
    // for local tests, mock the ENS reverse registrar at its goerli address.
    vm.mockCall(
      ensReverseRegistrar, abi.encodeWithSelector(IENSReverseRegistrar.setName.selector), bytes.concat(bytes32(0))
    );
    vm.mockCall(
      ensReverseRegistrar, abi.encodeWithSelector(IENSReverseRegistrar.claim.selector), bytes.concat(bytes32(0))
    );
    splitFactory = new SplitFactory(address(this));
    splitWallet = new SplitWallet(address(splitFactory.splitMain()));
    splitWalletId = keccak256("demofactroy");
    splitFactory.addSplitWallet(splitWalletId, address(splitWallet));
    lwFactory = new LWFactory(
      WATERFALL_FACTORY_MODULE_GOERLI,
      address(splitFactory),
      "demo.obol.eth",
      ensReverseRegistrar,
      address(this),
      address(this)
    );
  }

  function testCreateETHRewardSplit() external {
    address[] memory accounts = new address[](2);
    accounts[0] = address(lwFactory.lw1155());
    accounts[1] = makeAddr("accounts1");

    uint32[] memory percentAllocations = new uint32[](2);
    percentAllocations[0] = 400_000;
    percentAllocations[1] = 600_000;

    SplitConfiguration memory splitConfig = SplitConfiguration(accounts, percentAllocations, 0, address(0x0), address(0));

    address payable principal = payable(makeAddr("accounts2"));

    (address withdrawAddress, address splitRecipient) = lwFactory.createETHRewardSplit(
      splitWalletId,
      splitConfig,
      principal
    );

    // confirm expected splitrecipient address
    address expectedSplitRecipient = splitFactory.predictImmutableSplitAddress(splitWalletId, accounts, percentAllocations, 0);
    assertEq(splitRecipient, expectedSplitRecipient, "invalid split configuration");

    address[] memory expectedRecipients = new address[](2);
    expectedRecipients[0] = address(lwFactory.lw1155());
    expectedRecipients[1] = splitRecipient;

    uint256[] memory expectedThresholds = new uint256[](1);
    expectedThresholds[0] = 32 ether;

    (address[] memory recipients, uint256[] memory thresholds) = IWaterfallModule(withdrawAddress).getTranches();

    assertEq(recipients, expectedRecipients, "invalid recipients");
    assertEq(thresholds, expectedThresholds, "invalid thresholds");
  }
}
