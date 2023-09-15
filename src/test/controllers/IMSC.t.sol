// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;
import "forge-std/Test.sol";
import {
    ImmutableSplitControllerFactory,
    ImmutableSplitController
} from "src/controllers/ImmutableSplitControllerFactory.sol";
import {ISplitMain} from "src/interfaces/ISplitMain.sol";


contract IMSC is Test {
    error Initialized();

    address internal SPLIT_MAIN_GOERLI = 0x2ed6c4B5dA6378c7897AC67Ba9e43102Feb694EE;
    uint256 public constant PERCENTAGE_SCALE = 1e6;

    ImmutableSplitControllerFactory public factory;
    ImmutableSplitController public cntrlImpl;

    ImmutableSplitController public controller;

    address[] accounts;
    uint32[]  percentAllocations;

    address[] controllerAccounts;
    uint32[] controllerPercentAllocations;

    address split;

    function setUp() public {
        uint256 goerliBlock = 8_529_931;
        vm.createSelectFork(getChain("goerli").rpcUrl, goerliBlock);

        factory = new ImmutableSplitControllerFactory(SPLIT_MAIN_GOERLI);
        cntrlImpl = factory.controller();

        accounts = new address[](2);
        accounts[0] = makeAddr("accounts0");
        accounts[1] = makeAddr("accounts1");

        percentAllocations = new uint32[](2);
        percentAllocations[0] = 400_000;
        percentAllocations[1] = 600_000;

        controllerAccounts = new address[](3);
        controllerAccounts[0] = makeAddr("accounts0");
        controllerAccounts[1] = makeAddr("accounts1");
        controllerAccounts[2] = makeAddr("accounts3");

        controllerPercentAllocations = new uint32[](3);
        controllerPercentAllocations[0] = 400_000;
        controllerPercentAllocations[1] = 300_000;
        controllerPercentAllocations[2] = 300_000;

        bytes32 deploymentSalt = keccak256(abi.encodePacked(uint256(64)));
        
        // predict controller address
        address predictedControllerAddress = factory.predictSplitControllerAddress(
            controllerAccounts,
            controllerPercentAllocations,
            0,
            deploymentSalt
        );

        split = ISplitMain(SPLIT_MAIN_GOERLI).createSplit(
            accounts,
            percentAllocations,
            0,
            predictedControllerAddress
        );

        // deploy controller 
        controller = factory.createController(
            split,
            controllerAccounts,
            controllerPercentAllocations,
            0,
            deploymentSalt
        );
    }


    function testCannot_DoubleInitialiseIMSC() public {
        vm.expectRevert(
            Initialized.selector
        );
        
        controller.init(address(0x3));
    }

    function testCan_getSplitMain() public {
        assertEq(controller.splitMain(), SPLIT_MAIN_GOERLI, "valid splitMain address");
    }

    function testCan_getDistributorFee() public {
        assertEq(controller.distributorFee(), 0 , "invalid distributor fee");
        
        uint32 maxDistributorFee = 1e5;

        ImmutableSplitController customController = factory.createController(
            split,
            controllerAccounts,
            controllerPercentAllocations,
            maxDistributorFee,
            keccak256(abi.encodePacked(uint256(640)))
        );

        assertEq(
            customController.distributorFee(),
            maxDistributorFee,
            "invalid distributor fee"
        );
    }

    function testCan_getSplitConfiguration() public {
        (
            address[] memory localAccounts,
            uint32[] memory localPercentAllocations
        ) = controller.getNewSplitConfiguration();

        assertEq(
            localAccounts, controllerAccounts, "invalid accounts"
        ); 

        assertEq(
            localPercentAllocations.length,
            controllerPercentAllocations.length,
            "unequal length percent allocations"
        );

        for(uint i; i < localPercentAllocations.length; i++) {
            assertEq(
                uint256(localPercentAllocations[i]), 
                uint256(controllerPercentAllocations[i]),
                "invalid percentAllocations"
            );
        }
    }

    function testCan_getSplit() public {
        assertEq(
            controller.split(),
            split
        );
    }

    function testCan_updateSplit() public {
        controller.updateSplit();

        assertEq(
            ISplitMain(SPLIT_MAIN_GOERLI).getHash(split),
            _hashSplit(controllerAccounts, controllerPercentAllocations, 0),
            "invalid split hash"
        );
    }

    function testFuzz_updateSplit(
        uint256 splitSeed,
        uint256 controllerSeed,
        uint8 splitSize,
        uint8 controllerSize
    ) public {
        vm.assume(splitSeed != controllerSeed);
        vm.assume(splitSize > 1);
        vm.assume(controllerSize > 1);

        address[] memory splitterAccts = _generateAddresses(splitSeed, splitSize);
        address[] memory ctrllerAccounts = _generateAddresses(controllerSeed, controllerSize);

        uint32[] memory splitterPercentAlloc = _generatePercentAlloc(splitSize);
        uint32[] memory ctrllerPercentAlloc = _generatePercentAlloc(controllerSize);

        bytes32 deploymentSalt = keccak256(abi.encodePacked(uint256(604)));

        // predict controller address
        address predictedControllerAddress = factory.predictSplitControllerAddress(
            ctrllerAccounts,
            ctrllerPercentAlloc,
            0,
            deploymentSalt
        );

        // create split
        address fuzzSplit = ISplitMain(SPLIT_MAIN_GOERLI).createSplit(
            splitterAccts,
            splitterPercentAlloc,
            0,
            predictedControllerAddress
        );

        // create controller
        controller = factory.createController(
            fuzzSplit,
            ctrllerAccounts,
            ctrllerPercentAlloc,
            0,
            deploymentSalt
        );

        // get current split hash
        bytes32 currentSplitHash = ISplitMain(SPLIT_MAIN_GOERLI).getHash(fuzzSplit);
        // update split
        controller.updateSplit();

        bytes32 newSplitHash = ISplitMain(SPLIT_MAIN_GOERLI).getHash(fuzzSplit);

        bytes32 calculatedSplitHash = _hashSplit(
            ctrllerAccounts,
            ctrllerPercentAlloc,
            0
        );

        assertTrue(currentSplitHash != newSplitHash, "update split hash");
        assertEq(calculatedSplitHash, newSplitHash, "split hash equal");
    }

    function _hashSplit(
        address[] memory accts,
        uint32[] memory percentAlloc,
        uint32 distributorFee
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(accts, percentAlloc, distributorFee));
    }

    
    function _generateAddresses(
        uint256 _seed,
        uint256 size
    ) internal pure returns (address[] memory accts) {
        accts = new address[](size);
        uint160 seed = uint160(uint256(keccak256(abi.encodePacked(_seed))));
        for(uint160 i ; i < size; i++) {
            accts[i] = address(seed);
            seed += 1;
        }
    }

    function _generatePercentAlloc(
        uint256 size
    ) internal pure returns (uint32[] memory alloc) {

        alloc = new uint32[](size);
        for (uint i; i < size; i++) {
            alloc[i] = uint32(PERCENTAGE_SCALE / size);
        }

        if (PERCENTAGE_SCALE % size != 0) {
            alloc[size - 1] += uint32(PERCENTAGE_SCALE % size);
        }
    }

}