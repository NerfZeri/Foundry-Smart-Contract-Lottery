// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/interactions.s.sol";

contract RaffleTest is Test {
    event EnteredRaffle(address indexed player);
    
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 enteranceFee; 
    uint256 interval;
    address vrfCoordinator; 
    bytes32 gasLane;
    uint64 subscriptionId; 
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;
    
    modifier enteredWithTime() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier entered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
        _;
    }

    modifier skipFork() {
        if(block.chainid != 31337){
            return;
        }
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (enteranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link, deployerKey) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleStartsOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsIfNotEnoughEthSent() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testAddsToArray() public entered {
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEnterance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testCantEnterRaffleIfNotOpen() public enteredWithTime {
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testCheckUpkeepFalseIfNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepFalseIfNotOpen() public enteredWithTime { 
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(raffleState == Raffle.RaffleState.CALCULATING_WINNER);
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfTimeHasntPassed() public entered {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public enteredWithTime {
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckupkeepIsNotTrue() public enteredWithTime {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        vm.expectRevert(abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, raffleState));
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public enteredWithTime {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    function testFullfillRandomWordsOnlyAfterUpkeep(uint256 randomRequestId) public enteredWithTime skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksWinnerAndResets() public enteredWithTime skipFork{
        uint256 additionalEnterants = 5;
        uint256 startingIndex = 1;
        for(uint256 i = startingIndex; i< startingIndex + additionalEnterants; i++){
            address player = address(uint160(i));
            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: enteranceFee}();
        }

        uint256 prize = enteranceFee * (additionalEnterants + 1);
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(raffle.getRecentWinner().balance == prize + STARTING_BALANCE - enteranceFee);
    }
}