pragma solidity ^0.4.15;

import "./LegalToken.sol";

contract LegalTokenMock is LegalToken {
    /**
    * @dev Contructor that gives msg.sender all of existing tokens. 
    */
    function LegalTokenMock(address _mockAccount, uint256 _mockBalance,  address _rewardWallet, uint32 _inflationCompBPS, uint32 _inflationCompInterval)
    LegalToken(_rewardWallet, _inflationCompBPS, _inflationCompInterval) 
    {
        balances[_mockAccount] = _mockBalance;
        totalSupply = _mockBalance;
    }
}