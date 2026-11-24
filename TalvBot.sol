// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAgentIdRegistry {
    function balanceOf(address wallet) external view returns (uint256);
}

/// @title TalvBot — a 999-capsule gacha on BNB Chain.
/// One spin mints one capsule NFT and reveals its tier in the same transaction.
/// Every 100th PAID spin wins a BNB jackpot paid instantly in that same transaction.
/// No claims, no waiting, no second step — every reward lands inside the spin.
contract TalvBot is ERC721, Ownable {
    enum Tier {
        Common,
        Rare,
        Legendary
    }

    uint256 public constant MAX_SUPPLY = 999;
    uint256 public constant MAX_PER_WALLET = 25;
    uint256 public constant JACKPOT_EVERY = 100; // paid spins
    uint256 public constant JACKPOT_AMOUNT = 0.025 ether;

    IAgentIdRegistry public constant AGENT_ID_REGISTRY =
        IAgentIdRegistry(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    bool public mintOpen;
    uint256 public totalMinted;
    uint256 public paidCount;
    string private _baseTokenURI;

    mapping(address => bool) public freeSpinUsed;
    mapping(address => uint256) public spinsOf;
    mapping(uint256 => Tier) public tierOf;

    event Spun(
        address indexed spinner,
        uint256 indexed tokenId,
        Tier tier,
        bool paid,
        uint256 jackpotWei
    );
    event MintOpenSet(bool open);
    event BaseURISet(string baseURI);
    event Withdrawn(address indexed to, uint256 amount);

    constructor() ERC721("TalvBot", "TBOT") Ownable(msg.sender) {}

    // ---------- pricing ----------

    /// @notice Current paid spin price, stepped by total minted.
    function currentPrice() public view returns (uint256) {
        uint256 m = totalMinted;
        if (m < 250) return 0.0008 ether;
        if (m < 500) return 0.001 ether;
        if (m < 750) return 0.0012 ether;
        return 0.0015 ether;
    }

    /// @notice Paid spins remaining until the next jackpot spin.
    function paidSpinsToJackpot() public view returns (uint256) {
        uint256 r = paidCount % JACKPOT_EVERY;
        return r == 0 ? JACKPOT_EVERY : JACKPOT_EVERY - r;
    }

    function hasAgentId(address wallet) public view returns (bool) {
        return AGENT_ID_REGISTRY.balanceOf(wallet) > 0;
    }

    // ---------- spinning ----------

    function spin() external payable {
        require(mintOpen, "mint closed");
        require(totalMinted < MAX_SUPPLY, "sold out");
        require(spinsOf[msg.sender] < MAX_PER_WALLET, "wallet cap");
        uint256 price = currentPrice();
        require(msg.value == price, "wrong fee");

        paidCount += 1;
        bool jackpot = (paidCount % JACKPOT_EVERY == 0);
        Tier tier = _roll(true);
        uint256 tokenId = _mintCapsule(tier, true);

        uint256 jackpotWei = 0;
        if (jackpot && address(this).balance >= JACKPOT_AMOUNT) {
            jackpotWei = JACKPOT_AMOUNT;
            (bool ok, ) = payable(msg.sender).call{value: JACKPOT_AMOUNT}("");
            require(ok, "jackpot payout failed");
        }
        emit Spun(msg.sender, tokenId, tier, true, jackpotWei);
    }

    /// @notice One free spin per wallet for Binance Agent ID holders. Hook only:
    /// free spins mint a capsule but never count toward the jackpot counter.
    function freeSpin() external {
        require(mintOpen, "mint closed");
        require(totalMinted < MAX_SUPPLY, "sold out");
        require(spinsOf[msg.sender] < MAX_PER_WALLET, "wallet cap");
        require(!freeSpinUsed[msg.sender], "free spin used");
        require(hasAgentId(msg.sender), "no Agent ID");

        freeSpinUsed[msg.sender] = true;
        Tier tier = _roll(false);
        uint256 tokenId = _mintCapsule(tier, false);
        emit Spun(msg.sender, tokenId, tier, false, 0);
    }

    function _mintCapsule(Tier tier, bool /*paid*/) internal returns (uint256 tokenId) {
        totalMinted += 1;
        tokenId = totalMinted;
        spinsOf[msg.sender] += 1;
        tierOf[tokenId] = tier;
        _safeMint(msg.sender, tokenId);
    }

    function _roll(bool paid) internal view returns (Tier) {
        uint256 r = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    block.timestamp,
                    msg.sender,
                    totalMinted,
                    paidCount
                )
            )
        ) % 100;
        if (paid) {
            if (r < 62) return Tier.Common;
            if (r < 92) return Tier.Rare;
            return Tier.Legendary;
        }
        return r < 75 ? Tier.Common : Tier.Rare;
    }

    // ---------- metadata ----------

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Tier t = tierOf[tokenId];
        string memory file = t == Tier.Legendary
            ? "legendary.json"
            : t == Tier.Rare
                ? "rare.json"
                : "common.json";
        return string(abi.encodePacked(_baseTokenURI, file));
    }

    // ---------- owner ----------

    function setMintOpen(bool open) external onlyOwner {
        mintOpen = open;
        emit MintOpenSet(open);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
        emit BaseURISet(baseURI);
    }

    function baseURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function withdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "zero balance");
        (bool ok, ) = payable(owner()).call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawn(owner(), amount);
    }

    receive() external payable {}
}
