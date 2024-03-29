//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./libraries/BoringERC20.sol";

contract BananaVault is Ownable, Pausable, ReentrancyGuard {
    using SafeMath for uint256;
    using BoringERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }


    IERC20 public lpToken; // Address of LP token contract.
    uint256 public lastRewardTimestamp; // Last timestamp that Reward distribution occurs.
    uint256 public accRewardTokenPerShare; // Accumulated Reward per share, times 1e12. See below.

    uint256 public bonusEndTimestamp; // deadline of the vault

    IERC20 public rewardToken;
    // Reward tokens created per second.
    uint256 public manualRewardPerSecond = 34722222222222; // 3 * 1e18 / 86400

    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Harvest(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event DepositRewards(uint256 amount);
    event EmergencyRewardWithdraw(address indexed user, uint256 amount);
    
    function setStakeToken(IERC20 _stakeToken) external onlyOwner {
        lpToken = _stakeToken;
    }

    function setRewardToken(IERC20 _rewardToken) external onlyOwner {
        rewardToken = _rewardToken;
    }

    function setStartTimestamp(uint256 _startTimestamp) external onlyOwner {
        lastRewardTimestamp = _startTimestamp;
    }

        /// The block when rewards will end
    function setBonusEndTimestamp(uint256 _bonusEndTimestamp) external onlyOwner {
        require(_bonusEndTimestamp > bonusEndTimestamp, "new bonus end block must be greater than current");
        bonusEndTimestamp = _bonusEndTimestamp;
    }

    // Returns calculated or manual rewards per second
    function getRewardPerSecond() public view returns (uint256) {
            return manualRewardPerSecond;
   }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndTimestamp) {
            return _to.sub(_from);
        } else if (_from >= bonusEndTimestamp) {
            return 0;
        } else {
            return bonusEndTimestamp.sub(_from);
        }
    }

    function vaultStarted() public view returns (bool) {
        return lastRewardTimestamp != 0 && bonusEndTimestamp != 0;
    }

    function rewardBalance() public view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function depositedBalance() public view returns (uint256) {
        return lpToken.balanceOf(address(this));
    }

    // View function to see pending Token on frontend.
    function pendingRewards(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accRewardToken = accRewardTokenPerShare;
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (block.timestamp > lastRewardTimestamp && lpSupply != 0) {
            uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
            uint256 tokenReward = multiplier.mul(getRewardPerSecond());
            accRewardToken = accRewardToken.add(tokenReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accRewardToken).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public whenNotPaused {
        if (block.timestamp <= lastRewardTimestamp) {
            return;
        }
        uint256 lpSupply = lpToken.balanceOf(address(this));

        if (lpSupply == 0) {
            lastRewardTimestamp = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
        accRewardTokenPerShare = accRewardTokenPerShare.add(multiplier.mul(getRewardPerSecond()).mul(1e12).div(lpSupply));
        lastRewardTimestamp = block.timestamp;
    }

    // Deposit LP tokens to Alpha Ape for Reward allocation.
    function deposit(uint256 _amount) public whenNotPaused nonReentrant {
        require(vaultStarted(), "you can't deposit yet");
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accRewardTokenPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTokenTransfer(msg.sender, pending);
                emit Harvest(msg.sender, pending);
            }
        }
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(accRewardTokenPerShare).div(1e12);

        if(_amount > 0) {
            lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        }
        emit Deposit(msg.sender, _amount);
    }

    // Withdraw LP tokens from Alpha Ape.
    function withdraw(uint256 _amount) public whenNotPaused nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool();

        // Harvest Reward
        uint256 pending = user.amount.mul(accRewardTokenPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTokenTransfer(msg.sender, pending);
            emit Harvest(msg.sender, pending);
        }

        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(accRewardTokenPerShare).div(1e12);

        if(_amount > 0) {
            lpToken.safeTransfer(address(msg.sender), _amount);
        }
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        lpToken.safeTransfer(address(msg.sender), user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        emit EmergencyWithdraw(msg.sender, user.amount);
    }

    // Safe Reward transfer function, just in case if rounding error causes pool to not have enough Reward.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = rewardToken.balanceOf(address(this));
        if (_amount > rewardBal) {
            rewardToken.safeTransfer(_to, rewardBal);
        } else {
            rewardToken.safeTransfer(_to, _amount);
        }
    }

    function depositRewards(uint256 _amount) external {
        require(_amount > 0, "deposit value must be greater than zero");
        rewardToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        emit DepositRewards(_amount);
    }

    // Withdraw reward. EMERGENCY ONLY.
    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        require(_amount <= rewardToken.balanceOf(address(this)), "not enough rewards");
        // Withdraw rewards
        rewardToken.safeTransfer(address(msg.sender), _amount);
        emit EmergencyRewardWithdraw(msg.sender, _amount);
    }

    function setManualRewardPerSecond(uint256 _manualRewardPerSecond) external onlyOwner {
        manualRewardPerSecond = _manualRewardPerSecond;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

}