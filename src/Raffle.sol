// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts@0.8.0/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts@0.8.0/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    // custom error
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpKeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /** Type decoration */
    // create enum type to manage the state of the contract
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
    }
    // state variable

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORLD = 1;

    uint256 private immutable i_entranceFee;
    bytes32 private immutable i_gasLame;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint256 private immutable i_interval;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    event RaffleEnter(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 entranceFee,
        bytes32 gasLame,
        address vrfCoordinator,
        uint256 interval,
        uint64 subscriptionId,
        uint32 callBackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_gasLame = gasLame;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_callBackGasLimit = callBackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // Emit an event when we update a dynamic array or mapping
        // Named events with the function name reversed
        emit RaffleEnter(msg.sender);
    }

    /**
     * @dev This is a function that the chainlink automation Node will call
     * to see if it's time to perform an upkeep
     * function will return true if the following condition meet:
     * 1. The raffle is in the open state
     * 2. The time since the last raffle is greater than the interval
     * 3. The contract has ETH
     * 4. There is at least one player in the raffle
     * 5. The contract has enough LINK to pay for the upkeep
     */
    function checkUpkeep(
        bytes memory /* checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /** performData*/) {
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayer = s_players.length > 0;
        upkeepNeeded = isOpen && timeHasPassed && hasBalance && hasPlayer;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        // check to see if enough time has passed
        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING;
        i_vrfCoordinator.requestRandomWords(
            i_gasLame,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callBackGasLimit,
            NUM_WORLD
        );
    }

    // Follow the CEI partern: Check, Effect, Interact
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // pick a winner
        uint256 winnerIndex = randomWords[0] % s_players.length;
        address payable winner = s_players[winnerIndex];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        // reset the players array
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        // emit an event
        emit PickedWinner(winner);

        // transfer the money to the winner
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }
}
