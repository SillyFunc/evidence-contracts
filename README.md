# 碳汇数字存证合约

`CarbonEvidenceRegistry` 在一个合约实例中管理六类碳汇数字存证。管理员提交完整资料后，合约保存记录，并提供按编号查询及编号分页查询。

合约源码：[CarbonEvidenceRegistry.sol](src/CarbonEvidenceRegistry.sol)。

## 编译与部署

| 配置 | 值 |
| --- | --- |
| 区块链 | FISCO BCOS 2.11.0，非国密模式 |
| 部署工具 | WeBASE |
| Solidity | `0.6.10` |
| ABI 编码 | `ABIEncoderV2` |
| EVM 目标 | `istanbul` |
| 优化器 | 开启，`200` runs |
| 构造参数 | `address initialOwner`：初始 Owner 的链地址，不能为零地址 |
| 外部合约依赖 | 无 |

将合约源码导入 WeBASE，按上述配置编译，在构造参数 `initialOwner` 中填写自己控制的钱包地址后部署。WeBASE 用于签署部署交易的账户与初始 Owner 可以不同。调用接口时使用对应编译产物的 ABI，按结构体字段顺序编码参数。

部署成功后调用 `owner()`，确认返回的地址与填写的 `initialOwner` 一致。调用 `setAdmin`、`transferOwnership` 时，交易必须由当前 Owner 对应的私钥签名：可通过 FISCO SDK 使用该钱包私钥发起调用，或在 WeBASE 中使用与 Owner 地址匹配的私钥用户。在 WeBASE 中登记一个公钥地址不会获得该地址的签名能力。

本地编译和验证命令：

```shell
forge build
python scripts/check_contract_size.py
forge test
forge fmt --check src/CarbonEvidenceRegistry.sol test/CarbonEvidenceRegistry.t.sol
```

`foundry.toml` 的合约大小上限为 `262144` 字节，大小检查脚本读取编译产物进行检查。Foundry 配置跳过 `Counter` 示例合约、测试和脚本。部署与实际交易执行使用 WeBASE 或 FISCO SDK。

VS Code 的 JuanBlanco Solidity 扩展使用项目中的 `.vscode/settings.json`，编译器固定为 `v0.6.10+commit.00c0fcaf`。首次使用由扩展下载对应编译器；修改配置后可执行 `Developer: Reload Window` 重新加载。编辑器、Foundry 和 WeBASE 各自的编译器均应使用 `0.6.10`。

## 权限

Owner 负责管理管理员和转移 Owner；管理员负责创建存证。两种角色独立，查询接口对任意调用地址开放。

| 接口 | 权限 | 行为 |
| --- | --- | --- |
| `setAdmin(address account, bool enabled)` | Owner | `true` 授予管理员权限，`false` 撤销权限；地址不能为零 |
| `transferOwnership(address newOwner)` | Owner | 立即转移 Owner；新地址不能为零或当前 Owner |
| 六个 `create…Evidence` | 管理员 | 创建存证 |
| 所有查询接口 | 任意地址 | 读取记录、权限状态或输入边界 |

构造函数将 `initialOwner` 设为 Owner，管理员名单初始为空。部署者不会因签署部署交易而自动获得权限。Owner 要创建存证，也需要调用 `setAdmin` 授权自己的地址。

Owner 转移在一次调用中生效。管理员名单保持原值，原 Owner 已有的管理员权限保留，新 Owner 不会自动获得管理员权限。

## 创建逻辑

业务系统完成资料填写、附件上传和审核后，管理员调用对应类别的创建接口，一次提交三个结构体：

1. `EvidenceInput`：所有类别共用的资料。
2. 对应类别的 `ProjectInfo`：项目或对象信息。
3. 对应类别的 `CoreData`：数量、方法、日期或声明等核心信息。

合约检查调用权限、字段约束和编号唯一性，保存公共资料及类别资料，追加编号索引，并触发 `EvidenceCreated` 事件。成功返回 `true`；检查失败时整笔交易回滚，不保留部分记录。

记录创建后不可修改或删除。`evidenceNo` 在同一个合约实例的六类存证之间唯一，按完整字符串的字节值比较，不自动处理大小写、空格或 Unicode 规范化。

合约自动记录以下字段，调用方无需传入：

| 字段 | 值 |
| --- | --- |
| `category` | 创建接口对应的类别 |
| `creator` | 实际调用管理员的 `msg.sender` |
| `createTime` | `block.timestamp / 1000`，适配 FISCO BCOS 2.11 的毫秒时间戳，保存为 Unix 秒 |

`holderAddress` 是存证持有人的地址；`evidenceSubject` 是存证主体的实名资料；`author` 是业务系统登录发布者的实名资料。它们由管理员提交，合约不验证这些身份与链地址之间的关联关系。

## 类别与接口

| 枚举值 | 类别 | 创建接口 | 查询接口 |
| --- | --- | --- | --- |
| `0 Resource` | 碳汇资源 | `createResourceEvidence` | `getResourceEvidence` |
| `1 Reduction` | 碳减排量 | `createReductionEvidence` | `getReductionEvidence` |
| `2 Footprint` | 碳足迹 | `createFootprintEvidence` | `getFootprintEvidence` |
| `3 TradeOffset` | 碳交易与抵消 | `createTradeOffsetEvidence` | `getTradeOffsetEvidence` |
| `4 Asset` | 碳资产 | `createAssetEvidence` | `getAssetEvidence` |
| `5 Technology` | 碳汇技术 | `createTechnologyEvidence` | `getTechnologyEvidence` |

每个创建接口的参数为 `(EvidenceInput input, 对应ProjectInfo project, 对应CoreData core)`。每个类别查询接口接收 `string evidenceNo`，返回 `(EvidenceCommon common, 对应ProjectInfo project, 对应CoreData core)`。

类别查询要求编号存在且类别匹配。可先调用 `getEvidenceCommon` 获取类别，再调用对应查询接口。

## 数据结构

合约定义 19 个结构体：公共输入、公共记录、五个公共子结构体，以及六类各自的项目和核心数据结构体。以下表格按源码字段顺序排列。

### 公共输入与记录

| 结构体 | 字段顺序 |
| --- | --- |
| `EvidenceInput` | `holderAddress`, `evidenceNo`, `evidenceName`, `certificateInfo`, `evidenceSubject`, `author`, `orgInfo`, `purpose`, `otherPurpose`, `auditInstitution`, `verificationSummary`, `remark`, `fileList` |
| `EvidenceCommon` | `data`, `category`, `creator`, `createTime` |

`EvidenceInput.holderAddress` 为 `address`，`purpose` 为 `string[]`，`fileList` 为 `FileInfo[]`；`certificateInfo`、`evidenceSubject`、`author`、`orgInfo` 分别使用对应子结构体，其余字段为 `string`。

`EvidenceCommon.data` 保存完整的 `EvidenceInput`，`category` 为 `EvidenceCategory`，`creator` 为 `address`，`createTime` 为 `uint256`。

### 公共子结构体

| 结构体 | 字段顺序 |
| --- | --- |
| `CertificateInfo` | `issuer`, `digitalId`, `trustedTs` |
| `EvidenceSubjectInfo` | `subjectType`, `subjectName`, `subjectNo`, `legalPerson` |
| `AuthorInfo` | `realId`, `realType`, `realName`, `realNo` |
| `OrganizationInfo` | `orgName`, `orgType`, `creditCode`, `legalPerson`, `contactPerson`, `contactPhone`, `contactEmail`, `registeredAddress` |
| `FileInfo` | `fileType`, `fileHash`, `fileName`, `fileSize` |

`trustedTs` 和 `fileSize` 为 `uint256`，其余子结构体字段均为 `string`。

- `CertificateInfo`：签发机构、证书业务标识、业务系统提供的 Unix 秒时间戳。
- `EvidenceSubjectInfo`：存证主体类型、名称、主体号码和法定代表人。
- `AuthorInfo`：登录发布者的实名会员编号、实名类型、实名名称和实名号码。
- `OrganizationInfo`：申请机构名称、类型、信用代码、负责人、联系人、电话、邮箱和注册地址。

`evidenceSubject.legalPerson` 和 `orgInfo.legalPerson` 分别描述存证主体与申请机构的代表人。个人主体的 `evidenceSubject.legalPerson` 可为空，申请机构的 `orgInfo.legalPerson` 必填。

实名、联系方式、账户及交易对手信息随存证按提交的明文字符串保存，可通过查询接口读取。

### 类别专属结构体

| 类别 | 项目结构体及字段顺序 | 核心数据结构体及字段顺序 |
| --- | --- | --- |
| 资源 | `ResourceProjectInfo`：`projectName`, `resourceType`, `resourceSubType`, `projectAddr`, `recordNo`, `projectArea`, `projectPeriod` | `ResourceCoreData`：`applyCarbonSinkAmount`, `detectPeriod`, `methodology` |
| 减排量 | `ReductionProjectInfo`：`reduceType`, `projectName`, `projectAddr`, `recordNo`, `projectScale`, `projectPeriod`, `techRoute` | `ReductionCoreData`：`applyReduceAmount`, `detectPeriod`, `methodology` |
| 足迹 | `FootprintProjectInfo`：`footprintType`, `objectName`, `boundaryDesc`, `baseYearUnit`, `applyStandard`, `collectPeriod` | `FootprintCoreData`：`applyEmissionAmount`, `calculatePeriod`, `emissionStandard` |
| 交易与抵消 | `TradeOffsetProjectInfo`：`subType`, `creditSource`, `sourceCertNo`, `registerPlatform`, `cancelTradeNo`, `counterParty`, `tradePrice`, `carbonNeutralScope` | `TradeOffsetCoreData`：`certAmount`, `tradeOffsetDate`, `repeatPreventDeclare` |
| 资产 | `AssetProjectInfo`：`assetType`, `registerPlatform`, `accountId`, `assetRegisterNo`, `sourceProjectName`, `holdStartDate` | `AssetCoreData`：`holdAmount`, `sourceCompliant`, `unencumbered`, `pledgePurposeApplicable`, `pledgePurpose`, `pledgeAgreementApplicable` |
| 技术 | `TechnologyProjectInfo`：`techEvidenceType`, `techName`, `techField`, `developOrg`, `techMaturity`, `ipNo`, `applicationCase` | `TechnologyCoreData`：`coreCarbonIndex`, `validPeriod`, `evaluateStandard` |

`repeatPreventDeclare`、`sourceCompliant`、`unencumbered`、`pledgePurposeApplicable`、`pledgeAgreementApplicable` 为 `bool`，其余类别专属字段均为 `string`。

## 字段约束

`holderAddress` 必须为非零地址。除下表列出的可选文本外，所有文本字段必须非空。非空仅指字节长度大于零，合约不检查文本是否只包含空白。

| 可选字段 | 条件 |
| --- | --- |
| `evidenceSubject.legalPerson` | 可为空 |
| `otherPurpose`, `remark` | 可为空 |
| `TradeOffsetProjectInfo.tradePrice`, `TradeOffsetProjectInfo.carbonNeutralScope` | 可为空 |
| `AssetCoreData.pledgePurpose` | `pledgePurposeApplicable` 为 `true` 时必须非空 |
| `TechnologyProjectInfo.ipNo`, `TechnologyProjectInfo.applicationCase` | 可为空 |

资产与交易声明的约束：

- `TradeOffsetCoreData.repeatPreventDeclare` 必须为 `true`。
- `AssetCoreData.sourceCompliant`、`AssetCoreData.unencumbered` 必须为 `true`。
- `AssetCoreData.pledgeAgreementApplicable` 为 `true` 时，`fileList` 中至少有一个文件的 `fileType` 精确等于 `pledgeAgreement`。

长度按 UTF-8 字节数检查。常见汉字通常占三字节。

| 字段或集合 | 限制 |
| --- | --- |
| `evidenceNo`, `certificateInfo.digitalId`, `author.realId`, `author.realNo`, `evidenceSubject.subjectNo`, `orgInfo.creditCode`, `orgInfo.contactPhone`, `AssetProjectInfo.accountId` | 不超过 128 字节 |
| 普通文本及每个 `purpose` 项 | 不超过 2048 字节 |
| `verificationSummary`, `otherPurpose`, `remark`, `boundaryDesc`, `carbonNeutralScope`, `pledgePurpose`, `applicationCase` | 不超过 6000 字节 |
| 每个文件的 `fileType`, `fileHash`, `fileName` | 各不超过 256 字节 |
| `purpose` | 1 至 8 项，每项非空 |
| `fileList` | 1 至 32 项 |
| `FileInfo.fileSize` | 大于零 |
| 分页 `limit` | 1 至 50 |

上述边界可通过 `MAX_ID_BYTES()`、`MAX_TEXT_BYTES()`、`MAX_LONG_TEXT_BYTES()`、`MAX_PURPOSES()`、`MAX_FILES()` 和 `MAX_PAGE_SIZE()` 查询。文件的 256 字节上限直接定义在校验逻辑中。

### 文件信息

每个附件使用 `FileInfo` 保存：

| 字段 | 含义 |
| --- | --- |
| `fileType` | 材料类别的英文编码，例如 `verificationReport`、`authorizationLetter`、`pledgeAgreement` |
| `fileHash` | 文件服务根据实际文件内容计算的哈希 |
| `fileName` | 文件服务最终保存的文件名 |
| `fileSize` | KB，由业务系统按 `ceil(文件字节数 / 1024)` 向上取整 |

文件原文保存在文件服务。合约检查文件元数据的非空、长度和大小约束，不读取原文、不计算文件哈希，也不限定哈希算法或编码格式。

除质押协议的条件校验外，各类别材料是否齐全、文件类型与内容是否对应，由业务系统审核。

`fileType` 使用下表的英文编码，区分大小写，中文名称用于界面显示。该字段表示材料类别，文件格式由文件服务管理。

| 英文编码 | 中文名称 |
| --- | --- |
| `qualificationProof` | 主体/机构资质证明 |
| `authorizationLetter` | 授权委托书 |
| `verificationReport` | 核查报告/审定意见 |
| `monitoringReport` | 监测数据报告 |
| `remoteOrSiteMedia` | 遥感/现场影像 |
| `governmentApprovalOrEia` | 政府批复/环评文件 |
| `supportingMaterial` | 其他支撑材料 |
| `landOrSeaOwnershipProof` | 土地/海域权属证明 |
| `measurementBasis` | 碳汇计量依据文件 |
| `projectApproval` | 项目批复/核准文件 |
| `emissionSourceList` | 排放源清单 |
| `footprintReport` | 碳足迹核算报告 |
| `calculationBasis` | 减排量/碳排放量核算依据文件 |
| `tradeOrRetirementProof` | 注销凭证/交易流水 |
| `assetHoldingProof` | 资产持有凭证 |
| `pledgeAgreement` | 质押协议 |
| `technologyEvaluationReport` | 技术评估报告 |
| `technologyEvaluationBasis` | 技术评估依据文件 |

合约的 `fileType` 类型为 `string`，检查非空和长度，但不执行上述编码的白名单校验；质押协议适用时必须匹配 `pledgeAgreement`。

授权委托书通过 `fileList` 接收，`fileType` 填写 `authorizationLetter`，并一同提交文件哈希、文件名和大小。经办人是法定代表人时可不提交该文件；经办人不是法定代表人时，业务系统应要求上传并将文件元数据传入合约。合约保存提交的文件列表，不根据经办人身份强制检查授权委托书。

### 数量、日期与声明

数量、金额、日期和区间使用字符串保存，业务系统统一格式及单位：

| 字段 | 输入约定 |
| --- | --- |
| `projectArea` | 公顷 |
| `projectScale` | 万吨，按业务项目口径填写 |
| 碳汇量、减排量、排放量、交易抵消量、资产持有量 | 吨 CO2e |
| `tradePrice` | 元/吨 |
| `coreCarbonIndex` | 吨 CO2e/年 |
| `validPeriod` | 年限 |
| 年份区间 | 例如 `2026/2036` |
| 日期及日期区间 | 例如 `2026-10-14`、`2026-01-01/2026-12-31` |

合约不解析上述字符串，不校验数值、日期先后、单位、类型字典或用途重复项。`carbonNeutralScope` 对应子类型的业务必填规则由后台处理。

`trustedTs` 原值保存，不校验是否大于零、时间先后或可信时间机构签名。声明布尔值是记录的一部分，合约不验证外部碳信用、质押或注销状态。`sourceCertNo` 作为业务引用保存，不检查它是否对应链上已有存证。

## 查询与分页

| 接口 | 返回及规则 |
| --- | --- |
| `getEvidenceCommon(string evidenceNo)` | 返回完整公共记录；编号不存在时回滚 |
| 六个 `get…Evidence(string evidenceNo)` | 返回公共记录、对应项目及核心数据；编号不存在或类别不匹配时回滚 |
| `evidenceNoExists(string evidenceNo)` | 返回编号是否存在 |
| `getEvidenceCount()` | 返回存证总数 |
| `getEvidenceNumbers(uint256 offset, uint256 limit)` | 按创建顺序返回编号数组；`offset` 从零开始，尾页返回剩余项，越界返回空数组；非法 `limit` 会回滚 |
| `owner()` | 返回当前 Owner |
| `admins(address account)` | 返回该地址是否为管理员 |

编号分页不按持有人或类别筛选。业务系统可通过 `EvidenceCreated` 事件建立检索索引，再按编号读取完整记录。

## 事件

| 事件 | 触发时机及字段 |
| --- | --- |
| `OwnershipTransferred(previousOwner, newOwner)` | 部署和转移 Owner 时触发；两个地址均为索引字段，部署时 `previousOwner` 为零地址、`newOwner` 为 `initialOwner` |
| `AdminUpdated(account, enabled, operator)` | 设置或撤销管理员时触发；`account`、`operator` 为索引字段 |
| `EvidenceCreated(evidenceKey, holderAddress, category, evidenceNo, creator, createTime)` | 创建存证时触发；前三项为索引字段 |

`evidenceKey` 为 `keccak256(bytes(evidenceNo))`，用于日志检索；完整编号仍保存在事件和存证记录中。

## 调用示例

部署时为构造参数 `initialOwner` 填入管理钱包地址，例如 `0x1111111111111111111111111111111111111111`。部署完成后，由该 Owner 钱包签名调用 `setAdmin(管理员地址, true)`。该管理员随后调用对应类别的创建接口。

以下 JSON 展示 `createResourceEvidence(input, project, core)` 三个参数的 tuple 字段顺序，所有资料均为虚构示例：

```json
[
  [
    "0x1111111111111111111111111111111111111111",
    "RESOURCE-2026-000001",
    "示例林业碳汇资源存证",
    ["示例签发机构", "CERT-2026-000001", 1791936000],
    ["企业", "示例持有主体", "SUBJECT-TEST-000001", "示例主体法人"],
    ["MEMBER-TEST-000001", "个人", "示例发布者", "IDENTITY-TEST-000001"],
    [
      "示例申请机构", "企业", "CREDIT-TEST-000001", "示例机构负责人",
      "示例联系人 / 项目经办", "00000000000", "test@example.invalid", "示例省示例市测试路 1 号"
    ],
    ["ESG/绿色金融披露"],
    "",
    "示例核查机构",
    "经业务审核的核查摘要",
    "",
    [
      [
        "verificationReport",
        "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
        "material-2026-000001.pdf",
        12
      ]
    ]
  ],
  [
    "示例林业项目", "林业碳汇", "造林碳汇", "示例省/示例市/示例县",
    "PROJECT-2026-000001", "100.50", "2026/2036"
  ],
  ["1200.50", "2026-01-01/2026-12-31", "示例方法学"]
]
```

示例哈希为占位内容，实际调用需传入真实文件哈希和对应材料。WeBASE 或 SDK 按编译产物的 ABI 编码 tuple。

创建成功后调用 `getResourceEvidence("RESOURCE-2026-000001")`，返回公共记录、资源项目及核心数据。公共记录的 tuple 形状为 `[data, category, creator, createTime]`。

## 回滚信息

合约使用 `require` 的字符串描述失败原因：

| 信息 | 原因 |
| --- | --- |
| `owner only` | 调用方不是 Owner |
| `admin only` | 调用方不是管理员 |
| `admin zero`, `owner zero`, `holder zero` | 对应地址为零 |
| `same owner` | 目标 Owner 与当前 Owner 相同 |
| `number exists` | 存证编号已存在 |
| `not found` | 存证编号不存在 |
| `wrong category` | 编号对应类别与查询接口不匹配 |
| `required text`, `text too long` | 必填文本为空或文本超长 |
| `purpose count`, `file count` | 用途或文件数量超出允许范围 |
| `file size zero` | 文件大小为零 |
| `declaration required` | 必须接受的声明为 `false` |
| `pledge purpose required` | 质押用途适用，但用途文本为空 |
| `pledge agreement required` | 质押协议适用，但文件列表中没有 `pledgeAgreement` |
| `page limit` | 分页数量不在允许范围内 |
