   // SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./External/SafeMathUpgradeable.sol";
import "./External/PausableUpgradeable.sol";
import "./External/IERC20Upgradeable.sol";
import "./External/ReentrancyGuardUpgradeable.sol";
import "./External/Initializable.sol";
import "./External/OwnableUpgradeable.sol";
import "./External/IERC20.sol";


/* @title Staking Pool Contract
 * Open Zeppelin Pausable  */

contract Stakingpool is Initializable,ReentrancyGuardUpgradeable,PausableUpgradeable{
  
  using SafeMathUpgradeable for uint;
  
  uint public StakePeriod;
  
  address private owner;

  IERC20 mchtoken;
  IERC20Upgradeable mcftoken;
  
  
 /** @dev track total current stake yields of a user */
   mapping(address => uint) public currentstakeyields;
   
   /** @dev track Stakedbalances of user*/
  mapping(address => uint) public stakedBalances;
  
  /** @dev track StakedShares of user */
  mapping(address => uint) public stakedShares;
  
  /** @dev track total staked amount of tokens of all users */
  uint public totalStakedMcH;
  
  /** @dev track total staked value of all users */
  uint public totalStakedamount;
  
 /** @dev track Daily Rate of Investment */
 mapping(address => uint) public DROI;
  
 /** @dev track Monthly Rate of Investment */
  mapping(address => uint) public MROI;
  
 /** @dev track Annual Rate of Investment */ 
  mapping(address => uint) public ROI;
  
  /** @dev track claimable tokens */ 
  mapping(address => uint) public claimable;
  
  /** @dev track vested tokens */  
  mapping(address => uint) public vested;
  
   /** @dev track users
    * users must be tracked in this array because mapping is not iterable */
  address[] public users;
  
   /** @dev track index by address added to users */
  mapping(address => uint) private userIndex;
  
 
 /** @dev trigger notification of staked amount
    * @param sender       msg.sender for the transaction
    * @param amount       msg.value for the transaction
    */
  event NotifyStaked(address sender, uint amount);
  
  /** @dev trigger notification of unstaked amount
    * @param sender       msg.sender for the transaction
    * @param amount       msg.value for the transaction
    */
  event NotifyUnStaked(address sender, uint amount);


  // @dev trigger notification of claimed amount
  event Notifyclaimed(address sender,uint Balance);
  
  mapping(address=> uint) internal creationTime;
  
 
  modifier onlyOwner {
        require(
            msg.sender == owner,
            "Only owner can call this function."
        );
        _;
    }
  
     /**
     * @dev Throws if called before stakingperiod
     */
    modifier onlyAfter() {
        
       require(block.timestamp > StakePeriod ,"StakePeriod not completed");
        _;
    }
   

 // @dev contract Initializable
    
    function Initialize (address _mchtoken, address _mcftoken) public initializer {
    
     mchtoken = IERC20(_mchtoken);
     mcftoken = IERC20Upgradeable(_mcftoken);
     owner = msg.sender;
     StakePeriod = 15 days;
    
    }

  /************************ USER MANAGEMENT ***********************/

  /** @dev test if user is in current user list
    * @param user address of user to test if in list
    * @return true if user is on record, otherwise false
    */
  function isUser(address user)
       internal
       view
       returns(bool, uint256)
   {
       for (uint256 i = 0; i < users.length; i += 1){
           if (user == users[i]) return (true, i);
       }
       return (false, 0);
   }
    
    /** @dev add a user to users array
    * @param user address of user to add to the list
    */
  
    function addUser(address user)
       internal
   {
       (bool _isUser, ) = isUser(user);
       if(!_isUser) users.push(user);
   }
   
   /** @dev remove a user from users array
    * @param user address of user to remove from the list
    */
    
   function removeUser(address user)
       internal
   {
       (bool isUser, uint256 i) = isUser(user);
       if(isUser){
           users[i] = users[users.length - 1];
           users.pop();
       }
   }
  /************************ USER MANAGEMENT ***********************/

  
   /** @dev stake funds to Contract
    */
  function Approvestake(uint amount) external whenNotPaused {
     
      require(amount > 0);
      
     // Transfer Mock  tokens to this contract for staking
     mchtoken.transferFrom(msg.sender, address(this), amount);
    
    if(stakedBalances[msg.sender] == 0) addUser(msg.sender);
       stakedBalances[msg.sender] = stakedBalances[msg.sender].add(amount);
       
       
    uint shares = (stakedBalances[msg.sender].mul(100)).div(totalStakedMcH.add(amount));
    stakedShares[msg.sender] = stakedShares[msg.sender].add(shares);
    
    emit NotifyStaked(msg.sender, amount);
  }


  /** @dev unstake funds from Pool
    */
   function unstake(uint amount) external whenNotPaused onlyAfter(){
    
    require(stakedBalances[msg.sender] >= amount, "unstaking balance cannot be 0");

    // Transfer Mocktokens 
    mchtoken.transfer(msg.sender, amount);

    // Reset staking balance
    stakedBalances[msg.sender] = stakedBalances[msg.sender].sub(amount);
    
    uint shares = (stakedBalances[msg.sender].mul(100)).div(totalStakedMcH.sub(amount));
    stakedShares[msg.sender] = stakedShares[msg.sender].sub(shares);
    
    if(stakedBalances[msg.sender] == 0) removeUser(msg.sender);

    emit NotifyUnStaked(msg.sender, amount);
  
   }

  
    function calcRewards(address user) public  onlyAfter() view  returns(uint) {
     
     uint mcftokensEmitted = mcftoken.totalSupply();
     return (stakedShares[user].mul(mcftokensEmitted)).div(100);
   
        
    }
  
  
    function distributeRewards() external onlyAfter() onlyOwner()  {
       
       for (uint256 i = 0; i < users.length; i += 1) {
           address user = users[i];
           uint256 reward = calcRewards(user);
           currentstakeyields[user] = currentstakeyields[user].add(reward);
           vested[user] = currentstakeyields[user].div(2);
           claimable[user]=currentstakeyields[user].sub(vested[user]);
      }
   }

    function Harvest() external whenNotPaused nonReentrant() onlyAfter() {
        
        uint256 Balance = claimable[msg.sender];
       // Require amount greater than 0
        require(Balance > 0, "balance cannot be 0");
        mcftoken.transfer(msg.sender, Balance);
       // payable(msg.sender).transfer(balance);
        currentstakeyields[msg.sender] = currentstakeyields[msg.sender].sub(Balance);
        claimable[msg.sender] = 0;

       emit Notifyclaimed(msg.sender,Balance);
    
    }
  
   function calcROI() external onlyOwner()  onlyAfter() {
     
      for (uint256 i = 0; i < users.length; i += 1) {
        address user = users[i];
        ROI[user] =  (currentstakeyields[user].div(totalStakedMcH)).mul(100);
        MROI[user] = (ROI[user]).div(12);
        DROI[user] = (ROI[user]).div(365);
       
       }
    }

}

        
   