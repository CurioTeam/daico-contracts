pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "./ICurioDaicoPool.sol";


/// @title Voting contract connected to a CurioDaicoPool. Token holders can make proposals and vote them.
/// @dev This contract can change the TAP value of the CurioDaicoPool and can destruct it as well.
contract CurioDaicoVoting{
    using SafeMath for uint256;

    address public votingTokenAddr;
    address payable public poolAddr;
    mapping (uint256 => mapping(address => uint256)) public deposits;
    mapping (uint => bool) public queued;

    uint256 proposalCostWei = 1 * 10**18;

    uint256 public constant VOTING_PERIOD = 14 days;

    struct Proposal {
        uint256 start_time;
        uint256 end_time;
        Subject subject;
        string reason;
        mapping (bool => uint256) votes;
        uint256 voter_count;
        bool isFinalized;
        uint256 tapMultiplierRate;
    }

    Proposal[] public proposals;
    uint public constant PROPOSAL_EMPTY = 0;

    enum Subject {
        RaiseTap,
        Destruction
    }

    event Vote(
        address indexed voter,
        uint256 amount
    );

    event ReturnDeposit(
        address indexed voter,
        uint256 amount
    );

    event ProposalRaised(
        address indexed proposer,
        string subject
    );

    /// @dev Constructor.
    /// @param _votingTokenAddr The contract address of ERC20
    /// @param _poolAddr The contract address of DaicoPool
    constructor (
        address _votingTokenAddr,
        address payable _poolAddr
    ) public {
        require(_votingTokenAddr != address(0));
        require(_poolAddr != address(0));
        votingTokenAddr = _votingTokenAddr;
        poolAddr = _poolAddr;

        // Insert an empty proposal as the header in order to make index 0 to be missing number.
        Proposal memory proposal;
        proposal.subject = Subject.RaiseTap;
        proposal.reason = "PROPOSAL_HEADER";
        proposal.start_time = block.timestamp -1;
        proposal.end_time = block.timestamp -1;
        proposal.voter_count = 0;
        proposal.isFinalized = true;

        proposals.push(proposal);
        assert(proposals.length == 1);
    }

    /// @dev Make a TAP raising proposal. It costs certain amount of ETH.
    /// @param _reason The reason to raise the TAP. This field can be an URL of a WEB site.
    /// @param _tapMultiplierRate TAP increase rate. From 101 to 200. i.e. 150 = 150% .
    function addRaiseTapProposal (
        string calldata _reason,
        uint256 _tapMultiplierRate
    ) external payable returns(uint256) {
        require(!queued[uint(Subject.RaiseTap)]);
        require(100 < _tapMultiplierRate && _tapMultiplierRate <= 200);

        uint256 newID = addProposal(Subject.RaiseTap, _reason);
        proposals[newID].tapMultiplierRate = _tapMultiplierRate;

        queued[uint(Subject.RaiseTap)] = true;
        emit ProposalRaised(msg.sender, "RaiseTap");
    }

    /// @dev Make a self destruction proposal. It costs certain amount of ETH.
    /// @param _reason The reason to destruct the pool. This field can be an URL of a WEB site.
    function addDestructionProposal (string calldata _reason) external payable returns(uint256) {
        require(!queued[uint(Subject.Destruction)]);

        addProposal(Subject.Destruction, _reason);

        queued[uint(Subject.Destruction)] = true;
        emit ProposalRaised(msg.sender, "SelfDestruction");
    }

    /// @dev Vote yes or no to current proposal.
    /// @param amount Token amount to be voted.
    function vote (bool agree, uint256 amount) external {
        require(IERC20(votingTokenAddr).transferFrom(msg.sender, address(this), amount));
        uint256 pid = this.getCurrentVoting();
        require(pid != PROPOSAL_EMPTY);

        require(proposals[pid].start_time <= block.timestamp);
        require(proposals[pid].end_time >= block.timestamp);

        if (deposits[pid][msg.sender] == 0) {
            proposals[pid].voter_count = proposals[pid].voter_count.add(1);
        }

        deposits[pid][msg.sender] = deposits[pid][msg.sender].add(amount);
        proposals[pid].votes[agree] = proposals[pid].votes[agree].add(amount);
        emit Vote(msg.sender, amount);
    }

    /// @dev Finalize the current voting. It can be invoked when the end time past.
    /// @dev Anyone can invoke this function.
    function finalizeVoting () external {
        uint256 pid = this.getCurrentVoting();
        require(pid != PROPOSAL_EMPTY);
        require(proposals[pid].end_time <= block.timestamp);
        require(!proposals[pid].isFinalized);

        proposals[pid].isFinalized = true;

        if (isSubjectRaiseTap(pid)) {
            queued[uint(Subject.RaiseTap)] = false;
            if (isPassed(pid)) {
                ICurioDaicoPool(poolAddr).raiseTap(proposals[pid].tapMultiplierRate);
            }

        } else if (isSubjectDestruction(pid)) {
            queued[uint(Subject.Destruction)] = false;
            if (isPassed(pid)) {
                ICurioDaicoPool(poolAddr).selfDestruction();
            }
        }
    }

    /// @dev Return all tokens which specific account used to vote so far.
    /// @param account An address that deposited tokens. It also be the receiver.
    function returnToken (address account) external returns(bool) {
        uint256 amount = 0;

        for (uint256 pid = 0; pid < proposals.length; pid++) {
            if(!proposals[pid].isFinalized){
              break;
            }
            amount = amount.add(deposits[pid][account]);
            deposits[pid][account] = 0;
        }

        if(amount <= 0){
           return false;
        }

        require(IERC20(votingTokenAddr).transfer(account, amount));
        emit ReturnDeposit(account, amount);

        return true;
    }

    /// @dev Return tokens to multiple addresses.
    /// @param accounts Addresses that deposited tokens. They also be the receivers.
    function returnTokenMulti (address[] calldata accounts) external {
        for(uint256 i = 0; i < accounts.length; i++){
            this.returnToken(accounts[i]);
        }
    }

    /// @dev Return the index of on going voting.
    /// @return The index of voting.
    function getCurrentVoting () public view returns(uint256) {
        for (uint256 i = 0; i < proposals.length; i++) {
            if (!proposals[i].isFinalized) {
                return i;
            }
        }
        return PROPOSAL_EMPTY;
    }

    /// @dev Check if a proposal has been agreed or not.
    /// @param pid Index of a proposal.
    /// @return True if the proposal passed. False otherwise.
    function isPassed (uint256 pid) public view returns(bool) {
        require(proposals[pid].isFinalized);
        uint256 ayes = getAyes(pid);
        uint256 nays = getNays(pid);
        uint256 absent = IERC20(votingTokenAddr).totalSupply().sub(ayes).sub(nays);
        return (ayes > nays.add(absent.div(6)));
    }

    /// @dev Check if a voting has started or not.
    /// @param pid Index of a proposal.
    /// @return True if the voting already started. False otherwise.
    function isStarted (uint256 pid) public view returns(bool) {
        if (pid > proposals.length) {
            return false;
        } else if (block.timestamp >= proposals[pid].start_time) {
            return true;
        }
        return false;
    }

    /// @dev Check if a voting has ended or not.
    /// @param pid Index of a proposal.
    /// @return True if the voting already ended. False otherwise.
    function isEnded (uint256 pid) public view returns(bool) {
        if (pid > proposals.length) {
            return false;
        } else if (block.timestamp >= proposals[pid].end_time) {
            return true;
        }
        return false;
    }

    /// @dev Return the reason of a proposal.
    /// @param pid Index of a proposal.
    /// @return Text of the reason that is set when the proposal made.
    function getReason (uint256 pid) external view returns(string memory) {
        require(pid < proposals.length);
        return proposals[pid].reason;
    }

    /// @dev Check if a proposal is about TAP raising or not.
    /// @param pid Index of a proposal.
    /// @return True if it's TAP raising. False otherwise.
    function isSubjectRaiseTap (uint256 pid) public view returns(bool) {
        require(pid < proposals.length);
        return proposals[pid].subject == Subject.RaiseTap;
    }

    /// @dev Check if a proposal is about self destruction or not.
    /// @param pid Index of a proposal.
    /// @return True if it's self destruction. False otherwise.
    function isSubjectDestruction (uint256 pid) public view returns(bool) {
        require(pid < proposals.length);
        return proposals[pid].subject == Subject.Destruction;
    }

    /// @dev Return the number of voters take part in a specific voting.
    /// @param pid Index of a proposal.
    /// @return The number of voters.
    function getVoterCount (uint256 pid) external view returns(uint256) {
        require(pid < proposals.length);
        return proposals[pid].voter_count;
    }

    /// @dev Return the number of votes that agrees the proposal.
    /// @param pid Index of a proposal.
    /// @return The number of votes that agrees the proposal.
    function getAyes (uint256 pid) public view returns(uint256) {
        require(pid < proposals.length);
        require(proposals[pid].isFinalized);
        return proposals[pid].votes[true];
    }

    /// @dev Return the number of votes that disagrees the proposal.
    /// @param pid Index of a proposal.
    /// @return The number of votes that disagrees the proposal.
    function getNays (uint256 pid) public view returns(uint256) {
        require(pid < proposals.length);
        require(proposals[pid].isFinalized);
        return proposals[pid].votes[false];
    }

    /// @dev Internal function to add a proposal into the voting queue.
    /// @param _subject Subject of the proposal. Can be TAP raising or self destruction.
    /// @param _reason Reason of the proposal. This field can be an URL of a WEB site.
    /// @return Index of the proposal.
    function addProposal (Subject _subject, string memory _reason) internal returns(uint256) {
        require(msg.value == proposalCostWei);
        require(ICurioDaicoPool(poolAddr).isStateProjectInProgress());
        poolAddr.transfer(msg.value);

        Proposal memory proposal;
        proposal.subject = _subject;
        proposal.reason = _reason;
        proposal.start_time = block.timestamp;
        proposal.end_time = block.timestamp + VOTING_PERIOD;
        proposal.voter_count = 0;
        proposal.isFinalized = false;

        proposals.push(proposal);
        uint256 newID = proposals.length - 1;
        return newID;
    }
}
