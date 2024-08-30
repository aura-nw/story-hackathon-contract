// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

import { LicenseToken } from "@storyprotocol/core/LicenseToken.sol";
import { LicensingModule } from "@storyprotocol/core/modules/licensing/LicensingModule.sol";
import { IPAssetRegistry } from "@storyprotocol/core/registries/IPAssetRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AccessControl.sol";
import "./LaunchpadNFT.sol";

contract StoryLaunchpadNFT721 is AccessControl, IERC721Receiver {
    using SafeERC20 for IERC20;
    address[] public LaunchpadNFTArray;

    mapping(address => bool) public acceptPayTokens;    
    //sender address -> license -> token id -> launchpad phase -> count
    mapping(address => mapping (address => mapping (uint256 => mapping (uint256 => uint256)))) public userBuyCount;
    //license address -> token id -> launchpad phase -> count
    mapping(address => mapping (uint256 => mapping (uint256 => uint256))) public numberOfNftSold;

    address public ipAssetRegistryAddr = 0xd43fE0d865cb5C26b1351d3eAf2E3064BE3276F6;
    address public licensingModuleAddr = 0xe89b0EaA8a0949738efA80bB531a165FB3456CBe;
    address public licenseTokenAddr = 0x1333c78A821c9a576209B01a16dDCEF881cAb6f2;
    address public licenseTemplateAddr = 0x260B6CB6284c89dbE660c0004233f7bB99B5edE7; 

     struct NFTLaunchpad {
        address payable creator;
        address licenseAddress;
        uint256 licenseTokenId;
        string  colectionName;
        uint256 startTime;        
        uint256 endTime;
        uint256 totalQuantity;
        uint256 maxBuy;      
    }

    struct LaunchpadInfor {
        address nftAddress;
        address payToken;
        uint256 price;
        string  uriLauchpad;
        string  uriNFT;
        uint256 royaltyPercentage;
        address royaltyAddress;
    }
 

    // Map from address of nft > nft type > NFTSales.
    mapping (address => mapping (uint256 => mapping (uint256 => NFTLaunchpad))) public NFTLaunchpads;
    mapping (address => mapping (uint256 => mapping (uint256 => LaunchpadInfor))) public LaunchpadInfors;
    mapping (address => mapping (uint256 => uint256)) public licenseSalePhase;

    event NFTLaunchpadCreated(address indexed _licenseAddress, 
                        uint256 indexed _licenseTokenId, 
                        NFTLaunchpad nftLaunchpad);

    event MintNFTSuccessful(
        address indexed _minter,
        uint256 _quantity
    );

    constructor(address _owner) public AccessControl(_owner)  {

    }    


    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    modifier isOpening(address _licenseAddress, uint256 _licenseTokenId) {
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        NFTLaunchpad memory launchpad = NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase];
        require(
            launchpad.startTime <= block.timestamp && block.timestamp < launchpad.endTime,
            "StoryLaunchpad: nft sale should be open"
        );
        _;
    }

    modifier isNotSaleRunning(address _licenseAddress, uint256 _licenseTokenId) {
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        NFTLaunchpad memory launchpad = NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase];
        require(
            launchpad.endTime < block.timestamp,
            "StoryLaunchpad: last nft sale should be end"
        );
        _;
    }    

    modifier notOpen(address _licenseAddress, uint256 _licenseTokenId) {
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        NFTLaunchpad memory launchpad = NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase];
        require(
            block.timestamp < launchpad.startTime,
            "StoryLaunchpad: nft sale should not open"
        );
        _;
    }

    modifier existNftSale(address _licenseAddress, uint256 _licenseTokenId) {
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        NFTLaunchpad memory launchpad = NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase];
        require(launchpad.startTime > 0, "StoryLaunchpad: nft sale should exist");
        _;
    }    

    modifier notExistNftSale(address _licenseAddress, uint256 _licenseTokenId) {
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        if(licensePhase > 0){
        require(NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase].licenseAddress == address(0x0), "StoryLaunchpad: nft sale should not exist");
        _;
        }
    }          

    function _owns(address _licenseAddress,  uint256 _tokenId) internal view returns (bool) {
        LicenseToken _licenseContract = LicenseToken(_licenseAddress);
        return (_licenseContract.ownerOf(_tokenId) == msg.sender);
    }  

    function setAcceptPayToken(address _payToken, bool _accept) public onlyOwner {
        acceptPayTokens[_payToken] = _accept;
    }  

    function setIpAssetRegistryAddr(address _addr) public onlyOwner {
        ipAssetRegistryAddr = _addr;
    }      

    function setLicensingModuleAddr(address _addr) public onlyOwner {
        licensingModuleAddr = _addr;
    }            

    function setLicenseTokenAddr(address _addr) public onlyOwner {
        licenseTokenAddr = _addr;
    }     

    function getCurrentLicensePhase(address _licenseAddress, uint256 _tokenId) public view returns (uint256) {
        return licenseSalePhase[_licenseAddress][_tokenId];
    }      

    function transferHelper(
        address token,
        address payable add,
        uint256 amount
    ) private {
        if (token == address(0)) {
            add.transfer(amount);
        } else {
            IERC20(token).transfer(add, amount);
        }
    }  

    function createNFTSale( NFTLaunchpad memory _launchpad, LaunchpadInfor memory _launchpadInfor
    ) public isNotSaleRunning(_launchpad.licenseAddress, _launchpad.licenseTokenId){

        require(_launchpad.licenseAddress != address(0), "licenseAddress is wrong");
        require(_owns(_launchpad.licenseAddress, _launchpad.licenseTokenId), "StoryLaunchpad: You are not owner license Token");
        require(acceptPayTokens[_launchpadInfor.payToken], "StoryLaunchpad: wrong pay token");
        require(_launchpad.maxBuy > 0, "INVALID maxBuy");
        require(_launchpad.licenseTokenId >= 0, "INVALID licenseTokenId");
        require(_launchpadInfor.price >= 0, "INVALID price");
        require(_launchpad.totalQuantity >= _launchpad.maxBuy, "INVALID totalQuantity");
        require(_launchpad.startTime > block.timestamp, "INVALID startTime");
        require(_launchpad.endTime > _launchpad.startTime, "INVALID endTime");
        require(_launchpadInfor.royaltyPercentage >= 0 && _launchpadInfor.royaltyPercentage <= 100, "INVALID royaltyPercentage");

        LaunchpadNFT launchpadNFT = new LaunchpadNFT(msg.sender, _launchpad.colectionName, "STORYAURANFT");
        LaunchpadNFTArray.push(address(launchpadNFT));

        LaunchpadInfor memory launchpadInfor;
        launchpadInfor = _launchpadInfor;
        launchpadInfor.nftAddress = address(launchpadNFT);

        uint256 currentPhase = getCurrentLicensePhase(_launchpad.licenseAddress, _launchpad.licenseTokenId);
        currentPhase += 1;
        NFTLaunchpads[_launchpad.licenseAddress][_launchpad.licenseTokenId][currentPhase] = _launchpad;
        licenseSalePhase[_launchpad.licenseAddress][_launchpad.licenseTokenId] += 1; // cumulative          

        LaunchpadInfors[_launchpad.licenseAddress][_launchpad.licenseTokenId][currentPhase] = _launchpadInfor;    

        emit NFTLaunchpadCreated(_launchpad.licenseAddress, _launchpad.licenseTokenId, _launchpad);
    }

    function updateInfo(NFTLaunchpad memory _launchpad, LaunchpadInfor memory _launchpadInfor) public 
        onlyOwner() 
        existNftSale(_launchpad.licenseAddress, _launchpad.licenseTokenId)
        notOpen(_launchpad.licenseAddress, _launchpad.licenseTokenId) {

        require(_launchpad.licenseAddress != address(0), "licenseAddress is wrong");
        require(acceptPayTokens[_launchpadInfor.payToken], "StoryLaunchpad: wrong pay token");
        require(_launchpad.maxBuy > 0, "INVALID maxBuy");
        require(_launchpad.licenseTokenId >= 0, "INVALID licenseTokenId");
        require(_launchpadInfor.price >= 0, "INVALID price");
        require(_launchpad.totalQuantity >= _launchpad.maxBuy, "INVALID totalQuantity");
        require(_launchpad.startTime > block.timestamp, "INVALID startTime");
        require(_launchpad.endTime > _launchpad.startTime, "INVALID endTime");
        require(_launchpadInfor.royaltyPercentage >= 0 && _launchpadInfor.royaltyPercentage <= 100, "INVALID royaltyPercentage");

            uint256 currentPhase = getCurrentLicensePhase(_launchpad.licenseAddress, _launchpad.licenseTokenId);
            NFTLaunchpad storage nftLaunchpad = NFTLaunchpads[_launchpad.licenseAddress][_launchpad.licenseTokenId][currentPhase];
            LaunchpadInfor storage launchpadInfor = LaunchpadInfors[_launchpad.licenseAddress][_launchpad.licenseTokenId][currentPhase];

            nftLaunchpad.startTime = _launchpad.startTime;        
            nftLaunchpad.endTime = _launchpad.endTime;
            nftLaunchpad.totalQuantity = _launchpad.totalQuantity;
            nftLaunchpad.maxBuy = _launchpad.maxBuy;
            nftLaunchpad.colectionName = _launchpad.colectionName;

            launchpadInfor.price = _launchpadInfor.price;
            launchpadInfor.uriLauchpad = _launchpadInfor.uriLauchpad;
            launchpadInfor.uriNFT = _launchpadInfor.uriNFT;
            launchpadInfor.royaltyPercentage = _launchpadInfor.royaltyPercentage;
            launchpadInfor.royaltyAddress = _launchpadInfor.royaltyAddress;

    }

    function mintNFT(
        address _licenseAddress,
        uint256 _licenseTokenId,
        uint256 _quantity,
        address _payToken,
        uint256 _payAmount
    ) public payable existNftSale(_licenseAddress, _licenseTokenId) isOpening(_licenseAddress, _licenseTokenId) {

        require(acceptPayTokens[_payToken], "StoryLaunchpad: wrong pay token");
        uint256 amount = 0;
        if (_payToken == address(0)) {
            amount = msg.value;
        } else {
            require(msg.value == 0, "StoryLaunchpad: Invalid msg.value");
            amount = _payAmount;
        }

        _mintNFT(_licenseAddress,
                _licenseTokenId,                
                _quantity,
                _payToken,
                amount);

        emit MintNFTSuccessful(msg.sender,
                            _quantity);
    }

    function _mintNFT(
        address _licenseAddress,
        uint256 _licenseTokenId,
        uint256 _quantity,
        address _payToken,
        uint256 _payAmount
    )
        internal
    {
        require(_licenseAddress != address(0), "StoryLaunchpad: nftAddress is wrong");      
        // Get a reference to the sale struct
        uint256 licensePhase = getCurrentLicensePhase(_licenseAddress, _licenseTokenId);
        NFTLaunchpad storage nftLaunchpad = NFTLaunchpads[_licenseAddress][_licenseTokenId][licensePhase];
        LaunchpadInfor storage launchpadInfor = LaunchpadInfors[_licenseAddress][_licenseTokenId][licensePhase];

        require(_licenseTokenId == nftLaunchpad.licenseTokenId, "StoryLaunchpad: Invalid licenseTokenId");  
        require(_quantity > 0, "StoryLaunchpad: Invalid quantity");    
        require(_quantity <=  nftLaunchpad.maxBuy, "StoryLaunchpad: Invalid quantity"); 
        require(_quantity <= nftLaunchpad.totalQuantity - (numberOfNftSold[_licenseAddress][_licenseTokenId][licensePhase]), "StoryLaunchpad: NFT sold out");
        require(userBuyCount[msg.sender][_licenseAddress][_licenseTokenId][licensePhase] + _quantity <= nftLaunchpad.maxBuy, "StoryLaunchpad: You buy too much");
        
        require(_payAmount >= launchpadInfor.price * _quantity, "StoryLaunchpad: not enough fund");

        numberOfNftSold[_licenseAddress][_licenseTokenId][licensePhase] += _quantity;
        userBuyCount[msg.sender][_licenseAddress][_licenseTokenId][licensePhase] += _quantity;    

        if (_payToken == address(0)) {
            require(msg.value >= launchpadInfor.price * _quantity, "INVALID MSG.VALUE");
        } else {
            require(msg.value == 0, "MSG.VALUE SHOULD BE ZERO");
            IERC20(_payToken).safeTransferFrom(
                msg.sender,
                nftLaunchpad.creator,
                launchpadInfor.price * _quantity
            );
        }        

        if (msg.value > launchpadInfor.price * _quantity) {
            payable(msg.sender).transfer(msg.value - (launchpadInfor.price * _quantity));
        }

        LaunchpadNFT _nftContract = LaunchpadNFT(launchpadInfor.nftAddress);
        for (uint256 i = 0; i < _quantity; i++) {
            //Mint NFT
            uint256 tokenId = _nftContract.mintTokens(address(this), launchpadInfor.uriNFT);
            require(tokenId > 0);

            //Regigter a childIpId for NFT
            address childIpId  = IPAssetRegistry(ipAssetRegistryAddr).register(block.chainid, launchpadInfor.nftAddress, tokenId);

            address[] memory parentIpIds = new address[](1);

            parentIpIds[0] = LicenseToken(_licenseAddress).getLicensorIpId(_licenseTokenId);            

            //Register Derivative for NFT with licenseId
            uint256[] memory licenseTermsIds = new uint256[](1);
            licenseTermsIds[0] = LicenseToken(_licenseAddress).getLicenseTermsId(_licenseTokenId);       

            LicensingModule(licensingModuleAddr).registerDerivative({
                parentIpIds: parentIpIds,                
                childIpId: childIpId,
                licenseTermsIds: licenseTermsIds,
                licenseTemplate: licenseTemplateAddr,
                royaltyContext: "0x0" // empty for PIL
            });     

            _nftContract.safeTransferFrom(address(this), msg.sender, tokenId);         
        }                   
    
    }
}
