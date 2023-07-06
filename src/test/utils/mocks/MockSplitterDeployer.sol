// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {ObolSplitterDeployer, ISplitMain} from "src/archive/Splitter.sol";

contract MockSplitterDeployer is ObolSplitterDeployer {
  constructor(ISplitMain splitterContract, address obolWallet) ObolSplitterDeployer(splitterContract, obolWallet) {}
}
