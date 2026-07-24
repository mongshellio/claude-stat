import Foundation
import Network

/// Minimal localhost HTTP listener for the OAuth loopback redirect
/// (RFC 8252). Binds a random free port, waits for the browser to hit
/// `/callback?code=…&state=…`, and returns that URL — enabling a seamless
/// "log in and come straight back" flow with no manual code paste.
@MainActor
final class LoopbackServer {
    private var listener: NWListener?
    private var codeContinuation: CheckedContinuation<URL, Error>?
    private var delivered = false

    /// Starts listening and returns the bound port.
    func start() async throws -> UInt16 {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        return try await withCheckedThrowingContinuation { cont in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue { cont.resume(returning: port) }
                    else { cont.resume(throwing: AuthError.tokenExchangeFailed("포트 할당 실패")) }
                case .failed(let err):
                    cont.resume(throwing: err)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.handle(conn) }
            }
            listener.start(queue: .main)
        }
    }

    /// Suspends until the browser redirects to our callback.
    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            self.codeContinuation = cont
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            guard let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first else {
                conn.cancel(); return
            }
            // "GET /callback?code=...&state=... HTTP/1.1"
            let parts = requestLine.split(separator: " ")
            let path = parts.count >= 2 ? String(parts[1]) : "/"
            let callback = URL(string: "http://localhost\(path)")

            let html = """
            <!doctype html><html><head><meta charset="utf-8"><title>mongshell-menubar</title></head>
            <body style="font-family:-apple-system,system-ui;background:#f3f2ef;color:#1d1d1f;text-align:center;padding-top:120px">
            <h2 style="font-weight:600">로그인 완료 ✅</h2>
            <p style="color:#86868b">이 탭을 닫고 앱으로 돌아가세요.</p></body></html>
            """
            let response = """
            HTTP/1.1 200 OK\r
            Content-Type: text/html; charset=utf-8\r
            Content-Length: \(html.utf8.count)\r
            Connection: close\r
            \r
            \(html)
            """
            conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })

            Task { @MainActor in
                guard !self.delivered, let callback else { return }
                self.delivered = true
                self.codeContinuation?.resume(returning: callback)
                self.codeContinuation = nil
            }
        }
    }
}
