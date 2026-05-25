import SwiftUI

struct LimitHygieneCard: View {
    @State private var diagnostics: ClaudeCodeDiagnostics?
    @State private var copiedTemplate: Bool = false
    @State private var expandedChecklist: Bool = false

    var body: some View {
        SettingsSectionCard(
            title: "diagnostics.title".localized,
            subtitle: "Read-only diagnostics and hygiene checklist"
        ) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.medium) {
                // Diagnostics
                if let diag = diagnostics {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                        // MCP servers
                        HStack {
                            Text("diagnostics.mcp_servers".localized)
                                .font(DesignTokens.Typography.body)
                            Spacer()
                            Text("\(diag.mcpServerCount)")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundColor(diag.mcpWarning ? .orange : .secondary)
                        }
                        if diag.mcpWarning {
                            Text("diagnostics.mcp_warning".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.orange)
                        }

                        // CLAUDE.md
                        HStack {
                            Text("diagnostics.claude_md".localized)
                                .font(DesignTokens.Typography.body)
                            Spacer()
                            if diag.hasClaudeMd || diag.hasGlobalClaudeMd {
                                Text("Present")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(diag.claudeMdWarning ? .orange : .adaptiveGreen)
                            } else {
                                Text("Not found")
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if diag.claudeMdWarning {
                            Text("diagnostics.claude_md_warning".localized)
                                .font(DesignTokens.Typography.caption)
                                .foregroundColor(.orange)
                        }

                        // Settings entries
                        HStack {
                            Text("diagnostics.settings_entries".localized)
                                .font(DesignTokens.Typography.body)
                            Spacer()
                            Text("\(diag.settingsEntriesCount)")
                                .font(DesignTokens.Typography.bodyMedium)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Button("Load Diagnostics") {
                        diagnostics = ClaudeCodeOptimizationService.shared.runDiagnostics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // Checklist
                DisclosureGroup(
                    isExpanded: $expandedChecklist,
                    content: {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                            ForEach(ClaudeCodeOptimizationService.shared.checklistItems()) { item in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.command)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.accentColor)
                                        Spacer()
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(item.command, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    Text(item.description)
                                        .font(DesignTokens.Typography.caption)
                                        .foregroundColor(.secondary)
                                    Text(item.whenToUse)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .italic()
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.small)
                    },
                    label: {
                        Text("diagnostics.checklist_title".localized)
                            .font(DesignTokens.Typography.body)
                            .foregroundColor(.primary)
                    }
                )

                Divider()

                // Session handoff template
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                    HStack {
                        Text("diagnostics.handoff_template".localized)
                            .font(DesignTokens.Typography.body)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(
                                ClaudeCodeOptimizationService.shared.sessionHandoffTemplate(),
                                forType: .string
                            )
                            copiedTemplate = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedTemplate = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedTemplate ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10))
                                Text(copiedTemplate ? "guide.copied".localized : "diagnostics.copy_template".localized)
                                    .font(DesignTokens.Typography.caption)
                            }
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }
        }
        .onAppear {
            diagnostics = ClaudeCodeOptimizationService.shared.runDiagnostics()
        }
    }
}