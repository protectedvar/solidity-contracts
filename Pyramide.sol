pragma solidity ^0.8.0;

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b > 0);
        uint256 c = a / b;
        assert(a == b * c + (a % b));
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}

/**
    Ownable contract
 */
contract Ownable {
    address private _owner;

    constructor() public {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(isOwner(), "Function accessible only by the owner !!");
        _;
    }

    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }
}

/**
    Chat contract
 */
contract Chat {
    using SafeMath for uint256;
    event SendMessage(uint256 id, string message, address sender);

    struct Message {
        address sender;
        string message;
    }

    uint256 private _messagesCount;
    mapping(address => string) public usernames;
    mapping(uint256 => Message) public messages;

    function messagesCount() public view returns (uint256) {
        return _messagesCount;
    }

    function sendMessage(string memory message) public returns (uint256) {
        messages[_messagesCount] = Message(msg.sender, message);
        emit SendMessage(_messagesCount, message, msg.sender);
        _messagesCount = _messagesCount.add(1);
        return _messagesCount;
    }

    function setUserName(string calldata name) public returns (bool) {
        bytes memory username = bytes(usernames[msg.sender]);
        if (username.length == 0) {
            usernames[msg.sender] = name;
            return true;
        }
        return false;
    }
}

contract Pyramide is Ownable, Chat {
    using SafeMath for uint256;

    event NewBlock(uint256 id);
    event Reward(uint256 blockID, address player, uint256 reward);
    event Withdraw(address player);

    uint256 private constant FIRST_ROW_BLOCKS_COUNT = 128;
    uint256 private constant MAXIMUM_ROWS_COUNT = FIRST_ROW_BLOCKS_COUNT - 1;
    uint256 private constant FIRST_BLOCK_PRICE = .005 ether;
    uint256 private constant REWARDED_BLOCK = 100;
    uint256 private constant REWARDS_TOTAL = 49; // only 49 rewards (50 reward == 5000 block == jackpot);
    uint256 private constant REWARD_DIV = 120;

    uint256 private constant REWARD_FEE_NUMERATOR = 70;
    uint256 private constant DENOMINATOR = 100; // 70% goes to rewards;
    // comission = (2% of each block) = (70% goes of comission to REWARDS and 30% goes block owner)
    uint256 private constant FEE_TOP = 2; // 2%
    uint256 private constant NEXT_ROW_GROWING = 25; // 25%

    bool public isLive;
    uint256 public totalBlocks = 0;
    uint256 public rewardBalance;
    uint256 public rewardsCount;

    struct Block {
        uint256 x;
        uint256 y;
        string message;
    }

    // block price = bottomRowBlockPrice + 0.1% * bottomRowBlockPrice
    mapping(address => uint256) public balances;
    mapping(uint256 => mapping(uint256 => uint256)) public blocksCoordinates;
    mapping(uint256 => address) public blocksOwners;
    mapping(uint256 => uint256) public prices;
    mapping(uint256 => address) public rewards_id;
    mapping(uint256 => uint256) public rewards_amount;
    mapping(uint256 => Block) public blocks;

    constructor() public {
        isLive = true;
        prices[0] = FIRST_BLOCK_PRICE;

        totalBlocks = 1;
        calculatePrice(0);
        placeBlock(owner(), 0, 0, "First Block :)");
        sendMessage("Welcome to the Pyramide!");
    }

    function setBlock(
        uint256 x,
        uint256 y,
        string calldata message
    ) external payable {
        if (isLive) {
            address sender = msg.sender;

            uint256 bet = calculatePrice(y);
            uint256 senderBalance = balances[sender] + msg.value;

            require(bet <= senderBalance);

            if (checkBlockEmpty(x, y)) {
                uint256 fee = (bet * FEE_TOP) / DENOMINATOR;
                uint256 jackpotFee = (fee * REWARD_FEE_NUMERATOR) / DENOMINATOR;
                uint256 amountForOwner = fee - jackpotFee;
                uint256 amountForBlock = bet - fee;

                if (x < FIRST_ROW_BLOCKS_COUNT - y) {
                    balances[owner()] += amountForOwner;
                    rewardBalance += jackpotFee;
                    balances[sender] = senderBalance - bet;

                    if (y == 0) {
                        uint256 firstBlockReward = (amountForBlock *
                            REWARD_FEE_NUMERATOR) / DENOMINATOR;
                        rewardBalance += firstBlockReward;
                        balances[owner()] += amountForBlock - firstBlockReward;
                        placeBlock(sender, x, y, message);
                    } else {
                        placeToRow(sender, x, y, message, amountForBlock);
                    }
                } else {
                    revert(); // outside the blocks field
                }
            } else {
                revert(); // block[x, y] is not empty
            }
        } else {
            revert(); // game is over
        }
    }

    function placeBlock(
        address sender,
        uint256 x,
        uint256 y,
        string memory message
    ) private {
        blocksCoordinates[y][x] = totalBlocks;

        blocks[totalBlocks] = Block(x, y, message);
        blocksOwners[totalBlocks] = sender;

        emit NewBlock(totalBlocks);

        // reward every 100 blocks
        if (totalBlocks % REWARDED_BLOCK == 0) {
            uint256 reward;
            // block id == 5000 - JACKPOT!!!! Game OVER;
            if (rewardsCount == REWARDS_TOTAL) {
                isLive = false; // GAME IS OVER
                rewardsCount++;
                reward = rewardBalance; // JACKPOT!
                rewardBalance = 0;
            } else {
                rewardsCount++;
                reward = calculateReward();
                rewardBalance = rewardBalance.sub(reward);
            }

            balances[sender] += reward;
            emit Reward(rewardsCount, sender, reward);
            rewards_id[rewardsCount - 1] = sender;
            rewards_amount[rewardsCount - 1] = reward;
        }
        totalBlocks++;
    }

    function placeToRow(
        address sender,
        uint256 x,
        uint256 y,
        string calldata message,
        uint256 bet
    ) private {
        uint256 parentY = y - 1;

        uint256 parent1_id = blocksCoordinates[parentY][x];
        uint256 parent2_id = blocksCoordinates[parentY][x + 1];

        if (parent1_id != 0 && parent2_id != 0) {
            address owner_of_block1 = blocksOwners[parent1_id];
            address owner_of_block2 = blocksOwners[parent2_id];

            uint256 reward1 = bet / 2;
            uint256 reward2 = bet - reward1;
            balances[owner_of_block1] += reward1;
            balances[owner_of_block2] += reward2;

            placeBlock(sender, x, y, message);
        } else {
            revert();
        }
    }

    function calculatePrice(uint256 y) private returns (uint256) {
        uint256 nextY = y + 1;
        uint256 currentPrice = prices[y];
        if (prices[nextY] == 0) {
            prices[nextY] =
                currentPrice +
                (currentPrice * NEXT_ROW_GROWING) /
                DENOMINATOR;
            return currentPrice;
        } else {
            return currentPrice;
        }
    }

    function withdrawBalance(uint256 amount) external {
        require(amount != 0);

        require(balances[msg.sender] >= amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        payable(msg.sender).transfer(amount);
        emit Withdraw(msg.sender);
    }

    function calculateReward() public view returns (uint256) {
        return (rewardBalance * rewardsCount) / REWARD_DIV;
    }

    function getBlockPrice(uint256 y) public view returns (uint256) {
        return prices[y];
    }

    function checkBlockEmpty(uint256 x, uint256 y) public view returns (bool) {
        return blocksCoordinates[y][x] == 0;
    }

    function Info()
        public
        view
        returns (
            uint256 tb,
            uint256 bc,
            uint256 fbp,
            uint256 rc,
            uint256 rb,
            uint256 rt,
            uint256 rf,
            uint256 rd,
            uint256 mc,
            uint256 rew
        )
    {
        tb = totalBlocks;
        bc = FIRST_ROW_BLOCKS_COUNT;
        fbp = FIRST_BLOCK_PRICE;
        rc = rewardsCount;
        rb = rewardBalance;
        rt = REWARDS_TOTAL;
        rf = REWARD_FEE_NUMERATOR;
        rd = REWARD_DIV;
        mc = messagesCount();
        rew = REWARDED_BLOCK;
    }

    function getBlock(uint256 id)
        public
        view
        returns (
            uint256 i,
            uint256 x,
            uint256 y,
            address own,
            string memory message
        )
    {
        Block storage bl = blocks[id];
        i = id;
        x = bl.x;
        y = bl.y;
        own = blocksOwners[id];
        message = bl.message;
    }

    function getRewards(uint256 c, uint256 o)
        public
        view
        returns (
            uint256 cursor,
            uint256 offset,
            uint256[] memory array
        )
    {
        uint256 n;
        uint256[] memory arr = new uint256[](o * 2);
        offset = o;
        cursor = c;
        uint256 l = offset + cursor;
        for (uint256 i = cursor; i < l; i++) {
            arr[n] = uint256(uint160(rewards_id[i]));
            arr[n + 1] = rewards_amount[i];
            n += 2;
        }
        array = arr;
    }

    function getBlocks(uint256 c, uint256 o)
        public
        view
        returns (
            uint256 cursor,
            uint256 offset,
            uint256[] memory array
        )
    {
        uint256 n;
        uint256[] memory arr = new uint256[](o * 3);
        offset = o;
        cursor = c;
        uint256 l = offset + cursor;
        for (uint256 i = cursor; i < l; i++) {
            Block storage b = blocks[i + 1];
            arr[n] = (b.x);
            arr[n + 1] = (b.y);
            arr[n + 2] = uint256(uint160(blocksOwners[i + 1]));
            n += 3;
        }
        array = arr;
    }

    function getPrices(uint256 c, uint256 o)
        public
        view
        returns (
            uint256 cursor,
            uint256 offset,
            uint256[] memory array
        )
    {
        uint256 n;
        uint256[] memory arr = new uint256[](o);
        offset = o;
        cursor = c;
        uint256 l = offset + cursor;
        for (uint256 i = cursor; i < l; i++) {
            arr[n] = prices[i];
            n++;
        }
        array = arr;
    }
}
