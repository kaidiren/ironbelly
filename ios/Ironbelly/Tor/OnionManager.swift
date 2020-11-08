//
//  OnionManager.swift
//  OnionBrowser2
//
//  Copyright (c) 2012-2020, Tigas Ventures, LLC (Mike Tigas)
//
//  This file is part of Onion Browser. See LICENSE file for redistribution terms.
//

import Foundation
import Reachability
import Tor
import IPtProxy

enum OnionError: Error {
    case connectionError
    case invalidBridges
    case missingCookieFile
}

extension OnionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingCookieFile:
            return NSLocalizedString("Onion_Error.error.missing_cookie_file", comment: "Onion error")
        case .invalidBridges:
            return NSLocalizedString("Onion_Error.error.invalid_bridges", comment: "Onion error")
        case .connectionError:
            return NSLocalizedString("Onion_Error.error.connectionError", comment: "Onion error")
        }
    }

    public var failureReason: String? {
        switch self {
        case .connectionError, .invalidBridges, .missingCookieFile:
            return NSLocalizedString("Onion_Error.error.title.onionError", comment: "Onion error")
        }
    }
}


protocol OnionManagerDelegate: class {

    func onTorConnProgress(_ progress: Int)

    func onTorConnFinished(_ configuration: BridgesConfuguration)

    func onTorConnDifficulties(error: OnionError)
    
    func onTorPortsOpened()
}

class OnionManager: NSObject {
    enum TorState: Int {
        case none
        case started
        case connected
        case stopped
    }
    
    static let shared = OnionManager()
    private var reachability: Reachability?
    
    // Show Tor log in iOS' app log.
    private static let TOR_LOGGING = false
    static let CONTROL_ADDRESS = "127.0.0.1"
    static let CONTROL_PORT: UInt16 = 39069
    
    static func getCookie() throws -> Data {
        if let cookieURL = OnionManager.torBaseConf().dataDirectory?.appendingPathComponent("control_auth_cookie") {
            let cookie = try Data(contentsOf: cookieURL)

            //TariLogger.tor("Using cookie for control auth")

            return cookie
        } else {
            throw OnionError.missingCookieFile
        }
    }
    
    private static func torBaseConf() -> TorConfiguration {
        // Store data in <appdir>/Library/Caches/tor (Library/Caches/ is for things that can persist between
        // launches -- which we'd like so we keep descriptors & etc -- but don't need to be backed up because
        // they can be regenerated by the app)


        // Configure tor and return the configuration object
        let configuration = TorConfiguration()
        configuration.cookieAuthentication = true
        
        if let dataDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?.appendingPathComponent("tor/listener", isDirectory: true) {
            #if DEBUG
            print("dataDir=\(dataDir)")
            #endif
        
            let torrcFile = dataDir.appendingPathComponent("torrc", isDirectory: false);

            // Create tor data directory if it does not yet exist
            do {
                try FileManager.default.createDirectory(atPath: dataDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                //TariLogger.tor("Failed to create tor directory", error: error)
            }
            // Create tor v3 auth directory if it does not yet exist
            let authDir = URL(fileURLWithPath: dataDir.path, isDirectory: true).appendingPathComponent("auth", isDirectory: true)
            do {
                try FileManager.default.createDirectory(atPath: authDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch let error as NSError {
                //TariLogger.tor("Failed to create tor auth directory", error: error)
            }
            
            configuration.dataDirectory = dataDir
            

            #if DEBUG
            let log_loc = "notice stdout"
            #else
            let log_loc = "notice file /dev/null"
            #endif
            
            configuration.arguments = [
//                "--allow-missing-torrc",
//                "--ignore-missing-torrc",
                "-f", torrcFile.path,
//                "--clientonly", "1",
                "--AvoidDiskWrites", "1",
//                "--socksport", "39059",
                //"--controlport", "\(OnionManager.CONTROL_ADDRESS):\(OnionManager.CONTROL_PORT)",
                "--log", log_loc,
                "--clientuseipv6", "1",
//                "--ClientTransportPlugin", "obfs4 socks5 127.0.0.1:47351",
//                "--ClientTransportPlugin", "meek_lite socks5 127.0.0.1:47352",
                "--ClientOnionAuthDir", authDir.path
            ]
        }
        
        return configuration
    }
    
    var state = TorState.none
    private var torController: TorController?
    private var torThread: TorThread?
    private var initRetry: DispatchWorkItem?
    private var bridgesType = OnionSettings.currentlyUsedBridgesConfiguration.bridgesType
    private var customBridges = OnionSettings.currentlyUsedBridgesConfiguration.customBridges
    private var needsReconfiguration = false

    private var cookie: Data? {
        if let cookieUrl = OnionManager.torBaseConf().dataDirectory?.appendingPathComponent("control_auth_cookie") {
            return try? Data(contentsOf: cookieUrl)
        }
        return nil
    }

    

    func torReconnect() {
        guard self.torThread != nil else {
            //TariLogger.tor("No tor thread, aborting reconnect")
            return
        }
        
        //TariLogger.tor("Tor reconnecting...")
        
        torController?.resetConnection({ (complete) in
            //TariLogger.tor("Tor reconnected")
        })
    }

    /**
    Get all fully built circuits and detailed info about their nodes.

    - parameter callback: Called, when all info is available.
    - parameter circuits: A list of circuits and the nodes they consist of.
    */
    func getCircuits(_ callback: @escaping ((_ circuits: [TorCircuit]) -> Void)) {
        torController?.getCircuits(callback)
    }
    
    func closeCircuits(_ circuits: [TorCircuit], _ callback: @escaping ((_ success: Bool) -> Void)) {
        torController?.close(circuits, completion: callback)
    }
    
    func startIObfs4Proxy() {
        IPtProxyStartObfs4Proxy()
    }

    func startTor(delegate: OnionManagerDelegate?) {
        // Avoid a retain cycle. Only use the weakDelegate in closures!
        weak var weakDelegate = delegate

        cancelInitRetry()
        state = .started

        if (self.torController == nil) {
            self.torController = TorController(socketHost: OnionManager.CONTROL_ADDRESS, port: OnionManager.CONTROL_PORT)
        }

        do {
            try startObserveReachability()
            //TariLogger.tor("Listening for reachability changes to reconnect tor")
        } catch {
            //TariLogger.tor("Failed to init Reachability", error: error)
        }


        if torThread?.isCancelled ?? true {
            torThread = nil

            let torConf = OnionManager.torBaseConf()

            var args = torConf.arguments!

            args += getBridgesAsArgs()

            // configure ipv4/ipv6
            // Use Ipv6Tester. If we _think_ we're IPv6-only, tell Tor to prefer IPv6 ports.
            // (Tor doesn't always guess this properly due to some internal IPv4 addresses being used,
            // so "auto" sometimes fails to bootstrap.)
            //TariLogger.tor("ipv6_status: \(Ipv6Tester.ipv6_status())")
            if (Ipv6Tester.ipv6_status() == .torIpv6ConnOnly) {
                args += ["--ClientPreferIPv6ORPort", "1"]

                if bridgesType != .none {
                    // Bridges on, leave IPv4 on.
                    // User's bridge config contains all the IPs (v4 or v6)
                    // that we connect to, so we let _that_ setting override our
                    // "IPv6 only" self-test.
                    args += ["--ClientUseIPv4", "1"]
                }
                else {
                    // Otherwise, for IPv6-only no-bridge state, disable IPv4
                    // connections from here to entry/guard nodes.
                    // (i.e. all outbound connections are ipv6 only.)
                    args += ["--ClientUseIPv4", "0"]
                }
            }
            else {
                args += [
                    "--ClientPreferIPv6ORPort", "auto",
                    "--ClientUseIPv4", "1",
                ]
            }

            #if DEBUG
            //TariLogger.tor("arguments=\(String(describing: args))")
            #endif

            torConf.arguments = args
            torThread = TorThread(configuration: torConf)
            needsReconfiguration = false

            torThread?.start()
            startIObfs4Proxy()
            //TariLogger.tor("Starting Tor")
        }
        else {
            if needsReconfiguration {
                let conf = getBridgesAsConf()

                torController?.resetConf(forKey: "Bridge")

                if conf.count > 0 {
                    // Bridges need to be set *before* "UseBridges"="1"!
                    torController?.setConfs(conf)
                    torController?.setConfForKey("UseBridges", withValue: "1")
                }
                else {
                    torController?.setConfForKey("UseBridges", withValue: "0")
                }
            }
        }

        // Wait long enough for Tor itself to have started. It's OK to wait for this
        // because Tor is already trying to connect; this is just the part that polls for
        // progress.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            if OnionManager.TOR_LOGGING {
                // Show Tor log in iOS' app log.
                TORInstallTorLoggingCallback { severity, msg in
                    let s: String

                    switch severity {
                    case .debug:
                        s = "debug"

                    case .error:
                        s = "error"

                    case .fault:
                        s = "fault"

                    case .info:
                        s = "info"

                    default:
                        s = "default"
                    }

                    //TariLogger.tor("[Tor libevent \(s)] \(String(cString: msg))")
                }
                TORInstallEventLoggingCallback { severity, msg in
                    let s: String

                    switch severity {
                    case .debug:
                        // Ignore libevent debug messages. Just too many of typically no importance.
                        return

                    case .error:
                        s = "error"

                    case .fault:
                        s = "fault"

                    case .info:
                        s = "info"

                    default:
                        s = "default"
                    }
                    //TariLogger.tor("[Tor libevent \(s)] \(String(cString: msg).trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }

            if !(self.torController?.isConnected ?? false) {
                do {
                    try self.torController?.connect()
                } catch {
                    //TariLogger.tor("Tor controller connection", error: error)
                }
            }

            guard let cookie = self.cookie else {
                //TariLogger.tor("Could not connect to Tor - invalid bridges!")
                delegate?.onTorConnDifficulties(error: OnionError.invalidBridges)
                return
            }

            #if DEBUG
            //TariLogger.tor("cookie= \(cookie.base64EncodedString())")
            #endif

            self.torController?.authenticate(with: cookie, completion: { success, error in
                if success {
                    delegate?.onTorPortsOpened()
                    var completeObs: Any?
                    completeObs = self.torController?.addObserver(forCircuitEstablished: { established in
                        if established {
                            self.state = .connected
                            self.torController?.removeObserver(completeObs)
                            self.cancelInitRetry()
                            #if DEBUG
                            //TariLogger.tor("Connection established!")
                            #endif
                            let bridgeConfiguration = BridgesConfuguration(bridges: self.bridgesType, customBridges: self.customBridges)
                            weakDelegate?.onTorConnFinished(bridgeConfiguration)
                        }
                    }) // torController.addObserver

                    var progressObs: Any?
                    progressObs = self.torController?.addObserver(forStatusEvents: {
                        (type: String, severity: String, action: String, arguments: [String : String]?) -> Bool in

                        if type == "STATUS_CLIENT" && action == "BOOTSTRAP" {
                            let progress = Int(arguments!["PROGRESS"]!)!
                            #if DEBUG
                            //TariLogger.tor("progress=\(progress)")
                            #endif

                            weakDelegate?.onTorConnProgress(progress)

                            if progress >= 100 {
                                self.torController?.removeObserver(progressObs)
                            }

                            return true
                        }

                        return false
                    })
                } else {
                    //TariLogger.tor("Didn't connect to control port.", error: error)
                }
            }) // controller authenticate
        }) //delay

        initRetry = DispatchWorkItem {
            #if DEBUG
            //TariLogger.tor("Triggering Tor connection retry.")
            #endif

            self.torController?.setConfForKey("DisableNetwork", withValue: "1")
            self.torController?.setConfForKey("DisableNetwork", withValue: "0")

            // Hint user that they might need to use a bridge.
            delegate?.onTorConnDifficulties(error: OnionError.connectionError)
        }

        // On first load: If Tor hasn't finished bootstrap in 30 seconds,
        // HUP tor once in case we have partially bootstrapped but got stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: initRetry!)
    }
    
    /**
    Experimental Tor shutdown.
    */
    func stopTor(completion:(() -> Void)? = nil) { // completion only in foreground
        //TariLogger.tor("Stopping tor")

        // Under the hood, TORController will SIGNAL SHUTDOWN and set it's channel to nil, so
        // we actually rely on that to stop Tor and reset the state of torController. (we can
        // SIGNAL SHUTDOWN here, but we can't reset the torController "isConnected" state.)
        torController?.disconnect()
        torController = nil

        // More cleanup
        torThread?.cancel()
        
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] (timer) in
            if (self?.torThread == nil || ((self?.torThread?.isFinished) == true && self?.torThread?.isExecuting == false)) {
                self?.torThread = nil
                timer.invalidate()
                completion?()
            }
        }
        
        state = .stopped
    }
    
    /**
    Set bridges configuration and evaluate, if the new configuration is actually different
    then the old one.

    - parameter bridgesType: the selected ID as defined in OBSettingsConstants.
    - parameter customBridges: a list of custom bridges the user configured.
    */
    func setBridgeConfiguration(bridgesType: OnionSettings.BridgesType, customBridges: [String]?) {
        needsReconfiguration = bridgesType != self.bridgesType

        if !needsReconfiguration {
            if let oldVal = self.customBridges, let newVal = customBridges {
                needsReconfiguration = oldVal != newVal
            }
            else{
                needsReconfiguration = (self.customBridges == nil && customBridges != nil) ||
                    (self.customBridges != nil && customBridges == nil)
            }
        }

        self.bridgesType = bridgesType
        self.customBridges = customBridges
    }
}

// MARK: Private Methods


extension OnionManager {
    /**
    - returns: The list of bridges which is currently configured to be valid.
    */
    private func getBridges() -> [String] {
        #if DEBUG
        //TariLogger.tor("bridgesId=\(bridgesType)")
        #endif

        switch bridgesType {
        case .custom:
            return customBridges ?? []

        default:
            return []
        }
    }

    /**
    - returns: The list of bridges which is currently configured to be valid *as argument list* to be used on Tor startup.
    */
    private func getBridgesAsArgs() -> [String] {
        var args = [String]()

        for bridge in getBridges() {
            args += ["--Bridge", bridge]
        }

        if args.count > 0 {
            args.append(contentsOf: ["--UseBridges", "1"])
        }

        return args
    }

    /**
    Each bridge line needs to be wrapped in double-quotes (").

    - returns: The list of bridges which is currently configured to be valid *as configuration list* to be used with `TORController#setConfs`.
    */
    private func getBridgesAsConf() -> [[String: String]] {
        return getBridges().map { ["key": "Bridge", "value": "\"\($0)\""] }
    }

    /**
    Cancel the connection retry and fail guard.
    */
    private func cancelInitRetry() {
        initRetry?.cancel()
        initRetry = nil
    }
}

// MARK: Reachability

extension OnionManager {
    @objc private func networkChange() {
        //TariLogger.tor("ipv6_status: \(Ipv6Tester.ipv6_status())")
        var confs:[Dictionary<String,String>] = []

        if (Ipv6Tester.ipv6_status() == .torIpv6ConnOnly) {
            // We think we're on a IPv6-only DNS64/NAT64 network.
            confs.append(["key": "ClientPreferIPv6ORPort", "value": "1"])

            if (self.bridgesType != .none) {
                // Bridges on, leave IPv4 on.
                // User's bridge config contains all the IPs (v4 or v6)
                // that we connect to, so we let _that_ setting override our
                // "IPv6 only" self-test.
                confs.append(["key": "ClientUseIPv4", "value": "1"])
            }
            else {
                // Otherwise, for IPv6-only no-bridge state, disable IPv4
                // connections from here to entry/guard nodes.
                //(i.e. all outbound connections are IPv6 only.)
                confs.append(["key": "ClientUseIPv4", "value": "0"])
            }
        } else {
            // default mode
            confs.append(["key": "ClientPreferIPv6DirPort", "value": "auto"])
            confs.append(["key": "ClientPreferIPv6ORPort", "value": "auto"])
            confs.append(["key": "ClientUseIPv4", "value": "1"])
        }

        torController?.setConfs(confs, completion: { _, _ in
            self.torReconnect()
        })
    }
    
    private func startObserveReachability() throws {
        stopObserveReachability()
        reachability = try Reachability()
        NotificationCenter.default.addObserver(self, selector: #selector(networkChange),
        name: .reachabilityChanged, object: nil)
        try reachability?.startNotifier()
    }

    private func stopObserveReachability() {
        reachability?.stopNotifier()
        NotificationCenter.default.removeObserver(self, name: .reachabilityChanged, object: nil)
    }
}
