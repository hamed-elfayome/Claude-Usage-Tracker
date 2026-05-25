import Foundation

final class LimitOptimizationTipService {
    static let shared = LimitOptimizationTipService()

    private init() {}

    func recommendedTips(
        sessionPercentage: Double,
        isPeakHours: Bool,
        hasClaudeCodeCredentials: Bool,
        hasMCPServers: Bool,
        noPlanConfigured: Bool,
        repeatedNearLimit: Bool,
        categories: [TipCategory]? = nil
    ) -> [LimitOptimizationTip] {
        let catalog = categories.flatMap { cats in
            cats.flatMap { LimitOptimizationTip.tips(for: $0) }
        } ?? LimitOptimizationTip.catalog

        var scored = catalog.map { tip -> (tip: LimitOptimizationTip, score: Int) in
            var score = 0

            switch tip.category {
            case .claudeAI:
                if sessionPercentage > 80 { score += 3 }
                if isPeakHours && tip.id == "claude-ai-off-peak" { score += 4 }
                if tip.id == "claude-ai-session-overlap" && noPlanConfigured { score += 2 }

            case .claudeCode:
                if hasClaudeCodeCredentials {
                    score += 2
                    if hasMCPServers && tip.id == "claude-code-disconnect-mcp" { score += 3 }
                    if hasMCPServers && tip.id == "claude-code-prefer-cli" { score += 2 }
                }
                if sessionPercentage > 70 {
                    if tip.id == "claude-code-clear" { score += 3 }
                    if tip.id == "claude-code-compact-rewind" { score += 2 }
                }

            case .claudeCowork:
                break
            }

            if sessionPercentage > 90 && (tip.id == "claude-ai-edit-instead-followup" || tip.id == "claude-ai-batch-requests") {
                score += 2
            }

            if repeatedNearLimit {
                if tip.actionStyle == .actionable || tip.actionStyle == .checklist {
                    score += 2
                }
            }

            if tip.riskLevel == .high {
                score -= 2
            }

            return (tip, max(0, score))
        }

        scored.sort { $0.score > $1.score }
        return scored.prefix(5).map(\.tip)
    }

    func rotatingTip(
        sessionPercentage: Double,
        isPeakHours: Bool,
        lastTipId: String?
    ) -> LimitOptimizationTip? {
        let tips = recommendedTips(
            sessionPercentage: sessionPercentage,
            isPeakHours: isPeakHours,
            hasClaudeCodeCredentials: false,
            hasMCPServers: false,
            noPlanConfigured: false,
            repeatedNearLimit: false
        )

        let actionable = tips.filter { $0.actionStyle == .actionable || $0.actionStyle == .checklist }
        let candidates = actionable.filter { $0.id != lastTipId }
        return candidates.first
    }

    func tipsForCategory(_ category: TipCategory) -> [LimitOptimizationTip] {
        LimitOptimizationTip.tips(for: category)
    }

    func actionableTipsForCategory(_ category: TipCategory) -> [LimitOptimizationTip] {
        LimitOptimizationTip.actionableTips(for: category)
    }

    func allTips() -> [LimitOptimizationTip] {
        LimitOptimizationTip.catalog
    }
}