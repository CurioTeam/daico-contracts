pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";


/// @title A token-pool that locks deposited tokens until their date of maturity.
/// @dev It regards the address "0x0" as ETH when you speficy a token.
contract CurioTimeLockPool{
    using SafeMath for uint256;

    struct LockedBalance {
      uint256 balance;
      uint256 releaseTime;
    }

    /*
      structure: lockedBalnces[owner][token] = LockedBalance(balance, releaseTime);
      token address = '0x0' stands for ETH (unit = wei)
    */
    mapping (address => mapping (address => LockedBalance[])) public lockedBalances;

    event Deposit(
        address indexed owner,
        address indexed tokenAddr,
        uint256 amount,
        uint256 releaseTime
    );

    event Withdraw(
        address indexed owner,
        address indexed tokenAddr,
        uint256 amount
    );

    /// @dev Constructor.
    constructor() public {}

    /// @dev Deposit tokens to specific account with time-lock.
    /// @param tokenAddr The contract address of a ERC20/ERC223 token.
    /// @param account The owner of deposited tokens.
    /// @param amount Amount to deposit.
    /// @param releaseTime Time-lock period.
    /// @return True if it is successful, revert otherwise.
    function depositERC20 (
        address tokenAddr,
        address account,
        uint256 amount,
        uint256 releaseTime
    ) external returns (bool) {
        require(account != address(0));
        require(tokenAddr != address(0));
        require(amount > 0);
        require(IERC20(tokenAddr).transferFrom(msg.sender, address(this), amount));

        lockedBalances[account][tokenAddr].push(LockedBalance(amount, releaseTime));
        emit Deposit(account, tokenAddr, amount, releaseTime);

        return true;
    }

    /// @dev Deposit ETH to specific account with time-lock.
    /// @param account The owner of deposited tokens.
    /// @param releaseTime Timestamp to release the fund.
    /// @return True if it is successful, revert otherwise.
    function depositETH (
        address account,
        uint256 releaseTime
    ) external payable returns (bool) {
        require(account != address(0));
        address tokenAddr = address(0);
        uint256 amount = msg.value;
        require(amount > 0);

        lockedBalances[account][tokenAddr].push(LockedBalance(amount, releaseTime));
        emit Deposit(account, tokenAddr, amount, releaseTime);

        return true;
    }

    /// @dev Release the available balance of an account.
    /// @param account An account to receive tokens.
    /// @param tokenAddr An address of ERC20/ERC223 token.
    /// @param index_from Starting index of records to withdraw.
    /// @param index_to Ending index of records to withdraw.
    /// @return True if it is successful, revert otherwise.
    function withdraw (address payable account, address tokenAddr, uint256 index_from, uint256 index_to) external returns (bool) {
        require(account != address(0));

        uint256 release_amount = 0;
        for (uint256 i = index_from; i < lockedBalances[account][tokenAddr].length && i < index_to + 1; i++) {
            if (lockedBalances[account][tokenAddr][i].balance > 0 &&
                lockedBalances[account][tokenAddr][i].releaseTime <= block.timestamp) {

                release_amount = release_amount.add(lockedBalances[account][tokenAddr][i].balance);
                lockedBalances[account][tokenAddr][i].balance = 0;
            }
        }

        require(release_amount > 0);

        if (tokenAddr == address(0)) {
            if (!account.send(release_amount)) {
                revert();
            }
            emit Withdraw(account, tokenAddr, release_amount);
            return true;
        } else {
            if (!IERC20(tokenAddr).transfer(account, release_amount)) {
                revert();
            }
            emit Withdraw(account, tokenAddr, release_amount);
            return true;
        }
    }

    /// @dev Returns total amount of balances which already passed release time.
    /// @param account An account to receive tokens.
    /// @param tokenAddr An address of ERC20/ERC223 token.
    /// @return Available balance of specified token.
    function getAvailableBalanceOf (address account, address tokenAddr)
        external
        view
        returns (uint256)
    {
        require(account != address(0));

        uint256 balance = 0;
        for(uint256 i = 0; i < lockedBalances[account][tokenAddr].length; i++) {
            if (lockedBalances[account][tokenAddr][i].releaseTime <= block.timestamp) {
                balance = balance.add(lockedBalances[account][tokenAddr][i].balance);
            }
        }
        return balance;
    }

    /// @dev Returns total amount of balances which are still locked.
    /// @param account An account to receive tokens.
    /// @param tokenAddr An address of ERC20/ERC223 token.
    /// @return Locked balance of specified token.
    function getLockedBalanceOf (address account, address tokenAddr)
        external
        view
        returns (uint256)
    {
        require(account != address(0));

        uint256 balance = 0;
        for(uint256 i = 0; i < lockedBalances[account][tokenAddr].length; i++) {
            if(lockedBalances[account][tokenAddr][i].releaseTime > block.timestamp) {
                balance = balance.add(lockedBalances[account][tokenAddr][i].balance);
            }
        }
        return balance;
    }

    /// @dev Returns next release time of locked balances.
    /// @param account An account to receive tokens.
    /// @param tokenAddr An address of ERC20/ERC223 token.
    /// @return Timestamp of next release.
    function getNextReleaseTimeOf (address account, address tokenAddr)
        external
        view
        returns (uint256)
    {
        require(account != address(0));

        uint256 nextRelease = 2**256 - 1;
        for (uint256 i = 0; i < lockedBalances[account][tokenAddr].length; i++) {
            if (lockedBalances[account][tokenAddr][i].releaseTime > block.timestamp &&
               lockedBalances[account][tokenAddr][i].releaseTime < nextRelease) {

                nextRelease = lockedBalances[account][tokenAddr][i].releaseTime;
            }
        }

        /* returns 0 if there are no more locked balances. */
        if (nextRelease == 2**256 - 1) {
            nextRelease = 0;
        }
        return nextRelease;
    }
}


