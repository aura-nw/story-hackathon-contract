// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;
pragma experimental ABIEncoderV2;

import { IAccessController } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/access/IAccessController.sol";
import { IIPAssetRegistry } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/registries/IIPAssetRegistry.sol";
import { ILicenseRegistry } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/registries/ILicenseRegistry.sol";
import { ILicensingModule } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/modules/licensing/ILicensingModule.sol";
import { ICoreMetadataViewModule } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/modules/metadata/ICoreMetadataViewModule.sol";
import { IPILicenseTemplate, PILTerms } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/modules/licensing/IPILicenseTemplate.sol";
import { ILicenseTemplate } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/modules/licensing/ILicenseTemplate.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AccessControl.sol";
import "./LaunchpadNFT.sol";

contract StoryCampaign is AccessControl, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public ipAssetRegistry = 0xd43fE0d865cb5C26b1351d3eAf2E3064BE3276F6;
    address public licensingModule = 0xe89b0EaA8a0949738efA80bB531a165FB3456CBe;
    address public licenseToken = 0x1333c78A821c9a576209B01a16dDCEF881cAb6f2;
    address public licenseTemplate = 0x260B6CB6284c89dbE660c0004233f7bB99B5edE7; 
    address public coreMetadataView = 0x17aD427cd467A85c256acDF57848Ec6383D70dF5; 
    address public licenseRegistry = 0x17aD427cd467A85c256acDF57848Ec6383D70dF5; 

    address public collectionAddress;

    uint256 private maxParents = 5;

    constructor(address _owner) public AccessControl(_owner)  {

    }    

    struct MakeDerivative {
        address[] parentIpIds;
        address licenseTemplate;
        uint256[] licenseTermsIds;
        bytes royaltyContext;
    }

    struct IPMetadata {
        string ipMetadataURI;
        bytes32 ipMetadataHash;
        string nftMetadataURI;
        bytes32 nftMetadataHash;
    }    

    event CollectionCreated(address indexed nftContract);
    /**
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // function _owns(address _licensorIpid) internal view returns (bool) {
    //     return (ICoreMetadataViewModule(coreMetadataView).getOwner(_licensorIpid) == msg.sender);
    // }  

    function setIpAssetRegistry(address _addr) public onlyOwner {
        ipAssetRegistry = _addr;
    }      

    function setLicensingModule(address _addr) public onlyOwner {
        licensingModule = _addr;
    }            

    function setLicenseToken(address _addr) public onlyOwner {
        licenseToken = _addr;
    }     

    function setCoreMetadataView(address _addr) public onlyOwner {
        coreMetadataView = _addr;
    }    

    function setLicenseRegistry(address _addr) public onlyOwner {
        licenseRegistry = _addr;
    }       

    function setCollectionAddress(address _addr) public onlyOwner {
        collectionAddress = _addr;
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

    function createCollection(string memory colectionName, string memory colectionSymbol) public onlyOperator {
        collectionAddress = address(new LaunchpadNFT(msg.sender, colectionName, colectionSymbol));
        emit CollectionCreated(address(collectionAddress));
    }   

    function _mintAndRegisterIp(
        address recipient,
        string memory uri
    ) internal returns (address ipId, uint256 tokenId) {

        tokenId = LaunchpadNFT(collectionAddress).mintTokens(recipient, uri);
        require(tokenId > 0);

        ipId = IIPAssetRegistry(ipAssetRegistry).register(block.chainid, collectionAddress, tokenId); 
    }     

    function mintAndRegisterIpAndAttach(
        address recipient,
        string memory uri,
        PILTerms calldata terms
    ) public onlyOperator returns (address ipId, uint256 tokenId, uint256 licenseTermsId) {

        (ipId, tokenId) = _mintAndRegisterIp(address(this), uri);
        //Register and attack PIL
        licenseTermsId = _registerPILTermsAndAttach(ipId, terms);

        LaunchpadNFT(collectionAddress).safeTransferFrom(address(this), recipient, tokenId);
    }

    function _registerPILTermsAndAttach(
        address ipId,
        PILTerms calldata terms
    ) internal returns (uint256 licenseTermsId) {

        licenseTermsId = IPILicenseTemplate(licenseTemplate).registerLicenseTerms(terms);
        // Returns if license terms are already attached.
        if (ILicenseRegistry(licenseRegistry).hasIpAttachedLicenseTerms(ipId, licenseTemplate, licenseTermsId)) return licenseTermsId;

        ILicensingModule(licensingModule).attachLicenseTerms(ipId, licenseTemplate, licenseTermsId);        

    }
        
    function mintAndRegisterIpAndMakeDerivative(
        MakeDerivative calldata derivData,
        IPMetadata calldata ipMetadata,
        address recipient
    ) external onlyOperator returns (address ipId, uint256 tokenId) {

        require(derivData.parentIpIds.length <= maxParents, "StoryCampaign: AboveParentLimit");

        tokenId = LaunchpadNFT(collectionAddress).mintTokens(address(this), ipMetadata.nftMetadataURI);
        require(tokenId > 0);

        ipId = IIPAssetRegistry(ipAssetRegistry).register(block.chainid, collectionAddress, tokenId);

        // MetadataHelper.setMetadata(ipId, address(CORE_METADATA_MODULE), ipMetadata);

        _collectMintFeesAndSetApproval(
            msg.sender,
            derivData.licenseTemplate,
            derivData.parentIpIds,
            derivData.licenseTermsIds
        );         

        ILicensingModule(licensingModule).registerDerivative({
            childIpId: ipId,
            parentIpIds: derivData.parentIpIds,
            licenseTermsIds: derivData.licenseTermsIds,
            licenseTemplate: derivData.licenseTemplate,
            royaltyContext: derivData.royaltyContext
        });

        LaunchpadNFT(collectionAddress).safeTransferFrom(address(this), recipient, tokenId);
    } 

    /// @dev Aggregate license mint fees for all parent IPs.
    /// @param payerAddress The address of the payer for the license mint fees.
    /// @param parentIpIds The IDs of all the parent IPs.
    /// @param licenseTermsIds The IDs of the license terms for each corresponding parent IP.
    /// @return totalMintFee The sum of license mint fees across all parent IPs.
    function _aggregateMintFees(
        address payerAddress,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds
    ) internal view returns (uint256 totalMintFee) {
        uint256 mintFee;

        for (uint256 i = 0; i < parentIpIds.length; i++) {
            (, mintFee) = ILicensingModule(licensingModule).predictMintingLicenseFee({
                licensorIpId: parentIpIds[i],
                licenseTemplate: licenseTemplate,
                licenseTermsId: licenseTermsIds[i],
                amount: 1,
                receiver: payerAddress,
                royaltyContext: ""
            });
            totalMintFee += mintFee;
        }
    } 

    /// @dev Collect mint fees for all parent IPs from the payer and set approval for Royalty Module to spend mint fees.
    /// @param payerAddress The address of the payer for the license mint fees.
    /// @param royaltyModule The address of the Royalty Module.
    /// @param parentIpIds The IDs of all the parent IPs.
    /// @param licenseTermsIds The IDs of the license terms for each corresponding parent IP.
    function _collectMintFeesAndSetApproval(
        address payerAddress,
        address royaltyModule,
        address[] calldata parentIpIds,
        uint256[] calldata licenseTermsIds
    ) internal {
        ILicenseTemplate lct = ILicenseTemplate(licenseTemplate);
        (address royaltyPolicy, , , address mintFeeCurrencyToken) = lct.getRoyaltyPolicy(licenseTermsIds[0]);

        if (royaltyPolicy != address(0)) {
            // Get total mint fee for all parent IPs
            uint256 totalMintFee = _aggregateMintFees({
                payerAddress: payerAddress,
                parentIpIds: parentIpIds,
                licenseTermsIds: licenseTermsIds
            });

            if (totalMintFee != 0) {
                // Transfer mint fee from payer to this contract
                IERC20(mintFeeCurrencyToken).safeTransferFrom(payerAddress, address(this), totalMintFee);

                // Approve Royalty Policy to spend mint fee
                IERC20(mintFeeCurrencyToken).forceApprove(royaltyModule, totalMintFee);
            }
        }
    }        
}
