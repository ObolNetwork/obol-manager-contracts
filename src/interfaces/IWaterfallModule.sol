// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IWaterfallModule {
    
    /// Waterfalls target token inside the contract to next-in-line recipients
    /// @dev pushes funds to recipients
    function waterfallFunds() external;

    /// Address of ERC20 to waterfall (0x0 used for ETH)
    /// @dev equivalent to address public immutable token;
    function token() external pure returns (address);
}