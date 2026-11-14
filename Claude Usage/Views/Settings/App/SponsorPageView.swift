//
//  SponsorPageView.swift
//  Claude Usage
//
//  The page behind the sponsor placement, shown in the settings window's
//  content area like any other section.
//

import SwiftUI
import WebKit

struct SponsorPageView: View {
    let url: URL
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("sponsor.label".localized)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                Text(url.host ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("sponsor.open_in_browser".localized) {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            SponsorWebView(url: url, isLoading: $isLoading)
        }
    }
}

/// A plain browser view for a third-party page. It shares nothing with the
/// app: its data store is in-memory and separate from the one the Claude
/// sign-in views use, so the page can never see those cookies.
private struct SponsorWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoading: $isLoading)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        @Binding var isLoading: Bool
        var loadedURL: URL?

        init(isLoading: Binding<Bool>) {
            _isLoading = isLoading
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // https pages only; anything else (mailto, custom schemes) goes to the system.
            guard let target = navigationAction.request.url else { return decisionHandler(.cancel) }
            if target.scheme?.lowercased() == "https" || target.scheme == "about" {
                decisionHandler(.allow)
            } else {
                if target.scheme?.lowercased() == "mailto" { NSWorkspace.shared.open(target) }
                decisionHandler(.cancel)
            }
        }

        /// Links that ask for a new window open in the default browser.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = navigationAction.request.url, target.scheme?.lowercased() == "https" {
                NSWorkspace.shared.open(target)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isLoading = false
        }
    }
}
