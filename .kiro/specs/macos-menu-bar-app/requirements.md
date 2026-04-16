# Requirements Document

## Introduction

iTip 是一个 macOS 菜单栏应用，用于记录用户最近使用的应用程序，并支持从菜单栏一键切换到目标应用。该应用在菜单栏常驻运行，自动追踪应用激活事件，按最近使用时间和使用频率排序，展示前 10 个最常用的应用，并支持点击直接激活或启动目标应用。使用历史在应用重启后持久保留。

## Glossary

- **iTip**: macOS 菜单栏应用，本项目的主体系统
- **Menu_Bar_Item**: macOS 系统菜单栏中 iTip 的常驻图标入口
- **Usage_Store**: 负责将应用使用记录持久化到本地磁盘的存储层
- **Usage_Record**: 单条应用使用记录，包含 bundle identifier、显示名称、最后激活时间和激活次数
- **Ranking_Engine**: 根据最近激活时间和激活次数对应用列表进行排序的排名服务
- **Activation_Monitor**: 监听 macOS 应用激活事件并更新使用记录的事件捕获组件
- **App_Launcher**: 负责激活或启动目标应用的组件
- **Menu_Presenter**: 将排序后的应用列表渲染为菜单栏下拉菜单的 UI 组件
- **Bundle_Identifier**: macOS 应用的唯一标识符（如 `com.apple.Safari`）

## Requirements

### Requirement 1: 菜单栏常驻入口

**User Story:** 作为 macOS 用户，我希望 iTip 在菜单栏中显示一个常驻图标，以便我随时访问最近使用的应用列表。

#### Acceptance Criteria

1. WHEN iTip launches, THE Menu_Bar_Item SHALL appear in the macOS system menu bar
2. WHILE iTip is running, THE Menu_Bar_Item SHALL remain visible in the menu bar
3. THE iTip SHALL set its activation policy to accessory mode so that no Dock icon is displayed
4. WHEN the user clicks the Menu_Bar_Item, THE Menu_Presenter SHALL display a dropdown menu containing the recent apps list

### Requirement 2: 应用激活事件捕获

**User Story:** 作为 macOS 用户，我希望 iTip 自动记录我切换应用的行为，以便无需手动操作即可追踪使用习惯。

#### Acceptance Criteria

1. WHEN a macOS application is activated by the user, THE Activation_Monitor SHALL detect the activation event via NSWorkspace notification
2. WHEN an activation event is detected, THE Activation_Monitor SHALL extract the Bundle_Identifier and display name from the activated application
3. WHEN an activation event is detected for an application already in the Usage_Store, THE Activation_Monitor SHALL increment the activation count by 1 and update the last activation timestamp
4. WHEN an activation event is detected for an application not yet in the Usage_Store, THE Activation_Monitor SHALL create a new Usage_Record with an activation count of 1 and the current timestamp
5. THE Activation_Monitor SHALL exclude iTip itself from the recorded activation events

### Requirement 3: 使用记录持久化存储

**User Story:** 作为 macOS 用户，我希望应用使用历史在 iTip 重启后仍然保留，以便不会丢失使用数据。

#### Acceptance Criteria

1. THE Usage_Store SHALL persist all Usage_Record entries to a local JSON file on disk
2. WHEN the Usage_Store saves records, THE Usage_Store SHALL write the data atomically to prevent corruption from partial writes
3. WHEN iTip launches, THE Usage_Store SHALL load previously saved Usage_Record entries from the local JSON file
4. IF the storage file does not exist on launch, THEN THE Usage_Store SHALL return an empty record list without error
5. IF the storage file contains corrupted data, THEN THE Usage_Store SHALL return an empty record list and log the error

### Requirement 4: 应用排名服务

**User Story:** 作为 macOS 用户，我希望最近使用的应用排在列表前面，以便快速找到我需要切换的应用。

#### Acceptance Criteria

1. THE Ranking_Engine SHALL sort Usage_Record entries primarily by last activation timestamp in descending order
2. WHEN two Usage_Record entries have the same last activation timestamp, THE Ranking_Engine SHALL use activation count in descending order as the secondary sort key
3. THE Ranking_Engine SHALL produce a deterministic sort order for any given set of Usage_Record entries
4. THE Ranking_Engine SHALL limit the output list to the top 10 entries

### Requirement 5: 菜单列表展示

**User Story:** 作为 macOS 用户，我希望在菜单栏下拉菜单中看到最近使用的应用列表，以便快速选择要切换的应用。

#### Acceptance Criteria

1. WHEN the user opens the dropdown menu, THE Menu_Presenter SHALL display up to 10 recently used applications in ranked order
2. THE Menu_Presenter SHALL display each application entry with its app icon and display name
3. WHEN no Usage_Record entries exist, THE Menu_Presenter SHALL display an empty state message indicating no recent apps are available
4. WHEN the dropdown menu is opened, THE Menu_Presenter SHALL read the latest data from the Usage_Store and re-rank the list

### Requirement 6: 一键应用激活

**User Story:** 作为 macOS 用户，我希望点击菜单中的应用条目即可切换到该应用，以便快速完成应用切换。

#### Acceptance Criteria

1. WHEN the user clicks an application entry in the dropdown menu, THE App_Launcher SHALL activate the corresponding application and bring it to the foreground
2. WHEN the target application is not currently running, THE App_Launcher SHALL launch the application first and then activate it
3. IF the target application cannot be found or launched, THEN THE App_Launcher SHALL display an error message to the user

### Requirement 7: 已移除应用清理

**User Story:** 作为 macOS 用户，我希望已卸载或不可用的应用不再出现在列表中，以便列表保持整洁和可用。

#### Acceptance Criteria

1. WHEN the Menu_Presenter builds the dropdown menu, THE Menu_Presenter SHALL omit Usage_Record entries whose Bundle_Identifier cannot be resolved to an installed application
2. WHEN a Usage_Record entry is omitted due to an unresolvable Bundle_Identifier, THE Usage_Store SHALL remove the corresponding record from persistent storage

### Requirement 8: 权限与错误处理

**User Story:** 作为 macOS 用户，我希望在权限不足或发生错误时看到清晰的提示信息，以便了解问题并采取措施。

#### Acceptance Criteria

1. IF macOS prevents iTip from monitoring application activation events, THEN THE iTip SHALL display a user-facing message explaining the permission limitation
2. IF macOS prevents iTip from activating a target application, THEN THE iTip SHALL display a user-facing message describing the failure reason
3. IF an unexpected error occurs during Usage_Store read or write operations, THEN THE Usage_Store SHALL handle the error gracefully without crashing the application

### Requirement 9: Usage_Record 序列化与反序列化

**User Story:** 作为开发者，我希望 Usage_Record 的序列化和反序列化是正确且可逆的，以便数据在存储和读取过程中不会丢失或损坏。

#### Acceptance Criteria

1. THE Usage_Store SHALL serialize Usage_Record entries to JSON format using Swift Codable protocol
2. THE Usage_Store SHALL deserialize JSON data back into Usage_Record entries using Swift Codable protocol
3. FOR ALL valid Usage_Record lists, serializing then deserializing SHALL produce an equivalent list (round-trip property)
