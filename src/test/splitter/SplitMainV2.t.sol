// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {
  SplitMainV2,
  Unauthorized,
  InvalidSplit__TooFewAccounts,
  InvalidSplit__AccountsAndAllocationsMismatch,
  InvalidSplit__InvalidAllocationsSum,
  InvalidSplit__AccountsOutOfOrder,
  InvalidSplit__AllocationMustBePositive,
  InvalidSplit__InvalidDistributorFee
} from "src/splitter/SplitMainV2.sol";
import {SplitWallet} from "src/splitter/SplitWallet.sol";
import {MockERC20} from "../utils/mocks/MockERC20.sol";


contract SplitMainV2Test is Test {
  SplitMainV2 public splitMainV2;
  address public splitWallet;
  uint32 public constant SPLIT_MAIN_PERCENTAGE_SCALE = 1e6;

  event CreateSplit(address indexed split);

  address[] accounts;
  uint32[] percentAllocations;
  address user1;
  address user2;
  address user3;
  
  ERC20 mockERC20;

  function setUp() public virtual {
    splitMainV2 = new SplitMainV2();
    splitWallet = address(new SplitWallet(address(splitMainV2)));
    
    mockERC20 = ERC20(address(new MockERC20("demo", "DMT", 18)));

    accounts = new address[](2);
    accounts[0] = makeAddr("accounts0");
    accounts[1] = makeAddr("accounts1");

    percentAllocations = new uint32[](2);
    percentAllocations[0] = 400_000;
    percentAllocations[1] = 600_000;

    user1 = makeAddr("account2");
    user2 = makeAddr("account3");
    user3 = makeAddr("account4"); 
  }

  function createTestMutableSplit() internal returns (address split) {
    split = splitMainV2.createSplit(
      address(splitWallet),
      accounts,
      percentAllocations,
      address(this),
      address(this),
      0
    );
  }

}

contract SplitMainV2CreateSplitConfiguration is SplitMainV2Test {
  address internal split;

  function testRevertIfAccountSizeIsOne() public {
    address[] memory newAccounts = new address[](1);
    newAccounts[0] = makeAddr("testRevertIfAccountSizeIsOne");

    vm.expectRevert(
      abi.encodeWithSelector(InvalidSplit__TooFewAccounts.selector, newAccounts.length)
    );

    splitMainV2.createSplit(
      splitWallet,
      newAccounts,
      percentAllocations,
      address(0),
      address(0),
      0
    );
  }
  
  function testRevertIfIncorrectAccountsAndAllocationSize() public {
    uint32[] memory newPercentAllocations = new uint32[](3);
    newPercentAllocations[0] = 200_000;
    newPercentAllocations[1] = 200_000;
    newPercentAllocations[2] = 600_000;

    vm.expectRevert(
      abi.encodeWithSelector(
        InvalidSplit__AccountsAndAllocationsMismatch.selector,
        accounts.length,
        newPercentAllocations.length
      )
    );

    splitMainV2.createSplit(
      splitWallet,
      accounts,
      newPercentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testRevertIfIncorrectPercentAllocations() public {
    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = 700_000;
    newPercentAllocations[1] = 500_000;

    vm.expectRevert(
      abi.encodeWithSelector(
        InvalidSplit__InvalidAllocationsSum.selector,
        1_200_000
      )
    );

    splitMainV2.createSplit(
      splitWallet,
      accounts,
      newPercentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testRevertIfAccountOutOfOrder() public {
    address[] memory newAccounts = new address[](2);
    newAccounts[0] = address(0x4);
    newAccounts[1] = address(0x1);

    vm.expectRevert(
      abi.encodeWithSelector(
        InvalidSplit__AccountsOutOfOrder.selector,
        0
      )
    );

    splitMainV2.createSplit(
      splitWallet,
      newAccounts,
      percentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testRevertIfZeroPercentAllocation() public {
    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = SPLIT_MAIN_PERCENTAGE_SCALE;
    newPercentAllocations[1] = 0;

    vm.expectRevert(
      abi.encodeWithSelector(
        InvalidSplit__AllocationMustBePositive.selector,
        1
      )
    );

    splitMainV2.createSplit(
      splitWallet,
      accounts,
      newPercentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testRevertIfInvalidDistributorFee() public {
    uint32 invalidDistributorFee = 1e6;
    
    vm.expectRevert(
      abi.encodeWithSelector(
        InvalidSplit__InvalidDistributorFee.selector,
        invalidDistributorFee
      )
    );

    splitMainV2.createSplit(
      splitWallet,
      accounts,
      percentAllocations,
      address(0),
      address(0),
      invalidDistributorFee
    );
  }

}

contract SplitMainV2CreateImmutableSplit is SplitMainV2Test {
  address internal split;
  
  function setUp() public override {
    super.setUp();
    address predictedSplitAddress = splitMainV2.predictImmutableSplitAddress(
      address(splitWallet), accounts, percentAllocations, 0
    );

    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit CreateSplit(predictedSplitAddress);

    split = splitMainV2.createSplit(address(splitWallet), accounts, percentAllocations, address(0), address(this), 0);

    assertEq(predictedSplitAddress, split, "invalid predicted split address");
  }

  function testGetSplitHash() public {
    bytes32 splitHash = splitMainV2.getHash(split);
    assertEq(splitHash != bytes32(0), true, "invalid split hash");
  }

  function testGetSplitController() public {
    assertEq(splitMainV2.getController(split), address(0), "invalid split controller");
  }

  function testRevertIfUpdateImmutableSplit() public {
    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = percentAllocations[1];
    newPercentAllocations[1] = percentAllocations[0];

    vm.expectRevert();
    splitMainV2.updateSplit(split, accounts, newPercentAllocations, 0);
  }

}

contract SplitMainV2CreateMutableSplit is SplitMainV2Test {

  event UpdateSplit(address indexed split);
  event InitiateControlTransfer(address indexed split, address indexed newPotentialController);
  event CancelControlTransfer(address indexed split);
  event ControlTransfer(address indexed split, address indexed previousController, address indexed newController);

  function testGetHash() public {
    address split = createTestMutableSplit();
    bytes32 splitHash = splitMainV2.getHash(split);
    assertEq(splitHash != bytes32(0), true, "invalid split hassh");
  }

  function testCanUpdateSplit() public {   
    address split = createTestMutableSplit();

    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = percentAllocations[1];
    newPercentAllocations[1] = percentAllocations[0];

    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit UpdateSplit(split);

    splitMainV2.updateSplit(split, accounts, newPercentAllocations, 0);
  }

  function testCanGetSplitController() public {
    address split = createTestMutableSplit();
    assertEq(splitMainV2.getController(split), address(this), "invalid split controler");
  }

  function testTransferControlMutableSplit() public {
    address split = createTestMutableSplit();
    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit InitiateControlTransfer(split, user1);

    splitMainV2.transferControl(split, user1);

    assertEq(splitMainV2.getNewPotentialController(split), user1, "invalid new controller");
  }

  function testRevertIfTransferControlNotController() public {
   address split = createTestMutableSplit();
    vm.expectRevert();
    vm.prank(user1);
    splitMainV2.transferControl(split, user1);
  }

  function testCancelControlTransfer() public {
    address split = createTestMutableSplit();

    splitMainV2.transferControl(split, user1);

    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit CancelControlTransfer(split);

    splitMainV2.cancelControlTransfer(split);
  }

  function testRevertIfCancelControlTransfer() public {
    address split = createTestMutableSplit();
    vm.expectRevert();
    vm.prank(user1);
    splitMainV2.cancelControlTransfer(split);
  }

  function testAcceptControl() public {
    address split = createTestMutableSplit();

    console.logString("getcontroller");
    console.log(splitMainV2.getController(split));
    vm.prank(address(this));
    splitMainV2.transferControl(split, user1);

    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit ControlTransfer(split, address(this), user1);
    
    vm.prank(user1);
    splitMainV2.acceptControl(split);
  }

  function testRevertIfAcceptControlNotNewPotentialController() public {

    address split = createTestMutableSplit();
    
    splitMainV2.transferControl(split, user1);
    vm.prank(user2);

    vm.expectRevert();
    splitMainV2.acceptControl(split);
  }

  function testMakeSplitImmutable() public {
    address split = createTestMutableSplit();

    vm.expectEmit(true, true, true, true, address(splitMainV2));
    emit ControlTransfer(split, address(this), address(0));

    splitMainV2.makeSplitImmutable(split);
  }

  function testRevertIfMakeImmutableNotController() public {
    address split = createTestMutableSplit();

    vm.expectRevert();
    vm.prank(user1);

    splitMainV2.makeSplitImmutable(split);
  }
}

contract SplitMainV2DistributeETH is SplitMainV2Test {

  address internal split;

  function setUp() public override {
    super.setUp();

    split = splitMainV2.createSplit(
      address(splitWallet),
      accounts,
      percentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testDistributeETHNoDistribtuor() public {

    vm.deal(address(split), 10 ether);

    splitMainV2.distributeETH(split, accounts, percentAllocations, 0, address(0));

    assertEq(splitMainV2.getETHBalance(accounts[0]), 4 ether);
    assertEq(splitMainV2.getETHBalance(accounts[1]), 6 ether);
  }

  function testRevertIfIncorrectSplitData() public {
    address[] memory incorrectAccounts = new address[](2);
    incorrectAccounts[0] = makeAddr("user1");
    incorrectAccounts[1] = makeAddr("user2");


    vm.expectRevert();
    splitMainV2.distributeETH(split, incorrectAccounts, percentAllocations, 0, address(0));
  }

  function testDistributeETHWithDistributor() public {
    address[] memory newAccounts = new address[](2);
    newAccounts[0] = makeAddr("user1");
    newAccounts[1] = makeAddr("user2");

    address splitWithDistributor = splitMainV2.createSplit(
      address(splitWallet),
      newAccounts,
      percentAllocations,
      address(0),
      address(this),
      0
    );

    vm.deal(splitWithDistributor, 10 ether);

    assertEq(splitMainV2.getDistributor(splitWithDistributor), address(this), "invalid distributor");

    // expect to revert if called by non distributor
    vm.expectRevert();
    vm.prank(user1);
    splitMainV2.distributeETH(
      splitWithDistributor,
      newAccounts,
      percentAllocations,
      0,
      address(this)
    );

    // should not revert
    splitMainV2.distributeETH(
      splitWithDistributor,
      newAccounts,
      percentAllocations,
      0,
      address(this)
    );

  }

  function testDistributeETH0WithDistributorFee() public {
    // @TODO fuzzing for the distributor fee
    uint256 amountToDistribute = 10 ether;

    address[] memory newAccounts = new address[](2);
    newAccounts[0] = makeAddr("user1");
    newAccounts[1] = makeAddr("user2");

    address splitWithDistributorFee = splitMainV2.createSplit(
      address(splitWallet),
      newAccounts,
      percentAllocations,
      address(0),
      address(this),
      1e5
    );

    vm.deal(splitWithDistributorFee, amountToDistribute);

    splitMainV2.distributeETH(
      splitWithDistributorFee,
      newAccounts,
      percentAllocations,
      1e5,
      address(this)
    );

    assertEq(splitMainV2.getETHBalance(newAccounts[0]), 36e17);
    assertEq(splitMainV2.getETHBalance(newAccounts[1]), 54e17);
  }

}

contract SplitMainV2UpdateAndDistributeERC20 is SplitMainV2Test {

  function testUpdateAndDistributeERC20() public {
    address split = createTestMutableSplit();

    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = 200_000;
    newPercentAllocations[1] = 800_000;

    bytes32 currentSplitHash = splitMainV2.getHash(split);

    splitMainV2.updateAndDistributeERC20(
      split,
      mockERC20,
      accounts,
      newPercentAllocations,
      0,
      address(this)
    );

    bytes32 newSplitHash = splitMainV2.getHash(split);

    assertEq(currentSplitHash != newSplitHash, true, "invalid split hash");
  }

  function testRevertsIfUpdateAndDistributeERC20NonController() public {
    address split = createTestMutableSplit();

    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = 200_000;
    newPercentAllocations[1] = 800_000;

    vm.expectRevert(
      abi.encodeWithSelector(Unauthorized.selector, user1)
    );

    vm.prank(user1);
    splitMainV2.updateAndDistributeERC20(
      split,
      mockERC20,
      accounts,
      newPercentAllocations,
      0,
      address(this)
    );
  }

}

contract SplitMainV2UpdateAndDistributeETH is SplitMainV2Test {

  function testUpdateAndDistributeETH() public {
    address split = createTestMutableSplit();

    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = 200_000;
    newPercentAllocations[1] = 800_000;

    bytes32 currentSplitHash = splitMainV2.getHash(split);

    splitMainV2.updateAndDistributeETH(
      split,
      accounts,
      newPercentAllocations,
      0,
      address(this)
    );

    bytes32 newSplitHash = splitMainV2.getHash(split);

    assertEq(currentSplitHash != newSplitHash, true, "invalid split hash");
  }

  function testRevertIfUpdateAndDistributeETHNonController() public {
    address split = createTestMutableSplit();

    uint32[] memory newPercentAllocations = new uint32[](2);
    newPercentAllocations[0] = 200_000;
    newPercentAllocations[1] = 800_000;

    vm.expectRevert(
      abi.encodeWithSelector(Unauthorized.selector, user1)
    );

    vm.prank(user1);
    
    splitMainV2.updateAndDistributeETH(
      split,
      accounts,
      newPercentAllocations,
      0,
      address(this)
    );
  }

}


contract SplitMainV2DistributeERC20 is SplitMainV2Test {

  address internal split;

  function setUp() public override {
    super.setUp();
    split = splitMainV2.createSplit(
      address(splitWallet),
      accounts,
      percentAllocations,
      address(0),
      address(0),
      0
    );
  }

  function testDistributeERC20() public {
    uint256 amountToDistribute = 10 ether;

    deal(address(mockERC20), split, amountToDistribute);

    splitMainV2.distributeERC20(split, mockERC20, accounts, percentAllocations, 0, address(0));

    assertApproxEqAbs(
      splitMainV2.getERC20Balance(accounts[0], mockERC20), 
      4 ether, 
      1,
      "invalid distribution"
    );

    assertApproxEqAbs(
      splitMainV2.getERC20Balance(accounts[1], mockERC20), 
      6 ether, 
      1, 
      "invalid distritbution"
    );

  }

  function testDistributeERC20WithDistributor() public {
    uint256 amountToDistribute = 10 ether;

    address[] memory newAccounts = new address[](2);
    newAccounts[0] = makeAddr("user1");
    newAccounts[1] = makeAddr("user2");

    address splitWithDistributor = splitMainV2.createSplit(
      address(splitWallet),
      newAccounts,
      percentAllocations,
      address(0),
      address(this),
      0
    );

    deal(address(mockERC20), splitWithDistributor, amountToDistribute);

    // expect to revert if called by non distributor
    vm.expectRevert();

    vm.prank(user1);

    splitMainV2.distributeERC20(
      splitWithDistributor,
      ERC20(address(mockERC20)),
      newAccounts,
      percentAllocations,
      0,
      address(this)
    );

    // should not revert
    splitMainV2.distributeERC20(
      splitWithDistributor,
      ERC20(address(mockERC20)),
      newAccounts,
      percentAllocations,
      0,
      address(this)
    );
  }
  
  function testDistributeERC20WithDistributorFee() public {
    // @TODO fuzzing for the distributor fee
    uint256 amountToDistribute = 10 ether;

    address[] memory newAccounts = new address[](2);
    newAccounts[0] = makeAddr("user1");
    newAccounts[1] = makeAddr("user2");

    address splitWithDistributorFee = splitMainV2.createSplit(
      address(splitWallet),
      newAccounts,
      percentAllocations,
      address(0),
      address(this),
      1e5
    );

    deal(address(mockERC20), splitWithDistributorFee, amountToDistribute);

    splitMainV2.distributeERC20(
      splitWithDistributorFee,
      ERC20(address(mockERC20)),
      newAccounts,
      percentAllocations,
      1e5,
      address(this)
    );
    
    assertEq(splitMainV2.getERC20Balance(newAccounts[0], mockERC20), 36e17);
    assertEq(splitMainV2.getERC20Balance(newAccounts[1], mockERC20), 54e17);
  }
}


contract SplitMainV2Withdraw is SplitMainV2Test {

  address internal split;

  function setUp() public override {
    super.setUp();

    split = splitMainV2.createSplit(
      address(splitWallet),
      accounts,
      percentAllocations,
      address(0),
      address(0),
      0
    );
  }


  function testWithdrawETH() public {
    uint256 amountToDistribute = 10 ether;
    vm.deal(split, amountToDistribute);

    // distribute
    splitMainV2.distributeETH(
      split,
      accounts,
      percentAllocations,
      0, 
      address(0)
    );

    assertApproxEqAbs(4 ether, splitMainV2.getETHBalance(accounts[0]), 1, "incorrect split amount");
    assertApproxEqAbs(6 ether, splitMainV2.getETHBalance(accounts[1]), 1, "incorrect withdraw amount");

    // withdraw
    ERC20[] memory tokens = new ERC20[](0);
    splitMainV2.withdraw(accounts[0], 1, tokens);
    splitMainV2.withdraw(accounts[1], 1, tokens);

    assertApproxEqAbs(accounts[0].balance, 4 ether, 1, "invalid amount");
    assertApproxEqAbs(accounts[1].balance, 6 ether, 1, "invalid amount");

  }

  function testWithdrawERC20() public {
    uint256 amountToDistribute = 10 ether;

    deal(address(mockERC20), split, amountToDistribute);

    splitMainV2.distributeERC20(
      split,
      mockERC20,
      accounts,
      percentAllocations, 
      0, 
      address(0)
    );

    // withdraw
    ERC20[] memory tokens = new ERC20[](1);
    tokens[0] = mockERC20;

    assertApproxEqAbs(4 ether, splitMainV2.getERC20Balance(accounts[0], mockERC20), 2, "invalid amount");
    assertApproxEqAbs(6 ether, splitMainV2.getERC20Balance(accounts[1], mockERC20), 2, "invalid amount");

    splitMainV2.withdraw(accounts[0], 0, tokens);
    splitMainV2.withdraw(accounts[1], 0, tokens);

    assertApproxEqAbs(mockERC20.balanceOf(accounts[0]), 4 ether, 2, "invalid split");
    assertApproxEqAbs(mockERC20.balanceOf(accounts[1]), 6 ether, 2, "invalid split");
  }

}