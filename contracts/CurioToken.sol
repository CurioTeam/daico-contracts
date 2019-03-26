pragma solidity ^0.5.3;

import { ERC777ERC20BaseToken } from "./ERC777/ERC777ERC20BaseToken.sol";
import { Ownable } from "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/**
 * @title CurioToken
 * @dev ERC777 token with ERC20 compatibility.
 */
contract CurioToken is ERC777ERC20BaseToken, Ownable {
    uint256 public constant INITIAL_SUPPLY = 100000000 * (10 ** 18);

    event ERC20Enabled();
    event ERC20Disabled();

    constructor(address[] memory defaultOperators) public ERC777ERC20BaseToken("CurioToken", "CUR", 1, defaultOperators) {
        doMint(msg.sender, INITIAL_SUPPLY, "", "");
    }

    function disableERC20() public onlyOwner {
        mErc20compatible = false;
        setInterfaceImplementation("ERC20Token", address(0));
        emit ERC20Disabled();
    }

    function enableERC20() public onlyOwner {
        mErc20compatible = true;
        setInterfaceImplementation("ERC20Token", address(this));
        emit ERC20Enabled();
    }

    function doMint(address tokenHolder, uint256 amount, bytes memory data, bytes memory operatorData) private {
        requireMultiple(amount);
        mTotalSupply = mTotalSupply.add(amount);
        mBalances[tokenHolder] = mBalances[tokenHolder].add(amount);

        callRecipient(msg.sender, address(0), tokenHolder, amount, data, operatorData, true);

        emit Minted(msg.sender, tokenHolder, amount, data, operatorData);
        if (mErc20compatible) {
            emit Transfer(address(0), tokenHolder, amount);
        }
    }
}
