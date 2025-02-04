// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// IERC20 Interface
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// Context Contract
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// Ownable Contract
abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// ReentrancyGuard Contract
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// Main Contract
contract AztechMint is Ownable, ReentrancyGuard {
    IERC20 public token;
    
    uint256 public constant MAX_MINTERS = 1000;  // Her ödül dönemi için maksimum mint edici sayısı
    uint256 public constant REFLECTION_COUNT = 33;  // Reflection yapılacak cüzdan sayısı
    uint256 public constant MIN_BALANCE = 1 ether;  // Minimum 1 BOFA tutma zorunluluğu (18 decimals)
    
    struct RewardCycle {
        uint256 cycleId;         // Dönem ID'si
        uint256 totalReward;     // Bu dönem için toplam ödül miktarı
        uint256 rewardPerMint;   // Her mint başına düşen ödül (totalReward / 1000)
        uint256 mintersCount;    // Şu ana kadar mint eden sayısı
        uint256 startTime;       // Dönemin başlangıç zamanı
        uint256 remainingReward; // Kalan ödül miktarı
        bool active;            // Dönem aktif mi?
    }
    
    RewardCycle public currentCycle;
    uint256 public cycleCount;  // Toplam dönem sayısı
    
    // Son 33 mint eden cüzdan adresleri
    address[] public lastMinters;
    
    // Cüzdan adresi => Mint edildi mi?
    mapping(address => bool) public hasEverMinted;
    
    // Dönem ID => Dönem bilgileri
    mapping(uint256 => RewardCycle) public cycleHistory;
    
    // Dönem ID => Mint eden cüzdanlar
    mapping(uint256 => address[]) public cycleMinters;
    
    event RewardCycleStarted(
        uint256 indexed cycleId,
        uint256 totalReward,
        uint256 rewardPerMint,
        uint256 startTime
    );
    
    event RewardDeposited(
        uint256 indexed cycleId,
        uint256 amount,
        uint256 rewardPerMint,
        uint256 timestamp
    );
    
    event Minted(
        address indexed minter,
        uint256 indexed cycleId,
        uint256 directReward,
        uint256 reflectionReward,
        uint256 timestamp,
        uint256 remainingMintsInCycle
    );
    
    event ReflectionDistributed(
        uint256 indexed cycleId,
        address[] recipients,
        uint256 amountPerRecipient,
        uint256 totalReflectionAmount
    );
    
    event CycleCompleted(
        uint256 indexed cycleId,
        uint256 totalMinters,
        uint256 totalRewardDistributed,
        uint256 timestamp
    );
    
    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }
    
    // Owner tarafından ödül yatırma
    function depositReward(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(!currentCycle.active || currentCycle.mintersCount >= MAX_MINTERS, 
                "Current cycle must be completed");
        
        // Ödülleri kontrata transfer et
        require(token.transferFrom(msg.sender, address(this), amount), 
                "Transfer failed");
        
        cycleCount++;
        
        // Yeni döngüyü başlat
        currentCycle = RewardCycle({
            cycleId: cycleCount,
            totalReward: amount,
            rewardPerMint: amount / MAX_MINTERS,
            mintersCount: 0,
            startTime: block.timestamp,
            remainingReward: amount,
            active: true
        });
        
        // Önceki mint edenleri sıfırla
        delete lastMinters;
        
        // Dönem geçmişine kaydet
        cycleHistory[cycleCount] = currentCycle;
        
        emit RewardCycleStarted(
            cycleCount,
            amount,
            currentCycle.rewardPerMint,
            block.timestamp
        );
        
        emit RewardDeposited(
            cycleCount,
            amount,
            currentCycle.rewardPerMint,
            block.timestamp
        );
    }
    
    // Mint fonksiyonu
    function mint() external nonReentrant {
        require(currentCycle.active, "No active reward cycle");
        require(!hasEverMinted[msg.sender], "Address has already minted");
        require(currentCycle.mintersCount < MAX_MINTERS, "Cycle is full");
        require(token.balanceOf(msg.sender) >= MIN_BALANCE, "Insufficient BOFA balance");
        
        uint256 mintAmount = currentCycle.rewardPerMint;
        uint256 userReward = mintAmount / 2;  // %50'si mint edene
        uint256 reflectionReward = mintAmount - userReward;  // %50'si reflection
        
        // Kullanıcıya ödülünü gönder
        require(token.transfer(msg.sender, userReward), "Transfer to minter failed");
        
        address[] memory reflectionRecipients;
        uint256 rewardPerReflection;
        
        // Reflection dağıtımı
        if (lastMinters.length > 0) {
            uint256 reflectionCount = lastMinters.length < REFLECTION_COUNT ? 
                lastMinters.length : REFLECTION_COUNT;
            
            rewardPerReflection = reflectionReward / reflectionCount;
            reflectionRecipients = new address[](reflectionCount);
            
            for (uint256 i = 0; i < reflectionCount; i++) {
                require(token.transfer(lastMinters[i], rewardPerReflection), 
                        "Reflection transfer failed");
                reflectionRecipients[i] = lastMinters[i];
            }
            
            emit ReflectionDistributed(
                currentCycle.cycleId,
                reflectionRecipients,
                rewardPerReflection,
                reflectionReward
            );
        } else {
            // İlk mint eden için reflection miktarı da kendisine gider
            require(token.transfer(msg.sender, reflectionReward), 
                    "Additional transfer to first minter failed");
        }
        
        // Son minterları güncelle
        if (lastMinters.length >= REFLECTION_COUNT) {
            // FIFO - İlk gireni çıkar
            for (uint256 i = 0; i < REFLECTION_COUNT - 1; i++) {
                lastMinters[i] = lastMinters[i + 1];
            }
            lastMinters[REFLECTION_COUNT - 1] = msg.sender;
        } else {
            lastMinters.push(msg.sender);
        }
        
        // Mint kaydı
        hasEverMinted[msg.sender] = true;
        currentCycle.mintersCount++;
        currentCycle.remainingReward -= mintAmount;
        
        // Dönem geçmişine kaydet
        cycleMinters[currentCycle.cycleId].push(msg.sender);
        cycleHistory[currentCycle.cycleId] = currentCycle;
        
        emit Minted(
            msg.sender,
            currentCycle.cycleId,
            userReward,
            reflectionReward,
            block.timestamp,
            MAX_MINTERS - currentCycle.mintersCount
        );
        
        // Döngü tamamlandı mı kontrol et
        if (currentCycle.mintersCount >= MAX_MINTERS) {
            currentCycle.active = false;
            cycleHistory[currentCycle.cycleId] = currentCycle;
            
            emit CycleCompleted(
                currentCycle.cycleId,
                MAX_MINTERS,
                currentCycle.totalReward,
                block.timestamp
            );
        }
    }
    
    // View fonksiyonları
    function getCurrentCycleInfo() external view returns (
        uint256 cycleId,
        uint256 totalReward,
        uint256 rewardPerMint,
        uint256 mintersCount,
        uint256 startTime,
        uint256 remainingReward,
        bool active,
        uint256 remainingMints
    ) {
        return (
            currentCycle.cycleId,
            currentCycle.totalReward,
            currentCycle.rewardPerMint,
            currentCycle.mintersCount,
            currentCycle.startTime,
            currentCycle.remainingReward,
            currentCycle.active,
            MAX_MINTERS - currentCycle.mintersCount
        );
    }
    
    function getLastMinters() external view returns (address[] memory) {
        return lastMinters;
    }
    
    function getCycleMinters(uint256 cycleId) external view returns (address[] memory) {
        return cycleMinters[cycleId];
    }
    
    function getCycleHistory(uint256 cycleId) external view returns (RewardCycle memory) {
        return cycleHistory[cycleId];
    }
    
    function getMintsRemaining() external view returns (uint256) {
        if (!currentCycle.active) return 0;
        return MAX_MINTERS - currentCycle.mintersCount;
    }
} 
