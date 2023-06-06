// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;
import "forge-std/Test.sol";
import {ERC20} from '@rari-capital/solmate/src/tokens/ERC20.sol';
import "../../../lido/LidoSplitWallet.sol";

contract LidoIntegration is Test {
    
    address internal STETH_MAINNET_ADDRESS = '0x';
    address internal WSTETH_MAINNET_ADDRESS = '0x';

    LidoSplitWallet lidoSplitWallet;

    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() {
        uint256 mainnetBlock = 17421005;
        vm.createSelectFork(getChain("mainnet").rpcUrl, mainnetBlock);
        // mainnet fork credit lido split wallet with tokens
        // credit some lido tokens to splitwallet
        // call sendERC20 to main to ensure wstETH is what's getting
        // sent 
        // that's all

        lidoSplitWallet = new LidoSplitWallet(
            ERC20(STETH_MAINNET_ADDRESS),
            ERC20(WSTETH_MAINNET_ADDRESS)
        );
    }

    function testSendERC20ToMain() external {
        deal(STETH_MAINNET_ADDRESS, lidoSplitWallet, 1 ether);

        lidoSplitWallet.sendERC20ToMain(ERC20(wstETH), 0.5 ether);

        // check the balance of this address
        assertEq(
            ERC20(WSTETH_MAINNET_ADDRESS).balanceOf(address(this)) > 0,
            true
        );
    }


    function testSendETHToMain() external {
        vm.deal(lidoSplitWallet, 1 ether);

        lidoSplitWallet.sendETHToMain(ERC20(wstETH), 0.5 ether);

        // check the balance of this address
        assertEq(address(this).balance, 0.5 ether);
    }
}