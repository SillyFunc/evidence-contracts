// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

/// @notice Six-category, append-only evidence registry for FISCO BCOS 2.11.
/// @dev Deploy this file alone with Solidity 0.6.10 / Istanbul. FISCO 2.x
///      block.timestamp is milliseconds; createTime is recorded in seconds.
///      Text, amounts, dates and declarations are audited business snapshots.
contract CarbonEvidenceRegistry {
    enum EvidenceCategory {
        Resource,
        Reduction,
        Footprint,
        TradeOffset,
        Asset,
        Technology
    }

    uint256 public constant MAX_ID_BYTES = 128;
    uint256 public constant MAX_TEXT_BYTES = 2048;
    uint256 public constant MAX_LONG_TEXT_BYTES = 6000;
    uint256 public constant MAX_FILES = 32;
    uint256 public constant MAX_PURPOSES = 8;
    uint256 public constant MAX_PAGE_SIZE = 50;

    struct CertificateInfo {
        string issuer;
        string digitalId; // Certificate ID, never a personal identity number.
        uint256 trustedTs; // Business-provided Unix seconds, not verified by this contract.
    }

    /// @dev Authenticated publishing account, distinct from the on-chain administrator.
    struct AuthorInfo {
        string realId; // Authenticated member number.
        string realType;
        string realName;
        string realNo; // Personal identity or organization registration number.
    }

    struct EvidenceSubjectInfo {
        string subjectType;
        string subjectName;
        string subjectNo;
        string legalPerson; // Optional for an individual subject.
    }

    struct OrganizationInfo {
        string orgName;
        string orgType;
        string creditCode;
        string legalPerson; // Applicant organization's representative or responsible person.
        string contactPerson;
        string contactPhone;
        string contactEmail;
        string registeredAddress;
    }

    struct FileInfo {
        string fileType; // Material category, not just MIME type.
        string fileHash; // Calculated from the actual file before submission.
        string fileName; // Generated server name, never the original personal file name.
        uint256 fileSize; // KB, rounded up by the business system.
    }

    /// @dev Includes the authenticated identity and contact snapshots approved for on-chain storage.
    struct EvidenceInput {
        address holderAddress;
        string evidenceNo;
        string evidenceName;
        CertificateInfo certificateInfo;
        EvidenceSubjectInfo evidenceSubject;
        AuthorInfo author;
        OrganizationInfo orgInfo;
        string[] purpose;
        string otherPurpose;
        string auditInstitution;
        string verificationSummary;
        string remark;
        FileInfo[] fileList;
    }

    struct EvidenceCommon {
        EvidenceInput data;
        EvidenceCategory category;
        address creator; // Actual administrator recorded from msg.sender.
        uint256 createTime; // Unix seconds; derived from FISCO 2.x milliseconds.
    }

    struct ResourceProjectInfo {
        string projectName;
        string resourceType;
        string resourceSubType;
        string projectAddr;
        string recordNo;
        string projectArea;
        string projectPeriod;
    }

    struct ResourceCoreData {
        string applyCarbonSinkAmount;
        string detectPeriod;
        string methodology;
    }

    struct ReductionProjectInfo {
        string reduceType;
        string projectName;
        string projectAddr;
        string recordNo;
        string projectScale;
        string projectPeriod;
        string techRoute;
    }

    struct ReductionCoreData {
        string applyReduceAmount;
        string detectPeriod;
        string methodology;
    }

    struct FootprintProjectInfo {
        string footprintType;
        string objectName;
        string boundaryDesc;
        string baseYearUnit;
        string applyStandard;
        string collectPeriod;
    }

    struct FootprintCoreData {
        string applyEmissionAmount;
        string calculatePeriod;
        string emissionStandard;
    }

    struct TradeOffsetProjectInfo {
        string subType;
        string creditSource;
        string sourceCertNo;
        string registerPlatform;
        string cancelTradeNo;
        string counterParty;
        string tradePrice;
        string carbonNeutralScope;
    }

    struct TradeOffsetCoreData {
        string certAmount;
        string tradeOffsetDate;
        bool repeatPreventDeclare;
    }

    struct AssetProjectInfo {
        string assetType;
        string registerPlatform;
        string accountId;
        string assetRegisterNo;
        string sourceProjectName;
        string holdStartDate;
    }

    struct AssetCoreData {
        string holdAmount;
        bool sourceCompliant;
        bool unencumbered;
        bool pledgePurposeApplicable;
        string pledgePurpose;
        bool pledgeAgreementApplicable;
    }

    struct TechnologyProjectInfo {
        string techEvidenceType;
        string techName;
        string techField;
        string developOrg;
        string techMaturity;
        string ipNo;
        string applicationCase;
    }

    struct TechnologyCoreData {
        string coreCarbonIndex;
        string validPeriod;
        string evaluateStandard;
    }

    address public owner;
    mapping(address => bool) public admins;
    mapping(string => bool) public evidenceNoExists;
    mapping(string => EvidenceCommon) private _common;
    string[] private _evidenceNumbers;
    mapping(string => ResourceProjectInfo) private _resourceProjects;
    mapping(string => ResourceCoreData) private _resourceCore;
    mapping(string => ReductionProjectInfo) private _reductionProjects;
    mapping(string => ReductionCoreData) private _reductionCore;
    mapping(string => FootprintProjectInfo) private _footprintProjects;
    mapping(string => FootprintCoreData) private _footprintCore;
    mapping(string => TradeOffsetProjectInfo) private _tradeOffsetProjects;
    mapping(string => TradeOffsetCoreData) private _tradeOffsetCore;
    mapping(string => AssetProjectInfo) private _assetProjects;
    mapping(string => AssetCoreData) private _assetCore;
    mapping(string => TechnologyProjectInfo) private _technologyProjects;
    mapping(string => TechnologyCoreData) private _technologyCore;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AdminUpdated(address indexed account, bool enabled, address indexed operator);
    event EvidenceCreated(
        bytes32 indexed evidenceKey,
        address indexed holderAddress,
        EvidenceCategory indexed category,
        string evidenceNo,
        address creator,
        uint256 createTime
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "owner only");
        _;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "admin only");
        _;
    }

    /// @notice Set the management wallet explicitly, independently of the deployment signer.
    constructor(address initialOwner) public {
        require(initialOwner != address(0), "owner zero");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Owner and administrator are independent roles; granting an existing admin is a silent no-op.
    function setAdmin(address account) external onlyOwner {
        _updateAdmin(account, true);
    }

    /// @notice Revoke administrator rights; revoking a non-admin is a silent no-op.
    function removeAdmin(address account) external onlyOwner {
        _updateAdmin(account, false);
    }

    /// @dev AdminUpdated is emitted only for actual changes, so indexers can rebuild the admin set from events.
    function _updateAdmin(address account, bool enabled) internal {
        require(account != address(0), "admin zero");
        if (admins[account] == enabled) return;
        admins[account] = enabled;
        emit AdminUpdated(account, enabled, msg.sender);
    }

    /// @notice Transfer ownership immediately; only the current Owner can call.
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "owner zero");
        require(newOwner != owner, "same owner");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function createResourceEvidence(
        EvidenceInput memory input,
        ResourceProjectInfo memory project,
        ResourceCoreData memory core
    ) public onlyAdmin returns (bool) {
        _validateResource(project, core);
        _createCommon(input, EvidenceCategory.Resource);
        _resourceProjects[input.evidenceNo] = project;
        _resourceCore[input.evidenceNo] = core;
        return true;
    }

    function getResourceEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, ResourceProjectInfo memory project, ResourceCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.Resource);
        return (_common[evidenceNo], _resourceProjects[evidenceNo], _resourceCore[evidenceNo]);
    }

    function createReductionEvidence(
        EvidenceInput memory input,
        ReductionProjectInfo memory project,
        ReductionCoreData memory core
    ) public onlyAdmin returns (bool) {
        _validateReduction(project, core);
        _createCommon(input, EvidenceCategory.Reduction);
        _reductionProjects[input.evidenceNo] = project;
        _reductionCore[input.evidenceNo] = core;
        return true;
    }

    function getReductionEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, ReductionProjectInfo memory project, ReductionCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.Reduction);
        return (_common[evidenceNo], _reductionProjects[evidenceNo], _reductionCore[evidenceNo]);
    }

    function createFootprintEvidence(
        EvidenceInput memory input,
        FootprintProjectInfo memory project,
        FootprintCoreData memory core
    ) public onlyAdmin returns (bool) {
        _validateFootprint(project, core);
        _createCommon(input, EvidenceCategory.Footprint);
        _footprintProjects[input.evidenceNo] = project;
        _footprintCore[input.evidenceNo] = core;
        return true;
    }

    function getFootprintEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, FootprintProjectInfo memory project, FootprintCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.Footprint);
        return (_common[evidenceNo], _footprintProjects[evidenceNo], _footprintCore[evidenceNo]);
    }

    function createTradeOffsetEvidence(
        EvidenceInput memory input,
        TradeOffsetProjectInfo memory project,
        TradeOffsetCoreData memory core
    ) public onlyAdmin returns (bool) {
        _validateTradeOffset(project, core);
        _createCommon(input, EvidenceCategory.TradeOffset);
        _tradeOffsetProjects[input.evidenceNo] = project;
        _tradeOffsetCore[input.evidenceNo] = core;
        return true;
    }

    function getTradeOffsetEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, TradeOffsetProjectInfo memory project, TradeOffsetCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.TradeOffset);
        return (_common[evidenceNo], _tradeOffsetProjects[evidenceNo], _tradeOffsetCore[evidenceNo]);
    }

    function createAssetEvidence(EvidenceInput memory input, AssetProjectInfo memory project, AssetCoreData memory core)
        public
        onlyAdmin
        returns (bool)
    {
        _validateAsset(project, core);
        if (core.pledgeAgreementApplicable) {
            require(input.fileList.length <= MAX_FILES, "file count");
            bool found;
            for (uint256 i = 0; i < input.fileList.length; i++) {
                if (keccak256(bytes(input.fileList[i].fileType)) == keccak256(bytes("pledgeAgreement"))) {
                    found = true;
                    break;
                }
            }
            require(found, "pledge agreement required");
        }
        _createCommon(input, EvidenceCategory.Asset);
        _assetProjects[input.evidenceNo] = project;
        _assetCore[input.evidenceNo] = core;
        return true;
    }

    function getAssetEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, AssetProjectInfo memory project, AssetCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.Asset);
        return (_common[evidenceNo], _assetProjects[evidenceNo], _assetCore[evidenceNo]);
    }

    function createTechnologyEvidence(
        EvidenceInput memory input,
        TechnologyProjectInfo memory project,
        TechnologyCoreData memory core
    ) public onlyAdmin returns (bool) {
        _validateTechnology(project, core);
        _createCommon(input, EvidenceCategory.Technology);
        _technologyProjects[input.evidenceNo] = project;
        _technologyCore[input.evidenceNo] = core;
        return true;
    }

    function getTechnologyEvidence(string memory evidenceNo)
        public
        view
        returns (EvidenceCommon memory common, TechnologyProjectInfo memory project, TechnologyCoreData memory core)
    {
        _requireCategory(evidenceNo, EvidenceCategory.Technology);
        return (_common[evidenceNo], _technologyProjects[evidenceNo], _technologyCore[evidenceNo]);
    }

    function getEvidenceCommon(string memory evidenceNo) public view returns (EvidenceCommon memory) {
        require(evidenceNoExists[evidenceNo], "not found");
        return _common[evidenceNo];
    }

    function getEvidenceCount() external view returns (uint256) {
        return _evidenceNumbers.length;
    }

    /// @notice Numbers are returned in creation order, using a zero-based offset.
    function getEvidenceNumbers(uint256 offset, uint256 limit) external view returns (string[] memory) {
        require(limit > 0 && limit <= MAX_PAGE_SIZE, "page limit");
        uint256 total = _evidenceNumbers.length;
        if (offset >= total) return new string[](0);
        uint256 count = total - offset;
        if (count > limit) count = limit;
        string[] memory numbers = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            numbers[i] = _evidenceNumbers[offset + i];
        }
        return numbers;
    }

    function _createCommon(EvidenceInput memory input, EvidenceCategory category) internal {
        _validateCommon(input);
        require(!evidenceNoExists[input.evidenceNo], "number exists");

        EvidenceCommon storage saved = _common[input.evidenceNo];
        saved.data.holderAddress = input.holderAddress;
        saved.data.evidenceNo = input.evidenceNo;
        saved.data.evidenceName = input.evidenceName;
        saved.data.certificateInfo = input.certificateInfo;
        saved.data.evidenceSubject = input.evidenceSubject;
        saved.data.author = input.author;
        saved.data.orgInfo = input.orgInfo;
        saved.data.otherPurpose = input.otherPurpose;
        saved.data.auditInstitution = input.auditInstitution;
        saved.data.verificationSummary = input.verificationSummary;
        saved.data.remark = input.remark;
        for (uint256 i = 0; i < input.purpose.length; i++) {
            saved.data.purpose.push(input.purpose[i]);
        }
        // Explicit copy supports arrays of structs containing strings in solc 0.6.10.
        for (uint256 i = 0; i < input.fileList.length; i++) {
            saved.data.fileList.push();
            FileInfo storage file = saved.data.fileList[i];
            file.fileType = input.fileList[i].fileType;
            file.fileHash = input.fileList[i].fileHash;
            file.fileName = input.fileList[i].fileName;
            file.fileSize = input.fileList[i].fileSize;
        }
        saved.category = category;
        saved.creator = msg.sender;
        saved.createTime = block.timestamp / 1000;
        evidenceNoExists[input.evidenceNo] = true;
        _evidenceNumbers.push(input.evidenceNo);
        emit EvidenceCreated(
            keccak256(bytes(input.evidenceNo)),
            input.holderAddress,
            category,
            input.evidenceNo,
            msg.sender,
            saved.createTime
        );
    }

    function _validateCommon(EvidenceInput memory input) internal pure {
        require(input.holderAddress != address(0), "holder zero");
        _text(input.evidenceNo, MAX_ID_BYTES, true);
        _text(input.evidenceName, MAX_TEXT_BYTES, true);
        _text(input.certificateInfo.issuer, MAX_TEXT_BYTES, true);
        _text(input.certificateInfo.digitalId, MAX_ID_BYTES, true);
        _text(input.evidenceSubject.subjectType, MAX_TEXT_BYTES, true);
        _text(input.evidenceSubject.subjectName, MAX_TEXT_BYTES, true);
        _text(input.evidenceSubject.subjectNo, MAX_ID_BYTES, true);
        _text(input.evidenceSubject.legalPerson, MAX_TEXT_BYTES, false);
        _text(input.author.realId, MAX_ID_BYTES, true);
        _text(input.author.realType, MAX_TEXT_BYTES, true);
        _text(input.author.realName, MAX_TEXT_BYTES, true);
        _text(input.author.realNo, MAX_ID_BYTES, true);
        _text(input.orgInfo.orgName, MAX_TEXT_BYTES, true);
        _text(input.orgInfo.orgType, MAX_TEXT_BYTES, true);
        _text(input.orgInfo.creditCode, MAX_ID_BYTES, true);
        _text(input.orgInfo.legalPerson, MAX_TEXT_BYTES, true);
        _text(input.orgInfo.contactPerson, MAX_TEXT_BYTES, true);
        _text(input.orgInfo.contactPhone, MAX_ID_BYTES, true);
        _text(input.orgInfo.contactEmail, MAX_TEXT_BYTES, true);
        _text(input.orgInfo.registeredAddress, MAX_TEXT_BYTES, true);
        _text(input.auditInstitution, MAX_TEXT_BYTES, true);
        _text(input.verificationSummary, MAX_LONG_TEXT_BYTES, true);
        _text(input.otherPurpose, MAX_LONG_TEXT_BYTES, false);
        _text(input.remark, MAX_LONG_TEXT_BYTES, false);
        require(input.purpose.length > 0 && input.purpose.length <= MAX_PURPOSES, "purpose count");
        for (uint256 i = 0; i < input.purpose.length; i++) {
            _text(input.purpose[i], MAX_TEXT_BYTES, true);
        }
        require(input.fileList.length > 0 && input.fileList.length <= MAX_FILES, "file count");
        for (uint256 i = 0; i < input.fileList.length; i++) {
            FileInfo memory file = input.fileList[i];
            _text(file.fileType, 256, true);
            _text(file.fileHash, 256, true);
            _text(file.fileName, 256, true);
            require(file.fileSize > 0, "file size zero");
        }
    }

    function _requireCategory(string memory evidenceNo, EvidenceCategory category) internal view {
        require(evidenceNoExists[evidenceNo], "not found");
        require(_common[evidenceNo].category == category, "wrong category");
    }

    function _text(string memory value, uint256 maxBytes, bool required) internal pure {
        uint256 size = bytes(value).length;
        require(!required || size > 0, "required text");
        require(size <= maxBytes, "text too long");
    }

    function _validateResource(ResourceProjectInfo memory project, ResourceCoreData memory core) internal pure {
        _text(project.projectName, MAX_TEXT_BYTES, true);
        _text(project.resourceType, MAX_TEXT_BYTES, true);
        _text(project.resourceSubType, MAX_TEXT_BYTES, true);
        _text(project.projectAddr, MAX_TEXT_BYTES, true);
        _text(project.recordNo, MAX_TEXT_BYTES, true);
        _text(project.projectArea, MAX_TEXT_BYTES, true);
        _text(project.projectPeriod, MAX_TEXT_BYTES, true);
        _text(core.applyCarbonSinkAmount, MAX_TEXT_BYTES, true);
        _text(core.detectPeriod, MAX_TEXT_BYTES, true);
        _text(core.methodology, MAX_TEXT_BYTES, true);
    }

    function _validateReduction(ReductionProjectInfo memory project, ReductionCoreData memory core) internal pure {
        _text(project.reduceType, MAX_TEXT_BYTES, true);
        _text(project.projectName, MAX_TEXT_BYTES, true);
        _text(project.projectAddr, MAX_TEXT_BYTES, true);
        _text(project.recordNo, MAX_TEXT_BYTES, true);
        _text(project.projectScale, MAX_TEXT_BYTES, true);
        _text(project.projectPeriod, MAX_TEXT_BYTES, true);
        _text(project.techRoute, MAX_TEXT_BYTES, true);
        _text(core.applyReduceAmount, MAX_TEXT_BYTES, true);
        _text(core.detectPeriod, MAX_TEXT_BYTES, true);
        _text(core.methodology, MAX_TEXT_BYTES, true);
    }

    function _validateFootprint(FootprintProjectInfo memory project, FootprintCoreData memory core) internal pure {
        _text(project.footprintType, MAX_TEXT_BYTES, true);
        _text(project.objectName, MAX_TEXT_BYTES, true);
        _text(project.boundaryDesc, MAX_LONG_TEXT_BYTES, true);
        _text(project.baseYearUnit, MAX_TEXT_BYTES, true);
        _text(project.applyStandard, MAX_TEXT_BYTES, true);
        _text(project.collectPeriod, MAX_TEXT_BYTES, true);
        _text(core.applyEmissionAmount, MAX_TEXT_BYTES, true);
        _text(core.calculatePeriod, MAX_TEXT_BYTES, true);
        _text(core.emissionStandard, MAX_TEXT_BYTES, true);
    }

    function _validateTradeOffset(TradeOffsetProjectInfo memory project, TradeOffsetCoreData memory core)
        internal
        pure
    {
        _text(project.subType, MAX_TEXT_BYTES, true);
        _text(project.creditSource, MAX_TEXT_BYTES, true);
        _text(project.sourceCertNo, MAX_TEXT_BYTES, true);
        _text(project.registerPlatform, MAX_TEXT_BYTES, true);
        _text(project.cancelTradeNo, MAX_TEXT_BYTES, true);
        _text(project.counterParty, MAX_TEXT_BYTES, true);
        _text(project.tradePrice, MAX_TEXT_BYTES, false);
        _text(project.carbonNeutralScope, MAX_LONG_TEXT_BYTES, false);
        _text(core.certAmount, MAX_TEXT_BYTES, true);
        _text(core.tradeOffsetDate, MAX_TEXT_BYTES, true);
        require(core.repeatPreventDeclare, "declaration required");
    }

    function _validateAsset(AssetProjectInfo memory project, AssetCoreData memory core) internal pure {
        _text(project.assetType, MAX_TEXT_BYTES, true);
        _text(project.registerPlatform, MAX_TEXT_BYTES, true);
        _text(project.accountId, MAX_ID_BYTES, true);
        _text(project.assetRegisterNo, MAX_TEXT_BYTES, true);
        _text(project.sourceProjectName, MAX_TEXT_BYTES, true);
        _text(project.holdStartDate, MAX_TEXT_BYTES, true);
        _text(core.holdAmount, MAX_TEXT_BYTES, true);
        require(core.sourceCompliant, "declaration required");
        require(core.unencumbered, "declaration required");
        _text(core.pledgePurpose, MAX_LONG_TEXT_BYTES, false);
        require(!core.pledgePurposeApplicable || bytes(core.pledgePurpose).length > 0, "pledge purpose required");
    }

    function _validateTechnology(TechnologyProjectInfo memory project, TechnologyCoreData memory core) internal pure {
        _text(project.techEvidenceType, MAX_TEXT_BYTES, true);
        _text(project.techName, MAX_TEXT_BYTES, true);
        _text(project.techField, MAX_TEXT_BYTES, true);
        _text(project.developOrg, MAX_TEXT_BYTES, true);
        _text(project.techMaturity, MAX_TEXT_BYTES, true);
        _text(project.ipNo, MAX_TEXT_BYTES, false);
        _text(project.applicationCase, MAX_LONG_TEXT_BYTES, false);
        _text(core.coreCarbonIndex, MAX_TEXT_BYTES, true);
        _text(core.validPeriod, MAX_TEXT_BYTES, true);
        _text(core.evaluateStandard, MAX_TEXT_BYTES, true);
    }
}

