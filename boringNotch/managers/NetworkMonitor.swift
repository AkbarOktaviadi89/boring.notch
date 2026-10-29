//
//  NetworkMonitor.swift
//  boringNotch
//
//  Created by Akbar Oktaviadi on 2026-10-29.
//

import Combine
import Foundation

/// Monitor › Network: the local connection (read by the XPC helper), the public address (ipinfo.io)
/// and a speed test against Cloudflare's speed endpoints, run only when asked
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    enum SpeedPhase: Equatable {
        case idle, ping, download, upload, done
    }

    static let downloadBytes = 25_000_000
    static let uploadBytes = 10_000_000

    @Published private(set) var info = NetworkInfo()
    @Published private(set) var hasLoaded = false
    @Published private(set) var helperUnavailable = false
    @Published private(set) var publicIP: PublicIPInfo?
    @Published private(set) var publicIPError: String?
    @Published private(set) var isLoadingPublicIP = false

    @Published private(set) var speedPhase: SpeedPhase = .idle
    @Published private(set) var pingMilliseconds: Double?
    @Published private(set) var downloadMbps: Double?
    @Published private(set) var uploadMbps: Double?
    @Published private(set) var speedError: String?

    private var pollTask: Task<Void, Never>?
    private var speedTask: Task<Void, Never>?
    private var viewers = 0

    /// No caches or cookies, so every measurement really goes over the network
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration)
    }()

    private init() {}

    func startMonitoring() {
        viewers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshLocal()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        if publicIP == nil { Task { await refreshPublicIP() } }
    }

    func stopMonitoring() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refreshLocal() async {
        guard let report = await XPCHelperClient.shared.networkReport() else {
            helperUnavailable = true
            hasLoaded = true
            return
        }
        let new = NetworkInfoParser.parse(report)
        let changed = new.interface != info.interface || new.vpnInterface != info.vpnInterface || new.localIPv4 != info.localIPv4
        info = new
        helperUnavailable = false
        // A VPN switching on or a new network changes the public address too
        if hasLoaded && changed { Task { await refreshPublicIP() } }
        hasLoaded = true
    }

    func refreshPublicIP() async {
        guard let url = URL(string: "https://ipinfo.io/json") else { return }
        isLoadingPublicIP = true
        defer { isLoadingPublicIP = false }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("BoringNotch", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: request)
            publicIP = try JSONDecoder().decode(PublicIPInfo.self, from: data)
            publicIPError = nil
        } catch {
            publicIP = nil
            publicIPError = (error as? URLError)?.code == .notConnectedToInternet ? "Offline" : "Couldn't look it up"
        }
    }

    // MARK: - Speed test

    func runSpeedTest() {
        guard speedTask == nil else { return }
        pingMilliseconds = nil
        downloadMbps = nil
        uploadMbps = nil
        speedError = nil
        speedTask = Task { [weak self] in
            await self?.measure()
            self?.speedTask = nil
        }
    }

    func cancelSpeedTest() {
        speedTask?.cancel()
        speedTask = nil
        speedPhase = .idle
    }

    private func measure() async {
        do {
            speedPhase = .ping
            var pings: [Double] = []
            for _ in 0..<5 {
                let start = ContinuousClock.now
                _ = try await session.data(from: Self.downURL(bytes: 0))
                pings.append(Self.seconds(since: start) * 1000)
            }
            // The fastest round trips: the first one also pays for setting up the connection
            pingMilliseconds = pings.sorted().prefix(3).reduce(0, +) / 3

            speedPhase = .download
            let downStart = ContinuousClock.now
            let (data, _) = try await session.data(from: Self.downURL(bytes: Self.downloadBytes))
            downloadMbps = NetworkInfoParser.mbps(bytes: data.count, seconds: Self.seconds(since: downStart))

            speedPhase = .upload
            var request = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let upStart = ContinuousClock.now
            _ = try await session.upload(for: request, from: Data(count: Self.uploadBytes))
            uploadMbps = NetworkInfoParser.mbps(bytes: Self.uploadBytes, seconds: Self.seconds(since: upStart))

            speedPhase = .done
        } catch is CancellationError {
            speedPhase = .idle
        } catch {
            speedError = (error as? URLError)?.code == .cancelled ? nil : "Speed test failed: \(error.localizedDescription)"
            speedPhase = .idle
        }
    }

    private static func downURL(bytes: Int) -> URL {
        URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
    }

    private static func seconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }
}
