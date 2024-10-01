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
import { IRoyaltyModule } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/modules/royalty/IRoyaltyModule.sol";
import { IIPAccount } from "../../node_modules/@story-protocol/protocol-core/contracts/interfaces/IIPAccount.sol";
import { AccessPermission } from "../../node_modules/@story-protocol/protocol-core/contracts/lib/AccessPermission.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./AccessControl.sol";
import "./LaunchpadNFT.sol";

contract DepipGateway is AccessControl, IERC721Receiver {
    using SafeERC20 for IERC20;

    address public ipAssetRegistry = 0x1a9d0d28a0422F26D31Be72Edc6f13ea4371E11B;
    address public licensingModule = 0xd81fd78f557b457b4350cB95D20b547bFEb4D857;
    address public licenseToken = 0xc7A302E03cd7A304394B401192bfED872af501BE;
    address public licenseTemplate = 0x0752f61E59fD2D39193a74610F1bd9a6Ade2E3f9; 
    address public coreMetadataView = 0x48ecAa9F197135A4614d1c7A5Db5641ffd8ad2b9; 
    address public licenseRegistry = 0xedf8e338F05f7B1b857C3a8d3a0aBB4bc2c41723; 
    address public royaltyModule = 0x3C27b2D7d30131D4b58C3584FD7c86e3358744de;
    address public accessController = 0xa8bF970E95278A7aF475CE13C24cdcC3a2234a3D;

    constructor(address _owner) public AccessControl(_owner)  {

    }    

    struct MakeDerivative {
        address[] parentIpIds;
        uint256[] licenseTermsIds;
        bytes royaltyContext;
    }

    struct IPMetadata {
        string ipMetadataURI;
        bytes32 ipMetadataHash;
        string nftMetadataURI;
        bytes32 nftMetadataHash;
    }    

    /// @notice Struct for signature data for execution via IP Account.
    /// @param signer The address of the signer for execution with signature.
    /// @param deadline The deadline for the signature.
    /// @param signature The signature for the execution via IP Account.
    struct SignatureData {
        address signer;
        uint256 deadline;
        bytes signature;
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

    function setaccessController(address _addr) public onlyOwner {
        accessController = _addr;
    }         

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

    function setLicenseTemplate(address _addr) public onlyOwner {
        licenseTemplate = _addr;
    }       

    function setRoyaltyModule(address _addr) public onlyOwner {
        royaltyModule = _addr;
    }       

    function getToken(address ipAccountAddress) public view returns (uint chainId, address tokenContract, uint tokenId) {
        (chainId, tokenContract, tokenId) = IIPAccount(payable(ipAccountAddress)).token();  
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

    function createCollection(string memory colectionName, string memory colectionSymbol) public onlyOperator returns (address collectionAddress){
        collectionAddress = address(new LaunchpadNFT(msg.sender, colectionName, colectionSymbol));
        emit CollectionCreated(address(collectionAddress));
    }   

    function _mintAndRegisterIp(
        address collectionAddress,
        address recipient,
        string memory uri
    ) internal returns (address ipId, uint256 tokenId) {

        tokenId = LaunchpadNFT(collectionAddress).mintTokens(recipient, uri);
        require(tokenId > 0);

        ipId = IIPAssetRegistry(ipAssetRegistry).register(block.chainid, collectionAddress, tokenId); 
    }     

    function mintAndRegisterIpAndAttach(
        address collectionAddress,
        address recipient,
        string memory uri,
        PILTerms calldata terms
    ) public onlyOperator returns (address ipId, uint256 tokenId, uint256 licenseTermsId) {
        (ipId, tokenId) = _mintAndRegisterIp(collectionAddress, address(this), uri);
        //Register and attack PIL
        licenseTermsId = _registerPILTermsAndAttach(ipId, terms);

        LaunchpadNFT(collectionAddress).safeTransferFrom(address(this), recipient, tokenId);
    }

    function registerPilAndAttach(
        address collectionAddress,
        address recipient,
        string memory uri,
        PILTerms calldata terms
    ) public onlyOperator returns (address ipId, uint256 tokenId, uint256 licenseTermsId) {
        (ipId, tokenId) = _mintAndRegisterIp(collectionAddress, address(this), uri);
        //Register and attack PIL
        licenseTermsId = _registerPILTermsAndAttach(ipId, terms);

        LaunchpadNFT(collectionAddress).safeTransferFrom(address(this), recipient, tokenId);
    }  

    /// @notice Register Programmable IP License Terms (if unregistered) and attach it to IP.
    /// @param ipId The ID of the IP.
    /// @param termId The PIL terms ID to attach.
    /// @return licenseTermsId The ID of the newly registered PIL terms.
    /// @param sigAttach Signature data for attachLicenseTerms to the IP via the Licensing Module.
    function attachPILTerms(
        address ipId,
        uint256 termId,
        SignatureData calldata sigAttach
    ) external returns (uint256 licenseTermsId) {

        // Returns if license terms are already attached.
        if (ILicenseRegistry(licenseRegistry).hasIpAttachedLicenseTerms(ipId, licenseTemplate, licenseTermsId)) return licenseTermsId;

        _setPermissionForModule(
            ipId,
            address(licensingModule),
            address(accessController),
            ILicensingModule.attachLicenseTerms.selector,
            sigAttach
        );
                
        ILicensingModule(licensingModule).attachLicenseTerms(ipId, licenseTemplate, licenseTermsId);   
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
        address collectionAddress,
        MakeDerivative calldata derivData,
        IPMetadata calldata ipMetadata,
        address recipient
    ) external onlyOperator returns (address ipId, uint256 tokenId) {
    
        tokenId = LaunchpadNFT(collectionAddress).mintTokens(address(this), ipMetadata.nftMetadataURI);
        require(tokenId > 0);

        ipId = IIPAssetRegistry(ipAssetRegistry).register(block.chainid, collectionAddress, tokenId);

        // MetadataHelper.setMetadata(ipId, address(CORE_METADATA_MODULE), ipMetadata);

        _collectMintFeesAndSetApproval(
            msg.sender,
            derivData.parentIpIds,
            derivData.licenseTermsIds
        );         

        ILicensingModule(licensingModule).registerDerivative({
            childIpId: ipId,
            parentIpIds: derivData.parentIpIds,
            licenseTermsIds: derivData.licenseTermsIds,
            licenseTemplate: licenseTemplate,
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
    /// @param parentIpIds The IDs of all the parent IPs.
    /// @param licenseTermsIds The IDs of the license terms for each corresponding parent IP.
    function _collectMintFeesAndSetApproval(
        address payerAddress,
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

    /// @dev Sets permission via signature to allow this contract to interact with the Licensing Module on behalf of the
    /// provided IP Account.
    /// @param ipId The ID of the IP.
    /// @param module The address of the module to set the permission for.
    /// @param accessController The address of the Access Controller contract.
    /// @param selector The selector of the function to be permitted for execution.
    /// @param sigData Signature data for setting the permission.
    function _setPermissionForModule(
        address ipId,
        address module,
        address accessController,
        bytes4 selector,
        SignatureData calldata sigData
    ) internal {
        IIPAccount(payable(ipId)).executeWithSig(
            accessController,
            0,
            abi.encodeWithSelector(
                IAccessController.setPermission.selector,
                address(ipId),
                address(this),
                address(module),
                selector,
                AccessPermission.ALLOW
            ),
            sigData.signer,
            sigData.deadline,
            sigData.signature
        );
    }

    /// @dev Sets batch permission via signature to allow this contract to interact with mutiple modules
    /// on behalf of the provided IP Account.
    /// @param ipId The ID of the IP.
    /// @param accessController The address of the Access Controller contract.
    /// @param modules The addresses of the modules to set the permission for.
    /// @param selectors The selectors of the functions to be permitted for execution.
    /// @param sigData Signature data for setting the batch permission.
    function _setBatchPermissionForModules(
        address ipId,
        address accessController,
        address[] memory modules,
        bytes4[] memory selectors,
        SignatureData calldata sigData
    ) internal {
        // assumes modules and selectors must have a 1:1 mapping
        AccessPermission.Permission[] memory permissionList = new AccessPermission.Permission[](modules.length);
        for (uint256 i = 0; i < modules.length; i++) {
            permissionList[i] = AccessPermission.Permission({
                ipAccount: ipId,
                signer: address(this),
                to: modules[i],
                func: selectors[i],
                permission: AccessPermission.ALLOW
            });
        }

        IIPAccount(payable(ipId)).executeWithSig(
            accessController,
            0,
            abi.encodeWithSelector(IAccessController.setBatchPermissions.selector, permissionList),
            sigData.signer,
            sigData.deadline,
            sigData.signature
        );
    }         
}
