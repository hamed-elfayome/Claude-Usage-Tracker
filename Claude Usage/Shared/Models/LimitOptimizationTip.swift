import Foundation

enum TipCategory: String, Codable, CaseIterable {
    case claudeAI = "claude_ai"
    case claudeCode = "claude_code"
    case claudeCowork = "claude_cowork"
}

enum TipActionStyle: String, Codable {
    case actionable
    case informational
    case checklist
}

enum TipRiskLevel: String, Codable {
    case safe
    case medium
    case high
}

struct LimitOptimizationTip: Identifiable, Codable, Equatable {
    let id: String
    let category: TipCategory
    let titleKey: String
    let detailKey: String
    let actionStyle: TipActionStyle
    let riskLevel: TipRiskLevel
    let actionData: TipActionData?
    let sortOrder: Int

    struct TipActionData: Codable, Equatable {
        let type: ActionType
        let value: String?

        enum ActionType: String, Codable {
            case copy
            case openURL
            case deepLink
            case none
        }
    }

    static func == (lhs: LimitOptimizationTip, rhs: LimitOptimizationTip) -> Bool {
        lhs.id == rhs.id
    }
}

extension LimitOptimizationTip {
    static let catalog: [LimitOptimizationTip] = [
        // Claude.ai tips (9)
        LimitOptimizationTip(
            id: "claude-ai-edit-instead-followup",
            category: .claudeAI,
            titleKey: "tip.claudeai.edit_instead_followup.title",
            detailKey: "tip.claudeai.edit_instead_followup.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 1
        ),
        LimitOptimizationTip(
            id: "claude-ai-batch-requests",
            category: .claudeAI,
            titleKey: "tip.claudeai.batch_requests.title",
            detailKey: "tip.claudeai.batch_requests.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 2
        ),
        LimitOptimizationTip(
            id: "claude-ai-fresh-chat",
            category: .claudeAI,
            titleKey: "tip.claudeai.fresh_chat.title",
            detailKey: "tip.claudeai.fresh_chat.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 3
        ),
        LimitOptimizationTip(
            id: "claude-ai-model-selection",
            category: .claudeAI,
            titleKey: "tip.claudeai.model_selection.title",
            detailKey: "tip.claudeai.model_selection.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 4
        ),
        LimitOptimizationTip(
            id: "claude-ai-extended-thinking",
            category: .claudeAI,
            titleKey: "tip.claudeai.extended_thinking.title",
            detailKey: "tip.claudeai.extended_thinking.detail",
            actionStyle: .actionable,
            riskLevel: .safe,
            actionData: TipActionData(type: .none, value: nil),
            sortOrder: 5
        ),
        LimitOptimizationTip(
            id: "claude-ai-markdown-conversion",
            category: .claudeAI,
            titleKey: "tip.claudeai.markdown_conversion.title",
            detailKey: "tip.claudeai.markdown_conversion.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 6
        ),
        LimitOptimizationTip(
            id: "claude-ai-projects",
            category: .claudeAI,
            titleKey: "tip.claudeai.projects.title",
            detailKey: "tip.claudeai.projects.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 7
        ),
        LimitOptimizationTip(
            id: "claude-ai-session-overlap",
            category: .claudeAI,
            titleKey: "tip.claudeai.session_overlap.title",
            detailKey: "tip.claudeai.session_overlap.detail",
            actionStyle: .actionable,
            riskLevel: .medium,
            actionData: TipActionData(type: .deepLink, value: "claude://session-planning"),
            sortOrder: 8
        ),
        LimitOptimizationTip(
            id: "claude-ai-off-peak",
            category: .claudeAI,
            titleKey: "tip.claudeai.off_peak.title",
            detailKey: "tip.claudeai.off_peak.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 9
        ),

        // Claude Code tips (8)
        LimitOptimizationTip(
            id: "claude-code-context",
            category: .claudeCode,
            titleKey: "tip.claudecode.context.title",
            detailKey: "tip.claudecode.context.detail",
            actionStyle: .checklist,
            riskLevel: .safe,
            actionData: TipActionData(type: .copy, value: "/context"),
            sortOrder: 10
        ),
        LimitOptimizationTip(
            id: "claude-code-disconnect-mcp",
            category: .claudeCode,
            titleKey: "tip.claudecode.disconnect_mcp.title",
            detailKey: "tip.claudecode.disconnect_mcp.detail",
            actionStyle: .checklist,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 11
        ),
        LimitOptimizationTip(
            id: "claude-code-prefer-cli",
            category: .claudeCode,
            titleKey: "tip.claudecode.prefer_cli.title",
            detailKey: "tip.claudecode.prefer_cli.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 12
        ),
        LimitOptimizationTip(
            id: "claude-code-clear",
            category: .claudeCode,
            titleKey: "tip.claudecode.clear.title",
            detailKey: "tip.claudecode.clear.detail",
            actionStyle: .checklist,
            riskLevel: .safe,
            actionData: TipActionData(type: .copy, value: "/clear"),
            sortOrder: 13
        ),
        LimitOptimizationTip(
            id: "claude-code-compact-rewind",
            category: .claudeCode,
            titleKey: "tip.claudecode.compact_rewind.title",
            detailKey: "tip.claudecode.compact_rewind.detail",
            actionStyle: .checklist,
            riskLevel: .safe,
            actionData: TipActionData(type: .copy, value: "/compact"),
            sortOrder: 14
        ),
        LimitOptimizationTip(
            id: "claude-code-session-handoff",
            category: .claudeCode,
            titleKey: "tip.claudecode.session_handoff.title",
            detailKey: "tip.claudecode.session_handoff.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 15
        ),
        LimitOptimizationTip(
            id: "claude-code-subagents",
            category: .claudeCode,
            titleKey: "tip.claudecode.subagents.title",
            detailKey: "tip.claudecode.subagents.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 16
        ),
        LimitOptimizationTip(
            id: "claude-code-claude-md-hygiene",
            category: .claudeCode,
            titleKey: "tip.claudecode.claude_md_hygiene.title",
            detailKey: "tip.claudecode.claude_md_hygiene.detail",
            actionStyle: .checklist,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 17
        ),

        // Claude Cowork tips (4)
        LimitOptimizationTip(
            id: "claude-cowork-dedicated-folder",
            category: .claudeCowork,
            titleKey: "tip.claudecowork.dedicated_folder.title",
            detailKey: "tip.claudecowork.dedicated_folder.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 18
        ),
        LimitOptimizationTip(
            id: "claude-cowork-local-memory",
            category: .claudeCowork,
            titleKey: "tip.claudecowork.local_memory.title",
            detailKey: "tip.claudecowork.local_memory.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 19
        ),
        LimitOptimizationTip(
            id: "claude-cowork-research-split",
            category: .claudeCowork,
            titleKey: "tip.claudecowork.research_split.title",
            detailKey: "tip.claudecowork.research_split.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 20
        ),
        LimitOptimizationTip(
            id: "claude-cowork-skills",
            category: .claudeCowork,
            titleKey: "tip.claudecowork.skills.title",
            detailKey: "tip.claudecowork.skills.detail",
            actionStyle: .informational,
            riskLevel: .safe,
            actionData: nil,
            sortOrder: 21
        ),
    ]

    static func tips(for category: TipCategory) -> [LimitOptimizationTip] {
        catalog.filter { $0.category == category }.sorted { $0.sortOrder < $1.sortOrder }
    }

    static func actionableTips(for category: TipCategory) -> [LimitOptimizationTip] {
        tips(for: category).filter { $0.actionStyle == .actionable || $0.actionStyle == .checklist }
    }
}