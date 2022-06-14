/*
SPDX-License-Identifier: GPL-3.0
    ___ _____   ____  ____  _______ 
   /   /__  /  / __ \/ __ \/  _/   |
  / /| | / /  / / / / /_/ // // /| |
 / ___ |/ /__/ /_/ / _, _// // ___ |
/_/  |_/____/\____/_/ |_/___/_/  |_|
            azoria.au

           METIS NINJAS
*/

pragma solidity 0.8.14;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol"; 
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "./interfaces/INetswapRouter02.sol";


contract MetisNinjas is ERC2981, ERC721Enumerable, Ownable, ReentrancyGuard, AccessControl {
    using SafeMath for uint256;
    using Address for address;
    using Address for address payable;

    uint256 public MAX_TOTAL_MINT;
    string private _contractURI;
    string public baseTokenURI;
    uint256 private _currentTokenId = 0;
    
    address private feeSplitter;
    address public treasury = 0x48eE6F05783D01Fe18904b1af2Bd29fb12Ce3139;
    address public artist = 0xe5d100bF6b44F54e0371EDCDE29018c8B54f4b46;
    address public WMETIS = 0x75cb093E4D61d2A2e65D8e0BBb01DE8d89b53481;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    address internal constant NETSWAP_ROUTER_ADDRESS = 0x1E876cCe41B7b844FDe09E38Fa1cf00f213bFf56;

    INetswapRouter02 public netswapRouter;
    address private proToken = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;
    
    constructor(string memory ContractURI) 
    ERC721("Metis Ninjas", "NINJAS") {
        MAX_TOTAL_MINT = 5000;
        baseTokenURI = "ipfs://QmWqVg8MsEmBXChLaNMCqz5SKE86DWGj88Pg7DaLaSDKMq/";
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        // _setDefaultRoyalty(treasury, 200);
        _contractURI = ContractURI;
        netswapRouter = INetswapRouter02(NETSWAP_ROUTER_ADDRESS);
    }

    function setBaseURI(string memory _setBaseURI) external onlyOwner {
        baseTokenURI = _setBaseURI;
    }

    function setContractURI(string memory uri) external onlyOwner {
        _contractURI = uri;
    }

    // PUBLIC
    
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(AccessControl, ERC2981, ERC721Enumerable)
    returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, Strings.toString(tokenId), ".json")) : "";
    }

    function getInfo() external view returns (
        uint256,
        uint256,
        uint256
    ) {
        return (
        this.totalSupply(),
        msg.sender == address(0) ? 0 : this.balanceOf(msg.sender),
        MAX_TOTAL_MINT
        );
    }

    /**
     * Accepts required payment and mints a specified number of tokens to an address.
     */
    function purchase(uint256 count) public payable nonReentrant {

        uint256 price;

        if (count >= 1 && count <= 2) {
            price = 2.5 ether;
        }
        if (count >= 3 && count <= 5) {
            price = 2.0 ether;
        }
        if (count >= 6 && count <= 10) {
            price = 1.7 ether;
        }
        if (count > 10) {
            price = 1.5 ether;
        }

        // Make sure minting is allowed
        requireMintingConditions(count);

        // Sent value matches required ETH amount
        require(price * count <= msg.value, "ERC721_COLLECTION/INSUFFICIENT_ETH_AMOUNT");

        for (uint256 i = 0; i < count; i++) {
            uint256 newTokenId = _getNextTokenId();
            _safeMint(msg.sender, newTokenId);
            _incrementTokenId();
        }

        distributeRoyalties(msg.value);
    }

    function distributeRoyalties(uint256 price) public {
        uint256 fee = price.mul(2).div(100);
        // uint256 treasuryFee = price.mul(2).div(100);
        // uint256 treasuryFee = price.mul(2).div(100);
        payable(treasury).transfer(fee);
        payable(artist).transfer(fee);
        swapTokenWithMetis(fee, proToken, treasury);
    }

    function withdraw() public onlyOwner  {
        uint256 balance = address(this).balance;
        uint256 treasuryAmt = balance.mul(65).div(100);
        uint256 artistAmt = balance.mul(25).div(100);
        uint256 buybackAmt = balance.mul(10).div(100);
        require(treasuryAmt.add(artistAmt).add(buybackAmt) == balance);
        payable(treasury).transfer(treasuryAmt);
        payable(artist).transfer(artistAmt);
        swapTokenWithMetis(buybackAmt, proToken, treasury);
    }

    // PRIVATE

    /**
     * This method checks if ONE of these conditions are met:
     *   - Public sale is active.
     *   - Pre-sale is active and receiver is allowlisted.
     *
     * Additionally ALL of these conditions must be met:
     *   - Gas fee must be equal or less than maximum allowed.
     *   - Newly requested number of tokens will not exceed maximum total supply.
     */
    function requireMintingConditions(uint256 count) internal view {

        // Total minted tokens must not exceed maximum supply
        require(totalSupply() + count <= MAX_TOTAL_MINT, "ERC721_COLLECTION/EXCEEDS_MAX_SUPPLY");
    }

    /**
     * Calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId.add(1);
    }

    /**
     * Increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    /**
        Airdrop by admin
     */
    function claimAirdrop(address _to/*, bytes memory _signature*/) public onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokenId = _getNextTokenId();
        // string memory message = getWebAuthToken();
        // require(verify(_to, message, tokenId, _signature), "You are not eligible for this Airdrop !");
        require(tokenId <= MAX_TOTAL_MINT, "All NFT have been airdropped. Sorry !");
        _incrementTokenId();
        _safeMint(_to, tokenId);
    }
    /***
        Swap tokens with metis using NetSwap Interface
     */
    function swapTokenWithMetis(uint256 metisAmount, address token, address to) public {
        convertMetisToExactToken(metisAmount, token, getEstimatedTokenforMetis(metisAmount, token), to);
    }
    
    function convertMetisToExactToken(uint256 metisAmount, address token, uint amount, address to) public {
        uint deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
        netswapRouter.swapMetisForExactTokens{ value: metisAmount }(amount, getPathForMetistoExactToken(token), to, deadline);
        
        // refund leftover ETH to user
        (bool success,) = msg.sender.call{ value: address(this).balance }("");
        require(success, "refund failed");
    }
  
    function getEstimatedTokenforMetis(uint metisAmount, address token) public view returns (uint) {
        address[] memory path = getPathForMetistoExactToken(token);
        uint256[] memory amountOutMins = netswapRouter.getAmountsOut(metisAmount, path);
            return amountOutMins[path.length -1];  
    }

    function getPathForMetistoExactToken(address token) private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = WMETIS;
        path[1] = token;
        
        return path;
    }
  

}
