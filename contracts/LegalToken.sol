pragma solidity ^0.4.15;

import "./zeppelin-solidity/contracts/token/MintableToken.sol";
import "./zeppelin-solidity/contracts/token/LimitedTransferToken.sol";
import "./zeppelin-solidity/contracts/token/VestedToken.sol";
import "./LegalLazyScheduler.sol";
/**
* @title LegalToken
* @author Marco Oesch <marco.oesch@crea-soft.ch>
* @notice The LEGAL token lies at the heart of the SmartOne ecosystem. Its main role consists in
* @notice the embodiment of a right: The right to membership of the ecosystem.
* @notice Alongside membership, the LEGAL token also serves as a license to use the SmartOne protocols. These enable token holders to access legal services, including the common
* regulatory requirements of Anti-Money Laundering (AML) and Know Your Customer (KYC) processes, through blockchain technology.
* @dev The main functionalities provided by this contract:
* @dev OpenZeppelin contracts were used for base token functionalities
* @dev - Tokens can not be transfered until auditing phase finishes
* @dev - The bonus tokens assigned to founders and teams are limited through OpenZeppelin's VestedToken contract.
* @dev - New tokens will be minted every month to compensate inflation. The minted tokens will used to reward rated publications on SKUANI platform.
*/
contract LegalToken is LegalLazyScheduler, MintableToken, VestedToken {
    /**
    * The name of the token
    */
    bytes32 public name;

    /**
    * The symbol used for exchange
    */
    bytes32 public symbol;

    /**
    * Use to convert to number of tokens.
    */
    uint public decimals = 18;

    /**
    * The yearly expected inflation rate in base points.
    */
    uint32 public inflationCompBPS;

    /**
    * The tokens are locked until the end of the TGE.
    * The contract can release the tokens if TGE successful. If false we are in transfer lock up period.
    */
    bool public released = false;

    /**
    * Annually new minted tokens will be transferred to this wallet.
    * Publications will be rewarded with funds (incentives).  
    */
    address public rewardWallet;

    /**
    * Name and symbol were updated. 
    */
    event UpdatedTokenInformation(bytes32 newName, bytes32 newSymbol);

    /**
    * @dev Constructor that gives msg.sender all of existing tokens. 
    */
    function LegalToken(address _rewardWallet, uint32 _inflationCompBPS, uint32 _inflationCompInterval) onlyOwner public {
        setTokenInformation("Legal Token", "LGL");
        totalSupply = 0;        
        rewardWallet = _rewardWallet;
        inflationCompBPS = _inflationCompBPS;
        registerIntervalCall(_inflationCompInterval, mintInflationPeriod);
    }    

    /**
    * This function allows the token owner to rename the token after the operations
    * have been completed and then point the audience to use the token contract.
    */
    function setTokenInformation(bytes32 _name, bytes32 _symbol) onlyOwner public {
        name = _name;
        symbol = _symbol;
        UpdatedTokenInformation(name, symbol);
    }

    /**
    * Mint new tokens for the predefined inflation period and assign them to the reward wallet. 
    */
    function mintInflationPeriod() private {
        uint256 tokensToMint = totalSupply.mul(inflationCompBPS).div(10000);
        totalSupply = totalSupply.add(tokensToMint);
        balances[rewardWallet] = balances[rewardWallet].add(tokensToMint);
        Mint(rewardWallet, tokensToMint);
        Transfer(0x0, rewardWallet, tokensToMint);
    }     
    
    function setRewardWallet(address _rewardWallet) public onlyOwner {
        rewardWallet = _rewardWallet;
    }

    /**
    * Limit token transfer until the TGE is over.
    */
    modifier tokenReleased(address _sender) {
        require(released);
        _;
    }

    /**
    * This will make the tokens transferable
    */
    function releaseTokenTransfer() public onlyOwner {
        released = true;
    }

    // error: canTransfer(msg.sender, _value)
    function transfer(address _to, uint _value) public tokenReleased(msg.sender) intervalTrigger returns (bool success) {
        // Calls StandardToken.transfer()
        // error: super.transfer(_to, _value);
        return super.transfer(_to, _value);
    }

    function transferFrom(address _from, address _to, uint _value) public tokenReleased(_from) intervalTrigger returns (bool success) {
        // Calls StandardToken.transferForm()
        return super.transferFrom(_from, _to, _value);
    }

    function approve(address _spender, uint256 _value) public tokenReleased(msg.sender) intervalTrigger returns (bool) {
        // calls StandardToken.approve(..)
        return super.approve(_spender, _value);
    }

    function allowance(address _owner, address _spender) public constant returns (uint256 remaining) {
        // calls StandardToken.allowance(..)
        return super.allowance(_owner, _spender);
    }

    function increaseApproval (address _spender, uint _addedValue) public tokenReleased(msg.sender) intervalTrigger returns (bool success) {
        // calls StandardToken.increaseApproval(..)
        return super.increaseApproval(_spender, _addedValue);
    }

    function decreaseApproval (address _spender, uint _subtractedValue) public tokenReleased(msg.sender) intervalTrigger returns (bool success) {
        // calls StandardToken.decreaseApproval(..)
        return super.decreaseApproval(_spender, _subtractedValue);
    }
}
