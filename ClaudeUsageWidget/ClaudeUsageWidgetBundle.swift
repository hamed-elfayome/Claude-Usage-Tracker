import SwiftUI
import WidgetKit

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionUsageWidget()
        UsageOverviewWidget()
    }
}
