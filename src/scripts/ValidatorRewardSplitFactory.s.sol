// SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "forge-std/Script.sol";
import {ValidatorRewardSplitFactory} from "../factory/ValidatorRewardSplitFactory.sol";

contract ValidatorRewardSplitFactoryScript is Script {
    function run() external {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        new ValidatorRewardSplitFactory{salt: keccak256("obol.validatorRewardSplitFactory.v1")}();

        vm.stopBroadcast();
    }
}