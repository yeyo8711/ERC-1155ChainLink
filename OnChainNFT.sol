// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OnChainNFT is ERC1155, ERC2981, Ownable, ERC1155Supply, VRFConsumerBaseV2, ReentrancyGuard {
    uint256 public constant legendary = 3;
    uint256 public constant epic = 2;
    uint256 public constant rare = 1;
    uint256 public constant common = 0;
    uint256 public legendaryRarity = 10;
    uint256 public epicRarity = 20;
    uint256 public rareRarity = 30;
    uint256 public commonRarity = 9940;
    uint256 public supplyLeft = 10000;
    uint256 public discountedTokensLeft = 10;
    uint256 public mintPrice = 5000000000000000000; // $5 USDC
    uint256 public discountPrice = 1000000000000000000; // $1 USDC
    bool public mintingEnabled;
    address private treasuryWallet = 0xD7d83a31940D4e2D7e9d14c6c0afA23978B2eB99;
    address private teamWallet = 0xD7d83a31940D4e2D7e9d14c6c0afA23978B2eB99;
    // Royalties
    uint96 public royaltyFeesInBips;
    string public contractUri;
    address private royaltyReceiver;
    // ChainLink VFR 
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    address vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
    bytes32 keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint32 callbackGasLimit = 2500000;
    uint16 requestConfirmations = 3;
    uint32 numWords =  10;
    uint256[] public s_randomWords;
    uint256 public s_requestId;
    uint256 public s_randomRange;
    mapping(uint256 => address) public requestToSender;
    mapping(uint256 => uint256) public requestIdToAmount;
    IERC20 usdc;
    struct Rarities{
        uint256 legendary;
        uint256 epic;
        uint256 rare;
        uint256 common;
    }
    mapping(uint256 => Rarities) public rarities;

    // Events //
    event Mint(address _address, uint256 tokenId, string rarity);
    event RandomNumberRequested(uint256 requestId, address buyer);
    event RandomNumberReceived(uint256 requestId, address receiver);

    constructor(uint64 subscriptionId, uint96 _royaltyFeesInBips, string memory _contractUri) VRFConsumerBaseV2(vrfCoordinator)
        ERC1155("ipfs://QmXUH4Xb8avxM4oxN3iN17xPbJ4MuieENjS1bVQUoniMHN")
        
    {
        usdc = IERC20(0xe11A86849d99F524cAC3E7A0Ec1241828e332C62);
        Rarities storage tokensLeft = rarities[0];
        tokensLeft.legendary = 10;
        tokensLeft.epic = 20;
        tokensLeft.rare = 30;
        tokensLeft.common  = 9940;

        // Royalties
        royaltyFeesInBips = _royaltyFeesInBips;
        contractUri = _contractUri;
        royaltyReceiver = msg.sender;
        // ChainLink
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
        
    }

    function mintNFT(address _address, uint256 _number) private {     
        Rarities storage tokensLeft = rarities[0];
        require(_number > 0);
        if(_number <= tokensLeft.legendary){
            _mint(_address, legendary, 1, "");
            tokensLeft.legendary -= 1;
            supplyLeft -= 1;
            emit Mint(_address, legendary, "Legendary");
            return;
        }
        if(_number <= tokensLeft.epic){
            _mint(_address, epic, 1, "");
            tokensLeft.epic -= 1;
            supplyLeft -= 1;
            emit Mint(_address, epic, "Epic");
            return;
        }
        if(_number <= tokensLeft.rare){
            _mint(_address, rare, 1, "");
            tokensLeft.rare -= 1;
            supplyLeft -= 1;
            emit Mint(_address, rare, "Rare");
            return;
        }
        if(_number <= tokensLeft.common){
            _mint(_address, common, 1, "");
            tokensLeft.common -= 1;
            supplyLeft -= 1;
            emit Mint(_address, common, "Common");
        }
    }


    function uri(uint256 _tokenId) override public pure returns(string memory){
        return string(abi.encodePacked("ipfs://QmXUH4Xb8avxM4oxN3iN17xPbJ4MuieENjS1bVQUoniMHN/", Strings.toString(_tokenId),".json"));
    }

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data)
        internal
        override(ERC1155, ERC1155Supply)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    // Royalties
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, ERC2981)
        returns (bool)
    {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) public view override returns (
        address receiver,
        uint256 royaltyAmount
    ){
        return (royaltyReceiver, calculateRoyalty(_salePrice));
    }
    function calculateRoyalty(uint256 _salePrice) view public returns(uint256){
        return (_salePrice / 10000) * royaltyFeesInBips;
    }
    function setRoyaltyInfo(address _royaltyReceiver, uint96 _royaltyFeesInBips) external onlyOwner{
        royaltyReceiver = _royaltyReceiver;
        royaltyFeesInBips = _royaltyFeesInBips;
    }
    function setContractUri(string memory _contractUri) external onlyOwner{
        contractUri = _contractUri;
    }

    // Setters and Getters 
    function changeTreasuryWallet(address _address)  external onlyOwner(){
        treasuryWallet = _address;
    }
    function changeTeamWallet(address _address)  external onlyOwner(){
        teamWallet = _address;
    }
    function enableMint() public onlyOwner{
        require(!mintingEnabled, "Minting is already enabled");
        mintingEnabled = true;
    }
    function burnSupply(uint256 _amountBurned) public onlyOwner{
        supplyLeft -= _amountBurned;
    }

    //----------------- ChainLink-----------------------------//
  function requestRandomWords(uint256 _amount) public payable nonReentrant() returns(uint256) {
    require(mintingEnabled, "Minting not yet available");
    require(supplyLeft > 0, "No more tokens can be minted");

    if(discountedTokensLeft - _amount >= 0){
    bool success = usdc.transferFrom(msg.sender, address(this), discountPrice * _amount);
    require(success, "Payment Failed"); 
    usdc.transfer(treasuryWallet, (discountPrice * 85 / 100) * _amount);
    usdc.transfer(teamWallet, (discountPrice * 15 / 100) * _amount); 
    discountedTokensLeft -= _amount;  
    }else{
    bool success = usdc.transferFrom(msg.sender, address(this), mintPrice * _amount);
    require(success, "Payment Failed");
    usdc.transfer(treasuryWallet, (mintPrice * 85 / 100) *_amount);
    usdc.transfer(teamWallet, (mintPrice * 15 / 100)*_amount);
    }

    uint256 requestId = COORDINATOR.requestRandomWords(
    keyHash,
    s_subscriptionId,
    requestConfirmations,
    callbackGasLimit,
    numWords
    );

    emit RandomNumberRequested(requestId, msg.sender);
    requestToSender[requestId] = msg.sender;
    requestIdToAmount[requestId] = _amount;
    return requestId;
  }
  function fulfillRandomWords(
    uint256 _requestId, /* requestId */
    uint256[] memory randomWords
    ) internal override {
   for(uint i; i < requestIdToAmount[_requestId]; i++){
        s_randomRange = (randomWords[0] % supplyLeft) + 1;
        mintNFT(requestToSender[_requestId], s_randomRange);
        emit RandomNumberReceived(s_randomRange, requestToSender[_requestId]);
    }
    
}
}   



