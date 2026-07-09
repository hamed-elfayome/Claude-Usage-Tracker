//
//  ConsoleAuthWebView.swift
//  Claude Usage
//
//  Created by Claude Code on 2026-03-01.
//

import SwiftUI
import WebKit

// MARK: - Cookie Result

struct ConsoleCookieResult {
    let sessionKey: String
    let expiryDate: Date?
}

// MARK: - WKWebView Wrapper

struct ConsoleAuthWebView: NSViewRepresentable {
    let loginURL: URL
    let cookieDomain: String
    let onCookieFound: (ConsoleCookieResult) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.parentWebView = webView
        context.coordinator.startObservingCookies(for: config.websiteDataStore)

        // Clear auth cookies to prevent auto-login with stale session.
        // Google cookies are preserved so SSO popup works.
        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            let group = DispatchGroup()
            for cookie in cookies where cookie.domain.contains("claude") || cookie.domain.contains("anthropic") {
                group.enter()
                cookieStore.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                webView.load(URLRequest(url: self.loginURL))
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(cookieDomain: cookieDomain, onCookieFound: onCookieFound)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        let cookieDomain: String
        let onCookieFound: (ConsoleCookieResult) -> Void
        private var foundCookie = false
        weak var parentWebView: WKWebView?
        private var popupWindow: NSWindow?
        private var popupWebView: WKWebView?
        private var pollTimer: Timer?

        init(cookieDomain: String, onCookieFound: @escaping (ConsoleCookieResult) -> Void) {
            self.cookieDomain = cookieDomain
            self.onCookieFound = onCookieFound
        }

        deinit {
            pollTimer?.invalidate()
        }

        func startObservingCookies(for dataStore: WKWebsiteDataStore) {
            dataStore.httpCookieStore.add(self)

            // WKHTTPCookieStoreObserver doesn't fire for cookies set via
            // Set-Cookie by the network process on macOS 26+, and claude.ai is
            // an SPA so didFinish never fires after login — poll as a fallback.
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if self.foundCookie {
                    self.pollTimer?.invalidate()
                    self.pollTimer = nil
                    return
                }
                self.searchForSessionCookie(in: dataStore.httpCookieStore)
            }
        }

        // WKHTTPCookieStoreObserver — fires whenever any cookie changes
        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            guard !foundCookie else { return }
            searchForSessionCookie(in: cookieStore)
        }

        private func searchForSessionCookie(in cookieStore: WKHTTPCookieStore) {
            cookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.foundCookie else { return }
                for cookie in cookies {
                    if cookie.name == "sessionKey" && cookie.domain.contains(self.cookieDomain) {
                        self.foundCookie = true
                        let result = ConsoleCookieResult(
                            sessionKey: cookie.value,
                            expiryDate: cookie.expiresDate
                        )
                        DispatchQueue.main.async {
                            self.pollTimer?.invalidate()
                            self.pollTimer = nil
                            self.onCookieFound(result)
                        }
                        return
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !foundCookie else { return }
            checkForSessionCookie(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            // Create a real popup WKWebView using the provided configuration
            // (preserves window.opener linkage and shared cookies for Google SSO)
            let popup = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 500, height: 600),
                configuration: configuration
            )
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let panel = NSPanel(
                contentRect: CGRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.contentView = popup
            panel.title = "Sign In"
            panel.center()
            panel.makeKeyAndOrderFront(nil)

            self.popupWindow = panel
            self.popupWebView = popup

            return popup
        }

        // Handle window.close() from Google SSO popup after auth completes
        func webViewDidClose(_ webView: WKWebView) {
            if webView === popupWebView {
                popupWindow?.close()
                popupWindow = nil
                popupWebView = nil
            }
        }

        private func checkForSessionCookie(in webView: WKWebView) {
            searchForSessionCookie(in: webView.configuration.websiteDataStore.httpCookieStore)
        }
    }
}

// MARK: - Auth Sheet

struct ConsoleAuthSheet: View {
    let title: String
    let loginURL: URL
    let cookieDomain: String
    let onSuccess: (ConsoleCookieResult) -> Void
    let onCancel: () -> Void

    @State private var isLoading = true
    @State private var hasError = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // WebView
            ConsoleAuthWebView(loginURL: loginURL, cookieDomain: cookieDomain) { result in
                onSuccess(result)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 680)
    }
}
