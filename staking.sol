// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Math library
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0 = x * y;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) {
                return prod0 / denominator;
            }
            require(denominator > prod1, "Math: mulDiv overflow");
            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
            }
            return prod0 / denominator + prod1;
        }
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 result = 1 << (log2(a) >> 1);
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }
}

// IERC20 interface
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ReentrancyGuard contract
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// Ana kontrat
contract BankOfAztechStaking is ReentrancyGuard {
    IERC20 public immutable stakingToken;
    
    uint256 public constant STAKING_DURATION = 3650 days; // 10 yıl
    uint256 public constant TOTAL_REWARDS = 3_000_000 * 1e18; // 3 Milyon BOFA
    uint256 public constant REWARD_RATE = TOTAL_REWARDS / STAKING_DURATION; // Günlük ödül oranı
    
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalStaked;
    bool public isInitialized;
    
    mapping(address => uint256) public userStakedAmount;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    
    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event StakingStarted(uint256 startTime);
    event RewardsInitialized(uint256 amount);
    
    constructor(address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
    }
    
    // Başlangıç ödül fonksiyonu - kontrat deploy edildikten sonra çağrılmalı
    function initializeRewards() external {
        require(!isInitialized, "Already initialized");
        require(stakingToken.transferFrom(msg.sender, address(this), TOTAL_REWARDS), "Initial reward transfer failed");
        
        lastUpdateTime = block.timestamp;
        isInitialized = true;
        
        emit StakingStarted(block.timestamp);
        emit RewardsInitialized(TOTAL_REWARDS);
    }
    
    // Görüntüleme fonksiyonları
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            ((block.timestamp - lastUpdateTime) * REWARD_RATE * 1e18) / totalStaked
        );
    }
    
    function earned(address account) public view returns (uint256) {
        return (
            (userStakedAmount[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18
        ) + rewards[account];
    }
    
    // Güncelleme modifier'ı
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
    
    // Stake fonksiyonu
    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(isInitialized, "Staking not initialized");
        require(amount > 0, "Stake amount must be greater than 0");
        totalStaked += amount;
        userStakedAmount[msg.sender] += amount;
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit Staked(msg.sender, amount);
    }
    
    // Unstake fonksiyonu
    function withdraw(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(isInitialized, "Staking not initialized");
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(userStakedAmount[msg.sender] >= amount, "Not enough staked tokens");
        totalStaked -= amount;
        userStakedAmount[msg.sender] -= amount;
        require(stakingToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }
    
    // Ödül toplama fonksiyonu
    function getReward() external nonReentrant updateReward(msg.sender) {
        require(isInitialized, "Staking not initialized");
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            require(stakingToken.transfer(msg.sender, reward), "Transfer failed");
            emit RewardPaid(msg.sender, reward);
        }
    }
    
    // Kontrat bakiyesini görüntüleme
    function getContractBalance() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }
} 
