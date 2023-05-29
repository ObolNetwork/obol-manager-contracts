// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/Script.sol";
import {ValidatorRewardSplitFactory} from "src/factory/ValidatorRewardSplitFactory.sol";

contract ValidatorRewardSplitFactoryScript is Script {
  function run(address waterfallFactoryModule, address splitMain, address ensReverseRegistrar, address ensOnwer)
    external
  {
    uint256 privKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(privKey);

    string memory ensName = "launchpad.obol.eth";

    new ValidatorRewardSplitFactory{salt: keccak256("obol.validatorRewardSplitFactory.v1")}(
            waterfallFactoryModule,
            splitMain,
            ensName,
            ensReverseRegistrar,
            ensOnwer
        );
    vm.stopBroadcast();
  }
}
