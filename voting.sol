// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

contract Voting is KeeperCompatibleInterface {
    struct Vote {
        uint id;
        string question;
        string[] options;
        mapping(uint => uint) votes;
        mapping(address => bool) hasVoted; // Track if an address has voted
        uint endTime;
        uint minVotes;
        bool isEnded;
        bool exists; // Added to check if vote exists
    }

    Vote[] public votes;
    mapping(address => bool) public isAdmin;
    address[] public adminList; // List of admin addresses

    event VoteCreated(uint indexed voteId, string question, string[] options, uint endTime);
    event Voted(uint indexed voteId, address indexed voter, uint optionIndex, uint newVoteCount);
    event VoteEnded(uint indexed voteId, string winner);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Only admin can perform this action.");
        _;
    }

    constructor() {
        isAdmin[msg.sender] = true; // Deployer is the admin
        adminList.push(msg.sender); // Add deployer to admin list
        emit AdminAdded(msg.sender);
    }

    function addAdmin(address newAdmin) public onlyAdmin {
        require(!isAdmin[newAdmin], "Address is already an admin.");
        isAdmin[newAdmin] = true;
        adminList.push(newAdmin); // Add new admin to admin list
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address admin) public onlyAdmin {
        require(msg.sender != admin, "Cannot remove yourself as admin.");
        require(isAdmin[admin], "Address is not an admin.");
        isAdmin[admin] = false;
        emit AdminRemoved(admin);

        // Remove admin from admin list
        for (uint i = 0; i < adminList.length; i++) {
            if (adminList[i] == admin) {
                adminList[i] = adminList[adminList.length - 1];
                adminList.pop();
                break;
            }
        }
    }

    function getAdmins() public view returns (address[] memory) {
        return adminList;
    }

    function createVote(string memory question, string[] memory options, uint endTime, uint minVotes) public onlyAdmin {
        uint voteId = votes.length;
        votes.push();
        Vote storage v = votes[votes.length - 1];
        v.id = voteId;
        v.question = question;
        v.options = options;
        v.endTime = endTime;
        v.minVotes = minVotes;
        v.isEnded = false;
        v.exists = true; // Mark the vote as existing

        emit VoteCreated(voteId, question, options, endTime);
    }

    function vote(uint voteId, uint optionIndex) public {
        require(votes[voteId].exists, "Vote does not exist.");
        Vote storage voteInstance = votes[voteId];
        require(!voteInstance.isEnded, "Voting has ended.");
        require(optionIndex < voteInstance.options.length, "Invalid option index.");
        require(!voteInstance.hasVoted[msg.sender], "You have already voted in this vote.");

        voteInstance.votes[optionIndex]++;
        voteInstance.hasVoted[msg.sender] = true; // Mark the user as voted
        emit Voted(voteId, msg.sender, optionIndex, voteInstance.votes[optionIndex]);

        if (block.timestamp >= voteInstance.endTime) {
            endVote(voteId);
        }
    }

    function endVote(uint voteId) public onlyAdmin {
        require(votes[voteId].exists, "Vote does not exist.");
        Vote storage voteInstance = votes[voteId];
        require(!voteInstance.isEnded, "Vote has already ended.");

        voteInstance.isEnded = true;

        uint maxVotes = 0;
        uint winningOption = 0;
        for (uint i = 0; i < voteInstance.options.length; i++) {
            if (voteInstance.votes[i] > maxVotes) {
                maxVotes = voteInstance.votes[i];
                winningOption = i;
            }
        }
        emit VoteEnded(voteId, voteInstance.options[winningOption]);
    }

    function getResults(uint voteId) public view returns (string[] memory options, uint[] memory results) {
        require(votes[voteId].exists, "Vote does not exist.");
        Vote storage voteInstance = votes[voteId];
        
        uint[] memory voteCounts = new uint[](voteInstance.options.length);
        for (uint i = 0; i < voteInstance.options.length; i++) {
            voteCounts[i] = voteInstance.votes[i];
        }

        return (voteInstance.options, voteCounts);
    }

    function getVoteDetails(uint voteId) public view returns (string memory question, string[] memory options, uint endTime, uint minVotes, bool isEnded, uint[] memory voteCounts) {
        require(votes[voteId].exists, "Vote does not exist.");
        Vote storage voteInstance = votes[voteId];
        
        uint[] memory counts = new uint[](voteInstance.options.length);
        for (uint i = 0; i < voteInstance.options.length; i++) {
            counts[i] = voteInstance.votes[i];
        }

        return (voteInstance.question, voteInstance.options, voteInstance.endTime, voteInstance.minVotes, voteInstance.isEnded, counts);
    }

    function getVotesLength() public view returns (uint) {
        return votes.length;
    }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = false;
        for (uint256 i = 0; i < votes.length; i++) {
            if (block.timestamp >= votes[i].endTime && !votes[i].isEnded) {
                upkeepNeeded = true;
                break;
            }
        }

        // Ensure to return a value for all code paths
        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        for (uint256 i = 0; i < votes.length; i++) {
            if (block.timestamp >= votes[i].endTime && !votes[i].isEnded) {
                endVote(i);
            }
        }
    }
}
