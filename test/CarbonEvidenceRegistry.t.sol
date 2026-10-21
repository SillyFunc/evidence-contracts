// SPDX-License-Identifier: MIT
pragma solidity 0.6.10;
pragma experimental ABIEncoderV2;

import "../src/CarbonEvidenceRegistry.sol";

// The test suite deliberately avoids a newer forge-std compiler requirement.
interface RegistryVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address sender) external;
    function expectRevert(bytes calldata revertData) external;
    function warp(uint256 timestamp) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

contract CarbonEvidenceRegistryTest {
    RegistryVm private constant vm = RegistryVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ADMIN = address(0xA11CE);
    address private constant HOLDER = address(0xB0B);
    address private constant NEXT_OWNER = address(0xC0FFEE);
    uint256 private constant FISCO_TIMESTAMP_MS = 1700000000123;
    CarbonEvidenceRegistry private registry;

    function setUp() public {
        registry = new CarbonEvidenceRegistry(address(this));
        registry.setAdmin(ADMIN);
        // FISCO BCOS 2.11 passes milliseconds to block.timestamp.
        vm.warp(FISCO_TIMESTAMP_MS);
    }

    function testOwnerIsIndependentFromAdmin() public {
        require(registry.owner() == address(this), "deployment owner");
        require(!registry.admins(address(this)), "owner unexpectedly admin");
        _expect("admin only");
        registry.createResourceEvidence(_input("OWNER"), _resourceProject(), _resourceCore());

        registry.setAdmin(address(this));
        require(registry.createResourceEvidence(_input("OWNER"), _resourceProject(), _resourceCore()), "owner create");
    }

    function testExplicitInitialOwnerControlsRegistryInsteadOfDeployer() public {
        CarbonEvidenceRegistry explicitRegistry = new CarbonEvidenceRegistry(NEXT_OWNER);
        require(explicitRegistry.owner() == NEXT_OWNER, "explicit owner ignored");
        require(!explicitRegistry.admins(address(this)), "deployer unexpectedly admin");
        require(!explicitRegistry.admins(NEXT_OWNER), "initial owner unexpectedly admin");

        _expect("owner only");
        explicitRegistry.setAdmin(ADMIN);
        _expect("owner only");
        explicitRegistry.transferOwnership(HOLDER);
        _expect("admin only");
        explicitRegistry.createResourceEvidence(_input("DEPLOYER-DENIED"), _resourceProject(), _resourceCore());
        require(!explicitRegistry.evidenceNoExists("DEPLOYER-DENIED"), "deployer created evidence");
        require(explicitRegistry.getEvidenceCount() == 0, "deployer changed index");

        vm.prank(NEXT_OWNER);
        explicitRegistry.setAdmin(ADMIN);
        require(explicitRegistry.admins(ADMIN), "initial owner cannot authorize admin");
        vm.prank(NEXT_OWNER);
        explicitRegistry.transferOwnership(HOLDER);
        require(explicitRegistry.owner() == HOLDER, "initial owner cannot transfer");
        require(explicitRegistry.admins(ADMIN), "transfer revoked admin");
        require(!explicitRegistry.admins(NEXT_OWNER), "initial owner implicitly admin");
        require(!explicitRegistry.admins(HOLDER), "successor implicitly admin");
    }

    function testInitialOwnerCannotBeZero() public {
        _expect("owner zero");
        new CarbonEvidenceRegistry(address(0));
    }

    function testConstructionEmitsSpecifiedOwner() public {
        vm.recordLogs();
        CarbonEvidenceRegistry explicitRegistry = new CarbonEvidenceRegistry(NEXT_OWNER);
        RegistryVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1, "construction event count");
        require(logs[0].emitter == address(explicitRegistry), "construction event emitter");
        require(logs[0].topics.length == 3, "construction event topics");
        require(logs[0].topics[0] == keccak256("OwnershipTransferred(address,address)"), "construction event signature");
        require(logs[0].topics[1] == bytes32(0), "construction event previous owner");
        require(logs[0].topics[2] == bytes32(uint256(uint160(NEXT_OWNER))), "construction event initial owner");
        require(logs[0].data.length == 0, "construction event data");
    }

    function testOnlyOwnerCanManageAdmins() public {
        _expect("owner only");
        vm.prank(ADMIN);
        registry.setAdmin(HOLDER);
        require(!registry.admins(HOLDER), "unauthorized admin addition");

        _expect("admin zero");
        registry.setAdmin(address(0));
    }

    function testMultipleAdminsAndRevocation() public {
        registry.setAdmin(HOLDER);
        _createResource("FIRST");
        vm.prank(HOLDER);
        registry.createResourceEvidence(_input("SECOND"), _resourceProject(), _resourceCore());
        registry.removeAdmin(ADMIN);

        _expect("admin only");
        vm.prank(ADMIN);
        registry.createResourceEvidence(_input("DENIED"), _resourceProject(), _resourceCore());
        require(registry.admins(HOLDER), "other admin revoked");
        require(registry.getEvidenceCount() == 2, "revocation changed records");
        require(!registry.evidenceNoExists("DENIED"), "unauthorized record stored");
    }

    function testOnlyOwnerCanRemoveAdmins() public {
        _expect("owner only");
        vm.prank(ADMIN);
        registry.removeAdmin(ADMIN);
        require(registry.admins(ADMIN), "unauthorized admin removal");

        _expect("admin zero");
        registry.removeAdmin(address(0));
    }

    function testAdminEventsReportGrantAndRevocation() public {
        vm.recordLogs();
        registry.setAdmin(HOLDER);
        registry.removeAdmin(HOLDER);
        RegistryVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 2, "admin event count");
        for (uint256 i = 0; i < 2; i++) {
            require(logs[i].emitter == address(registry), "admin event emitter");
            require(logs[i].topics.length == 3, "admin event topics");
            require(logs[i].topics[0] == keccak256("AdminUpdated(address,bool,address)"), "admin event signature");
            require(logs[i].topics[1] == bytes32(uint256(uint160(HOLDER))), "admin event account");
            require(logs[i].topics[2] == bytes32(uint256(uint160(address(this)))), "admin event operator");
        }
        require(abi.decode(logs[0].data, (bool)), "grant event flag");
        require(!abi.decode(logs[1].data, (bool)), "revoke event flag");
        require(!registry.admins(HOLDER), "admin not removed");
    }

    function testUnchangedAdminStateIsSilentNoOp() public {
        vm.recordLogs();
        registry.removeAdmin(HOLDER);
        registry.setAdmin(ADMIN);
        require(vm.getRecordedLogs().length == 0, "unchanged admin state emitted event");
        require(!registry.admins(HOLDER), "non-admin removal granted admin");
        require(registry.admins(ADMIN), "repeated grant revoked admin");
    }

    function testOwnershipTransferIsImmediateAndPreservesAdmins() public {
        // A previous owner's explicitly granted admin role remains explicit.
        registry.setAdmin(address(this));
        vm.recordLogs();
        registry.transferOwnership(NEXT_OWNER);
        require(registry.owner() == NEXT_OWNER, "owner not changed immediately");
        require(registry.admins(address(this)) && registry.admins(ADMIN), "existing admins changed");
        require(!registry.admins(NEXT_OWNER), "new owner implicitly admin");

        RegistryVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1, "ownership event count");
        require(logs[0].emitter == address(registry), "ownership event emitter");
        require(logs[0].topics.length == 3, "ownership event topics");
        require(logs[0].topics[0] == keccak256("OwnershipTransferred(address,address)"), "ownership event signature");
        require(logs[0].topics[1] == bytes32(uint256(uint160(address(this)))), "ownership event previous owner");
        require(logs[0].topics[2] == bytes32(uint256(uint160(NEXT_OWNER))), "ownership event new owner");
        require(logs[0].data.length == 0, "ownership event data");

        _expect("owner only");
        registry.setAdmin(HOLDER);
        vm.prank(NEXT_OWNER);
        registry.setAdmin(HOLDER);
        require(registry.admins(HOLDER), "new owner cannot manage admins");
    }

    function testOnlyCurrentOwnerCanTransferAgain() public {
        _expect("owner only");
        vm.prank(ADMIN);
        registry.transferOwnership(HOLDER);
        require(registry.owner() == address(this), "admin changed owner");

        registry.transferOwnership(NEXT_OWNER);
        _expect("owner only");
        registry.transferOwnership(HOLDER);
        _expect("owner only");
        vm.prank(ADMIN);
        registry.transferOwnership(HOLDER);
        require(registry.owner() == NEXT_OWNER, "unauthorized owner change");

        vm.prank(NEXT_OWNER);
        registry.transferOwnership(HOLDER);
        require(registry.owner() == HOLDER, "new owner cannot transfer again");
        _expect("owner only");
        vm.prank(NEXT_OWNER);
        registry.setAdmin(NEXT_OWNER);
        vm.prank(HOLDER);
        registry.setAdmin(NEXT_OWNER);
        require(registry.admins(NEXT_OWNER), "successor cannot manage admins");
        require(registry.admins(ADMIN), "transfer revoked existing admin");
        require(!registry.admins(HOLDER), "successor implicitly admin");
    }

    function testInvalidOwnershipTargets() public {
        _expect("owner zero");
        registry.transferOwnership(address(0));
        _expect("same owner");
        registry.transferOwnership(address(this));
        require(registry.owner() == address(this), "invalid target changed owner");

        registry.transferOwnership(NEXT_OWNER);
        _expect("owner zero");
        vm.prank(NEXT_OWNER);
        registry.transferOwnership(address(0));
        _expect("same owner");
        vm.prank(NEXT_OWNER);
        registry.transferOwnership(NEXT_OWNER);
        require(registry.owner() == NEXT_OWNER, "invalid target changed successor");
    }

    function testResourceRoundTripAndFiscoSeconds() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("RESOURCE-001");
        CarbonEvidenceRegistry.ResourceProjectInfo memory project = _resourceProject();
        CarbonEvidenceRegistry.ResourceCoreData memory core = _resourceCore();
        vm.prank(ADMIN);
        require(registry.createResourceEvidence(input, project, core), "resource return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.ResourceProjectInfo memory savedProject,
            CarbonEvidenceRegistry.ResourceCoreData memory savedCore
        ) = registry.getResourceEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Resource);
        require(keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "resource data");
        require(saved.data.certificateInfo.trustedTs == 1699999999, "business timestamp changed");
    }

    function testReductionRoundTrip() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("REDUCTION-001");
        CarbonEvidenceRegistry.ReductionProjectInfo memory project = _reductionProject();
        CarbonEvidenceRegistry.ReductionCoreData memory core = _reductionCore();
        vm.prank(ADMIN);
        require(registry.createReductionEvidence(input, project, core), "reduction return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.ReductionProjectInfo memory savedProject,
            CarbonEvidenceRegistry.ReductionCoreData memory savedCore
        ) = registry.getReductionEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Reduction);
        require(
            keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "reduction data"
        );
    }

    function testFootprintRoundTrip() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("FOOTPRINT-001");
        CarbonEvidenceRegistry.FootprintProjectInfo memory project = _footprintProject();
        CarbonEvidenceRegistry.FootprintCoreData memory core = _footprintCore();
        vm.prank(ADMIN);
        require(registry.createFootprintEvidence(input, project, core), "footprint return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.FootprintProjectInfo memory savedProject,
            CarbonEvidenceRegistry.FootprintCoreData memory savedCore
        ) = registry.getFootprintEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Footprint);
        require(
            keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "footprint data"
        );
    }

    function testTradeOffsetRoundTrip() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("TRADE-001");
        CarbonEvidenceRegistry.TradeOffsetProjectInfo memory project = _tradeProject();
        CarbonEvidenceRegistry.TradeOffsetCoreData memory core = _tradeCore();
        vm.prank(ADMIN);
        require(registry.createTradeOffsetEvidence(input, project, core), "trade return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.TradeOffsetProjectInfo memory savedProject,
            CarbonEvidenceRegistry.TradeOffsetCoreData memory savedCore
        ) = registry.getTradeOffsetEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.TradeOffset);
        require(keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "trade data");
    }

    function testAssetRoundTripWithConditionalPledgeFields() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("ASSET-001");
        input.fileList[1].fileType = "pledgeAgreement";
        CarbonEvidenceRegistry.AssetProjectInfo memory project = _assetProject();
        CarbonEvidenceRegistry.AssetCoreData memory core = _assetCore();
        core.pledgePurposeApplicable = true;
        core.pledgePurpose = "Green financing";
        core.pledgeAgreementApplicable = true;
        vm.prank(ADMIN);
        require(registry.createAssetEvidence(input, project, core), "asset return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.AssetProjectInfo memory savedProject,
            CarbonEvidenceRegistry.AssetCoreData memory savedCore
        ) = registry.getAssetEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Asset);
        require(keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "asset data");
    }

    function testTechnologyRoundTrip() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("TECH-001");
        CarbonEvidenceRegistry.TechnologyProjectInfo memory project = _technologyProject();
        CarbonEvidenceRegistry.TechnologyCoreData memory core = _technologyCore();
        vm.prank(ADMIN);
        require(registry.createTechnologyEvidence(input, project, core), "technology return");
        (
            CarbonEvidenceRegistry.EvidenceCommon memory saved,
            CarbonEvidenceRegistry.TechnologyProjectInfo memory savedProject,
            CarbonEvidenceRegistry.TechnologyCoreData memory savedCore
        ) = registry.getTechnologyEvidence(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Technology);
        require(
            keccak256(abi.encode(savedProject, savedCore)) == keccak256(abi.encode(project, core)), "technology data"
        );
    }

    function testIdentityAndOrganizationFieldsRemainDistinct() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("IDENTITY-ROUNDTRIP");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon(input.evidenceNo);

        _assertString(saved.data.author.realId, "FAKE-MEMBER-ID-001");
        _assertString(saved.data.author.realType, "Personal");
        _assertString(saved.data.author.realName, "Fictional publisher");
        _assertString(saved.data.author.realNo, "FAKE-PUBLISHER-NO-001");
        _assertString(saved.data.evidenceSubject.subjectType, "Enterprise");
        _assertString(saved.data.evidenceSubject.subjectName, "Fictional holder organization");
        _assertString(saved.data.evidenceSubject.subjectNo, "FAKE-SUBJECT-NO-001");
        _assertString(saved.data.evidenceSubject.legalPerson, "Fictional subject representative");
        _assertString(saved.data.orgInfo.orgName, "Fictional applicant institution");
        _assertString(saved.data.orgInfo.orgType, "Research");
        _assertString(saved.data.orgInfo.creditCode, "FAKE-CREDIT-CODE-001");
        _assertString(saved.data.orgInfo.legalPerson, "Fictional applicant representative");
        _assertString(saved.data.orgInfo.contactPerson, "Fictional liaison");
        _assertString(saved.data.orgInfo.contactPhone, "FAKE-PHONE-001");
        _assertString(saved.data.orgInfo.contactEmail, "fictional-contact@example.invalid");
        _assertString(saved.data.orgInfo.registeredAddress, "Fictional applicant address");
        require(saved.creator == ADMIN && saved.data.holderAddress == HOLDER, "identity changed chain addresses");
    }

    function testPersonalSubjectCanOmitLegalPerson() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("PERSONAL-SUBJECT");
        input.evidenceSubject.subjectType = "Personal";
        input.evidenceSubject.subjectName = "Fictional individual holder";
        input.evidenceSubject.legalPerson = "";
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon(input.evidenceNo);
        _assertCommon(saved, input, CarbonEvidenceRegistry.EvidenceCategory.Resource);
        require(bytes(saved.data.evidenceSubject.legalPerson).length == 0, "individual legal person populated");
        _assertString(saved.data.orgInfo.legalPerson, "Fictional applicant representative");
    }

    function testMissingRequiredIdentityFieldsNeverCreatePartialRecord() public {
        // Publisher, subject and applicant fields are independently required.
        for (uint256 i = 0; i < 13; i++) {
            CarbonEvidenceRegistry.EvidenceInput memory input = _input("MISSING-IDENTITY");
            _setRequiredIdentityField(input, i, "");
            _expect("required text");
            vm.prank(ADMIN);
            registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
            require(!registry.evidenceNoExists(input.evidenceNo), "partial identity record");
            require(registry.getEvidenceCount() == 0, "partial identity index");
        }
    }

    function testIdentityIdentifierByteBoundaries() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("IDENTITY-ID-LIMIT");
        string memory maximum = _repeatAscii(registry.MAX_ID_BYTES());
        input.author.realId = maximum;
        input.author.realNo = maximum;
        input.evidenceSubject.subjectNo = maximum;
        input.orgInfo.creditCode = maximum;
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        _assertCommon(
            registry.getEvidenceCommon(input.evidenceNo), input, CarbonEvidenceRegistry.EvidenceCategory.Resource
        );

        string memory excessive = _repeatAscii(registry.MAX_ID_BYTES() + 1);
        for (uint256 i = 0; i < 4; i++) {
            input = _input("IDENTITY-ID-OVERFLOW");
            if (i == 0) input.author.realId = excessive;
            else if (i == 1) input.author.realNo = excessive;
            else if (i == 2) input.evidenceSubject.subjectNo = excessive;
            else input.orgInfo.creditCode = excessive;
            _expect("text too long");
            vm.prank(ADMIN);
            registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
            require(!registry.evidenceNoExists(input.evidenceNo), "oversized identity stored");
            require(registry.getEvidenceCount() == 1, "oversized identity indexed");
        }
    }

    function testAccountIdentifierByteBoundaryAndMissingAccount() public {
        CarbonEvidenceRegistry.AssetProjectInfo memory project = _assetProject();
        project.accountId = _repeatAscii(registry.MAX_ID_BYTES());
        vm.prank(ADMIN);
        registry.createAssetEvidence(_input("ACCOUNT-LIMIT"), project, _assetCore());
        (, CarbonEvidenceRegistry.AssetProjectInfo memory savedProject,) = registry.getAssetEvidence("ACCOUNT-LIMIT");
        _assertString(savedProject.accountId, project.accountId);

        project.accountId = _repeatAscii(registry.MAX_ID_BYTES() + 1);
        _expect("text too long");
        vm.prank(ADMIN);
        registry.createAssetEvidence(_input("ACCOUNT-OVERFLOW"), project, _assetCore());
        require(!registry.evidenceNoExists("ACCOUNT-OVERFLOW"), "oversized account stored");
        project.accountId = "";
        _expect("required text");
        vm.prank(ADMIN);
        registry.createAssetEvidence(_input("ACCOUNT-MISSING"), project, _assetCore());
        require(!registry.evidenceNoExists("ACCOUNT-MISSING"), "missing account stored");
        require(registry.getEvidenceCount() == 1, "invalid account indexed");
    }

    function testTradeCounterPartyIsRequiredAndStored() public {
        CarbonEvidenceRegistry.TradeOffsetProjectInfo memory project = _tradeProject();
        project.counterParty = "";
        _expect("required text");
        vm.prank(ADMIN);
        registry.createTradeOffsetEvidence(_input("COUNTERPARTY-MISSING"), project, _tradeCore());
        require(!registry.evidenceNoExists("COUNTERPARTY-MISSING"), "missing counterparty stored");
        require(registry.getEvidenceCount() == 0, "missing counterparty indexed");

        project.counterParty = "Fictional counterparty";
        vm.prank(ADMIN);
        registry.createTradeOffsetEvidence(_input("COUNTERPARTY-PRESENT"), project, _tradeCore());
        (, CarbonEvidenceRegistry.TradeOffsetProjectInfo memory savedProject,) =
            registry.getTradeOffsetEvidence("COUNTERPARTY-PRESENT");
        _assertString(savedProject.counterParty, "Fictional counterparty");
    }

    function testEvidenceNumberIsUniqueAcrossCategories() public {
        _createResource("GLOBAL-NO");
        _expect("number exists");
        vm.prank(ADMIN);
        registry.createTechnologyEvidence(_input("GLOBAL-NO"), _technologyProject(), _technologyCore());
        require(registry.getEvidenceCount() == 1, "duplicate added to index");
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon("GLOBAL-NO");
        require(saved.category == CarbonEvidenceRegistry.EvidenceCategory.Resource, "duplicate changed category");
    }

    function testDuplicateCannotOverwriteAnyExistingData() public {
        CarbonEvidenceRegistry.EvidenceInput memory original = _input("IMMUTABLE");
        _createResource("IMMUTABLE");
        CarbonEvidenceRegistry.EvidenceInput memory changed = _input("IMMUTABLE");
        changed.holderAddress = NEXT_OWNER;
        changed.fileList[0].fileHash = "replacement-hash";
        changed.remark = "replacement";
        _expect("number exists");
        vm.prank(ADMIN);
        registry.createResourceEvidence(changed, _resourceProject(), _resourceCore());
        _assertCommon(
            registry.getEvidenceCommon("IMMUTABLE"), original, CarbonEvidenceRegistry.EvidenceCategory.Resource
        );
        string[] memory numbers = registry.getEvidenceNumbers(0, 50);
        require(numbers.length == 1, "duplicate index entry");
    }

    function testPublicQueriesRejectMissingNumbersAndWrongCategory() public {
        require(!registry.evidenceNoExists("MISSING"), "missing number exists");
        _expect("not found");
        registry.getEvidenceCommon("MISSING");
        _expect("not found");
        registry.getFootprintEvidence("MISSING");
        _createResource("PUBLIC");
        _expect("wrong category");
        registry.getTechnologyEvidence("PUBLIC");
        vm.prank(HOLDER);
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon("PUBLIC");
        require(saved.data.holderAddress == HOLDER, "public read failed");
    }

    function testPaginationPreservesCreationOrderAndHandlesOutOfRangeOffset() public {
        _createResource("FIRST");
        vm.prank(ADMIN);
        registry.createReductionEvidence(_input("SECOND"), _reductionProject(), _reductionCore());
        _createResource("THIRD");
        require(registry.getEvidenceCount() == 3, "total count");
        string[] memory first = registry.getEvidenceNumbers(0, 2);
        require(first.length == 2, "first page length");
        _assertString(first[0], "FIRST");
        _assertString(first[1], "SECOND");
        string[] memory last = registry.getEvidenceNumbers(2, 50);
        require(last.length == 1, "last page length");
        _assertString(last[0], "THIRD");
        require(registry.getEvidenceNumbers(3, 1).length == 0, "end offset");
        require(registry.getEvidenceNumbers(uint256(-1), 1).length == 0, "overflowing offset");
    }

    function testPaginationRejectsInvalidLimits() public {
        require(registry.getEvidenceNumbers(0, 1).length == 0, "empty registry page");
        uint256 excessiveLimit = registry.MAX_PAGE_SIZE() + 1;
        _expect("page limit");
        registry.getEvidenceNumbers(0, 0);
        _expect("page limit");
        registry.getEvidenceNumbers(0, excessiveLimit);
    }

    function testRejectsZeroHolderAndMissingRequiredTextWithoutPartialRecord() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("INVALID-COMMON");
        input.holderAddress = address(0);
        _expect("holder zero");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        input.holderAddress = HOLDER;
        input.evidenceName = "";
        _expect("required text");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        require(!registry.evidenceNoExists(input.evidenceNo), "partial failed record");
        require(registry.getEvidenceCount() == 0, "failed record index");
    }

    function testRejectsMissingFileHashAndZeroSize() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("INVALID-FILE");
        input.fileList[0].fileHash = "";
        _expect("required text");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        input.fileList[0].fileHash = "verified-hash";
        input.fileList[0].fileSize = 0;
        _expect("file size zero");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        require(!registry.evidenceNoExists(input.evidenceNo), "invalid file stored");
    }

    function testRejectsEmptyPurposeAndFileLists() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("EMPTY-LIST");
        input.purpose = new string[](0);
        _expect("purpose count");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        input = _input("EMPTY-LIST");
        input.fileList = new CarbonEvidenceRegistry.FileInfo[](0);
        _expect("file count");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
    }

    function testPurposeAndFileCountBoundaries() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("LIST-LIMIT");
        input.purpose = new string[](registry.MAX_PURPOSES());
        for (uint256 i = 0; i < input.purpose.length; i++) {
            input.purpose[i] = "Disclosure";
        }
        input.fileList = _files(registry.MAX_FILES());
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon(input.evidenceNo);
        require(saved.data.purpose.length == registry.MAX_PURPOSES(), "max purposes lost");
        require(saved.data.fileList.length == registry.MAX_FILES(), "max files lost");

        input.evidenceNo = "TOO-MANY-PURPOSES";
        input.purpose = new string[](registry.MAX_PURPOSES() + 1);
        _expect("purpose count");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        input = _input("TOO-MANY-FILES");
        input.fileList = _files(registry.MAX_FILES() + 1);
        _expect("file count");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
    }

    function testEvidenceNumberByteLengthBoundary() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input(_repeatAscii(registry.MAX_ID_BYTES()));
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        require(registry.evidenceNoExists(input.evidenceNo), "maximum ID rejected");
        input.evidenceNo = _repeatAscii(registry.MAX_ID_BYTES() + 1);
        _expect("text too long");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
    }

    function testUtf8LongTextByteBoundary() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("UTF8-BOUNDARY");
        input.verificationSummary = _repeatChinese(2000);
        require(bytes(input.verificationSummary).length == registry.MAX_LONG_TEXT_BYTES(), "UTF8 test setup");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
        _assertString(registry.getEvidenceCommon(input.evidenceNo).data.verificationSummary, input.verificationSummary);

        input.evidenceNo = "UTF8-OVERFLOW";
        input.verificationSummary = _repeatChinese(2001);
        _expect("text too long");
        vm.prank(ADMIN);
        registry.createResourceEvidence(input, _resourceProject(), _resourceCore());
    }

    function testProjectTextByteBoundary() public {
        CarbonEvidenceRegistry.ResourceProjectInfo memory project = _resourceProject();
        project.projectName = _repeatAscii(registry.MAX_TEXT_BYTES());
        vm.prank(ADMIN);
        registry.createResourceEvidence(_input("PROJECT-LIMIT"), project, _resourceCore());
        project.projectName = _repeatAscii(registry.MAX_TEXT_BYTES() + 1);
        _expect("text too long");
        vm.prank(ADMIN);
        registry.createResourceEvidence(_input("PROJECT-OVERFLOW"), project, _resourceCore());
        require(!registry.evidenceNoExists("PROJECT-OVERFLOW"), "oversized project stored");
    }

    function testAssetPledgePurposeAndAgreementRequirements() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("ASSET-INVALID");
        CarbonEvidenceRegistry.AssetCoreData memory core = _assetCore();
        core.pledgePurposeApplicable = true;
        _expect("pledge purpose required");
        vm.prank(ADMIN);
        registry.createAssetEvidence(input, _assetProject(), core);
        core.pledgePurpose = "Green financing";
        core.pledgeAgreementApplicable = true;
        _expect("pledge agreement required");
        vm.prank(ADMIN);
        registry.createAssetEvidence(input, _assetProject(), core);
        require(!registry.evidenceNoExists(input.evidenceNo), "incomplete pledge record");
        input.fileList[0].fileType = "pledgeAgreement";
        vm.prank(ADMIN);
        registry.createAssetEvidence(input, _assetProject(), core);
        require(registry.getEvidenceCount() == 1, "pledge completion failed");
    }

    function testAssetAndTradeDeclarationsAreRequired() public {
        CarbonEvidenceRegistry.AssetCoreData memory assetCore = _assetCore();
        assetCore.sourceCompliant = false;
        _expect("declaration required");
        vm.prank(ADMIN);
        registry.createAssetEvidence(_input("BAD-ASSET"), _assetProject(), assetCore);
        assetCore.sourceCompliant = true;
        assetCore.unencumbered = false;
        _expect("declaration required");
        vm.prank(ADMIN);
        registry.createAssetEvidence(_input("BAD-ASSET"), _assetProject(), assetCore);

        CarbonEvidenceRegistry.TradeOffsetCoreData memory tradeCore = _tradeCore();
        tradeCore.repeatPreventDeclare = false;
        _expect("declaration required");
        vm.prank(ADMIN);
        registry.createTradeOffsetEvidence(_input("BAD-TRADE"), _tradeProject(), tradeCore);
        require(registry.getEvidenceCount() == 0, "unaccepted declarations stored");
    }

    function testOptionalFieldsCanBeEmpty() public {
        CarbonEvidenceRegistry.EvidenceInput memory input = _input("OPTIONAL-TECH");
        input.otherPurpose = "";
        input.remark = "";
        CarbonEvidenceRegistry.TechnologyProjectInfo memory project = _technologyProject();
        project.ipNo = "";
        project.applicationCase = "";
        vm.prank(ADMIN);
        registry.createTechnologyEvidence(input, project, _technologyCore());
        CarbonEvidenceRegistry.EvidenceCommon memory saved = registry.getEvidenceCommon(input.evidenceNo);
        require(bytes(saved.data.remark).length == 0 && bytes(saved.data.otherPurpose).length == 0, "optional defaults");
        CarbonEvidenceRegistry.TradeOffsetProjectInfo memory trade = _tradeProject();
        trade.tradePrice = "";
        trade.carbonNeutralScope = "";
        vm.prank(ADMIN);
        registry.createTradeOffsetEvidence(_input("OPTIONAL-TRADE"), trade, _tradeCore());
        require(registry.getEvidenceCount() == 2, "optional fields rejected");
    }

    function testEvidenceCreatedEventContainsIndexAndRecordedMetadata() public {
        vm.recordLogs();
        _createResource("EVENT-NO");
        RegistryVm.Log[] memory logs = vm.getRecordedLogs();
        require(logs.length == 1 && logs[0].emitter == address(registry), "event emitter or count");
        require(logs[0].topics.length == 4, "event topics");
        require(
            logs[0].topics[0] == keccak256("EvidenceCreated(bytes32,address,uint8,string,address,uint256)"),
            "event signature"
        );
        require(logs[0].topics[1] == keccak256(bytes("EVENT-NO")), "event number index");
        require(logs[0].topics[2] == bytes32(uint256(uint160(HOLDER))), "event holder index");
        require(
            logs[0].topics[3] == bytes32(uint256(CarbonEvidenceRegistry.EvidenceCategory.Resource)),
            "event category index"
        );
        (string memory evidenceNo, address creator, uint256 createTime) =
            abi.decode(logs[0].data, (string, address, uint256));
        _assertString(evidenceNo, "EVENT-NO");
        require(creator == ADMIN && createTime == FISCO_TIMESTAMP_MS / 1000, "event recorded metadata");
    }

    function testFuzzUnauthorizedCannotCreate(address caller) public {
        if (caller == ADMIN) return;
        _expect("admin only");
        vm.prank(caller);
        registry.createResourceEvidence(_input("FUZZ-DENIED"), _resourceProject(), _resourceCore());
        require(registry.getEvidenceCount() == 0, "unauthorized count");
    }

    function _createResource(string memory evidenceNo) private {
        vm.prank(ADMIN);
        require(
            registry.createResourceEvidence(_input(evidenceNo), _resourceProject(), _resourceCore()), "create failed"
        );
    }

    function _input(string memory evidenceNo) private pure returns (CarbonEvidenceRegistry.EvidenceInput memory input) {
        input.holderAddress = HOLDER;
        input.evidenceNo = evidenceNo;
        // UTF-8 bytes for a Chinese evidence name, compatible with solc 0.6.10.
        input.evidenceName = string(hex"e7a2b3e6b187e8b584e6ba90e5ad98e8af81");
        input.certificateInfo = CarbonEvidenceRegistry.CertificateInfo("Public issuer", "CERT-001", 1699999999);
        input.evidenceSubject = CarbonEvidenceRegistry.EvidenceSubjectInfo(
            "Enterprise", "Fictional holder organization", "FAKE-SUBJECT-NO-001", "Fictional subject representative"
        );
        input.author = CarbonEvidenceRegistry.AuthorInfo(
            "FAKE-MEMBER-ID-001", "Personal", "Fictional publisher", "FAKE-PUBLISHER-NO-001"
        );
        input.orgInfo = CarbonEvidenceRegistry.OrganizationInfo(
            "Fictional applicant institution",
            "Research",
            "FAKE-CREDIT-CODE-001",
            "Fictional applicant representative",
            "Fictional liaison",
            "FAKE-PHONE-001",
            "fictional-contact@example.invalid",
            "Fictional applicant address"
        );
        input.purpose = new string[](2);
        input.purpose[0] = "ESG disclosure";
        input.purpose[1] = "Green financing";
        input.otherPurpose = "Other approved public use";
        input.auditInstitution = "Public verifier";
        input.verificationSummary = "Verified snapshot, version 1";
        input.remark = "Public business note";
        input.fileList = _files(2);
        input.fileList[1].fileHash = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        input.fileList[1].fileName = "generated-file-002.pdf";
        input.fileList[1].fileSize = 42;
    }

    function _setRequiredIdentityField(
        CarbonEvidenceRegistry.EvidenceInput memory input,
        uint256 index,
        string memory value
    ) private pure {
        if (index == 0) input.author.realId = value;
        else if (index == 1) input.author.realType = value;
        else if (index == 2) input.author.realName = value;
        else if (index == 3) input.author.realNo = value;
        else if (index == 4) input.evidenceSubject.subjectType = value;
        else if (index == 5) input.evidenceSubject.subjectName = value;
        else if (index == 6) input.evidenceSubject.subjectNo = value;
        else if (index == 7) input.orgInfo.creditCode = value;
        else if (index == 8) input.orgInfo.legalPerson = value;
        else if (index == 9) input.orgInfo.contactPerson = value;
        else if (index == 10) input.orgInfo.contactPhone = value;
        else if (index == 11) input.orgInfo.contactEmail = value;
        else input.orgInfo.registeredAddress = value;
    }

    function _files(uint256 count) private pure returns (CarbonEvidenceRegistry.FileInfo[] memory files) {
        files = new CarbonEvidenceRegistry.FileInfo[](count);
        for (uint256 i = 0; i < count; i++) {
            files[i] = CarbonEvidenceRegistry.FileInfo(
                "verificationReport",
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "generated-file-001.pdf",
                1024
            );
        }
    }

    function _resourceProject() private pure returns (CarbonEvidenceRegistry.ResourceProjectInfo memory) {
        return CarbonEvidenceRegistry.ResourceProjectInfo(
            "Public forest project",
            "Forestry",
            "Afforestation",
            "Province / City / County",
            "REC-001",
            "123.45",
            "2026/2046"
        );
    }

    function _resourceCore() private pure returns (CarbonEvidenceRegistry.ResourceCoreData memory) {
        return CarbonEvidenceRegistry.ResourceCoreData("1234.567", "2026-01-01/2026-12-31", "METHOD-001");
    }

    function _reductionProject() private pure returns (CarbonEvidenceRegistry.ReductionProjectInfo memory) {
        return CarbonEvidenceRegistry.ReductionProjectInfo(
            "Renewable energy",
            "Wind project",
            "Public project location",
            "RED-REC-001",
            "2.75",
            "2026/2046",
            "Wind generation"
        );
    }

    function _reductionCore() private pure returns (CarbonEvidenceRegistry.ReductionCoreData memory) {
        return CarbonEvidenceRegistry.ReductionCoreData("987.654", "2026-01-01/2026-12-31", "CCER-METHOD-001");
    }

    function _footprintProject() private pure returns (CarbonEvidenceRegistry.FootprintProjectInfo memory) {
        return CarbonEvidenceRegistry.FootprintProjectInfo(
            "Product", "Public product", "Cradle to gate", "2026 / one tonne", "ISO 14067", "2026-01-01/2026-12-31"
        );
    }

    function _footprintCore() private pure returns (CarbonEvidenceRegistry.FootprintCoreData memory) {
        return CarbonEvidenceRegistry.FootprintCoreData("12.345", "2026-01-01/2026-12-31", "ISO 14067");
    }

    function _tradeProject() private pure returns (CarbonEvidenceRegistry.TradeOffsetProjectInfo memory) {
        return CarbonEvidenceRegistry.TradeOffsetProjectInfo(
            "Carbon retirement",
            "CCER",
            "SOURCE-CERT-001",
            "CCER registry",
            "CANCEL-001",
            "Fictional counterparty",
            "88.25",
            "Public approved scope"
        );
    }

    function _tradeCore() private pure returns (CarbonEvidenceRegistry.TradeOffsetCoreData memory) {
        return CarbonEvidenceRegistry.TradeOffsetCoreData("56.789", "2026-10-14", true);
    }

    function _assetProject() private pure returns (CarbonEvidenceRegistry.AssetProjectInfo memory) {
        return CarbonEvidenceRegistry.AssetProjectInfo(
            "CCER", "CCER registry", "FAKE-ACCOUNT-001", "ASSET-REG-001", "Public forest project", "2026-10-14"
        );
    }

    function _assetCore() private pure returns (CarbonEvidenceRegistry.AssetCoreData memory) {
        return CarbonEvidenceRegistry.AssetCoreData("100.123", true, true, false, "", false);
    }

    function _technologyProject() private pure returns (CarbonEvidenceRegistry.TechnologyProjectInfo memory) {
        return CarbonEvidenceRegistry.TechnologyProjectInfo(
            "Methodology",
            "Public technology",
            "Forestry",
            "Public research institution",
            "Demonstration",
            "IP-001",
            "Public demonstration project"
        );
    }

    function _technologyCore() private pure returns (CarbonEvidenceRegistry.TechnologyCoreData memory) {
        return CarbonEvidenceRegistry.TechnologyCoreData("200.125", "5", "EVAL-001");
    }

    function _assertCommon(
        CarbonEvidenceRegistry.EvidenceCommon memory saved,
        CarbonEvidenceRegistry.EvidenceInput memory expected,
        CarbonEvidenceRegistry.EvidenceCategory category
    ) private pure {
        require(keccak256(abi.encode(saved.data)) == keccak256(abi.encode(expected)), "common data roundtrip");
        require(saved.category == category, "category metadata");
        require(saved.creator == ADMIN, "creator metadata");
        require(saved.creator != saved.data.holderAddress, "creator confused with holder");
        require(saved.createTime == FISCO_TIMESTAMP_MS / 1000, "seconds metadata");
    }

    function _assertString(string memory actual, string memory expected) private pure {
        require(keccak256(bytes(actual)) == keccak256(bytes(expected)), "string mismatch");
    }

    function _expect(string memory reason) private {
        vm.expectRevert(abi.encodeWithSignature("Error(string)", reason));
    }

    function _repeatAscii(uint256 count) private pure returns (string memory) {
        bytes memory value = new bytes(count);
        for (uint256 i = 0; i < count; i++) {
            value[i] = bytes1(uint8(65));
        }
        return string(value);
    }

    function _repeatChinese(uint256 count) private pure returns (string memory) {
        bytes memory value = new bytes(count * 3);
        for (uint256 i = 0; i < count; i++) {
            value[i * 3] = 0xE7;
            value[i * 3 + 1] = 0xA2;
            value[i * 3 + 2] = 0xB3;
        }
        return string(value);
    }
}
