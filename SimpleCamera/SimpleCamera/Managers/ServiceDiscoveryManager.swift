import Foundation
import Network

/**
 * Protocol for service discovery events.
 */
protocol ServiceDiscoveryDelegate: AnyObject {
    func didFindServer(at url: URL)
    func didUpdateDiscoveryStatus(_ status: String)
}

/**
 * ServiceDiscoveryManager handles finding pose analysis servers using various
 * discovery methods.
 *
 * This class uses both NWBrowser and NetServiceBrowser to reliably
 * discover servers on the local network.
 */
class ServiceDiscoveryManager: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    weak var delegate: ServiceDiscoveryDelegate?
    private var browser: NWBrowser?
    private var netServiceBrowser: NetServiceBrowser?
    private var discoveredServices: [NetService] = []
    private var resolvingService: NetService?
    private var serverEndpoint: NWEndpoint?
    private var discoveryTimer: Timer?
    
    init(delegate: ServiceDiscoveryDelegate) {
        self.delegate = delegate
        super.init()
    }
    
    /**
     * Sets a timeout for the discovery process.
     */
    func setDiscoveryTimeout(timeInterval: TimeInterval, completion: @escaping () -> Void) {
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            completion()
        }
    }
    
    /**
     * Starts the service discovery process using multiple methods.
     */
    func startDiscovery() {
        delegate?.didUpdateDiscoveryStatus("Setting up discovery services...")
        
        // First try using Network framework
        setupNWBrowser()
        
        // Also set up NetServiceBrowser as a fallback
        setupNetServiceBrowser()
    }
    
    /**
     * Stops all discovery processes and cleans up resources.
     */
    func stopDiscovery() {
        discoveryTimer?.invalidate()
        browser?.cancel()
        netServiceBrowser?.stop()
        discoveredServices.removeAll()
    }
    
    /**
     * Sets up NWBrowser for service discovery using the Network framework.
     */
    private func setupNWBrowser() {
        // Create a browser to look for our service
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        
        // Look for our service type
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_pose-server._tcp", domain: "local")
        browser = NWBrowser(for: browserDescriptor, using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            
            switch state {
            case .ready:
                self.delegate?.didUpdateDiscoveryStatus("NWBrowser is ready and searching")
                print("NWBrowser is ready")
            case .failed(let error):
                self.delegate?.didUpdateDiscoveryStatus("NWBrowser failed: \(error)")
                print("NWBrowser failed: \(error)")
            case .cancelled:
                self.delegate?.didUpdateDiscoveryStatus("NWBrowser cancelled")
                print("NWBrowser cancelled")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self = self else { return }
            
            self.delegate?.didUpdateDiscoveryStatus("Found \(results.count) services")
            
            // Find the first available server
            if let firstResult = results.first {
                self.serverEndpoint = firstResult.endpoint
                self.connectToServer()
            }
        }
        
        browser?.start(queue: .main)
    }
    
    /**
     * Sets up NetServiceBrowser for Bonjour service discovery.
     */
    private func setupNetServiceBrowser() {
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser?.delegate = self
        netServiceBrowser?.searchForServices(ofType: "_pose-server._tcp.", inDomain: "local.")
    }
    
    /**
     * Attempts to connect to a server discovered via NWBrowser.
     */
    private func connectToServer() {
        guard let endpoint = serverEndpoint else {
            print("No server endpoint available")
            return
        }
        
        delegate?.didUpdateDiscoveryStatus("Found server, attempting to connect...")
        
        // Convert the endpoint to a URL
        if case let NWEndpoint.service(name, type, domain, _) = endpoint {
            // Create a NetService and resolve it
            let service = NetService(domain: domain, type: type, name: name)
            service.delegate = self
            service.resolve(withTimeout: 5.0)
            
            // Store the service
            resolvingService = service
        }
    }
    
    /**
     * Attempts to connect to a discovered NetService.
     */
    private func connectToNetService(_ service: NetService) {
        delegate?.didUpdateDiscoveryStatus("Found server: \(service.name), resolving...")
        
        // Store the service we're trying to resolve
        resolvingService = service
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        // Add the service to our list
        discoveredServices.append(service)
        
        delegate?.didUpdateDiscoveryStatus("Found service: \(service.name)")
        
        // Try to resolve and connect to this service
        connectToNetService(service)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        // Remove the service from our list
        if let index = discoveredServices.firstIndex(of: service) {
            discoveredServices.remove(at: index)
        }
        
        delegate?.didUpdateDiscoveryStatus("Service removed: \(service.name)")
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        delegate?.didUpdateDiscoveryStatus("Service browser stopped")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        delegate?.didUpdateDiscoveryStatus("NetServiceBrowser error: \(errorDict)")
        print("NetServiceBrowser did not search: \(errorDict)")
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else {
            print("Failed to get hostname")
            delegate?.didUpdateDiscoveryStatus("Failed to get hostname for service")
            return
        }
        
        let port = sender.port
        
        delegate?.didUpdateDiscoveryStatus("Resolved service: \(hostName):\(port)")
        
        let urlString = "ws://\(hostName):\(port)/socket.io/?EIO=4&transport=websocket"
        if let url = URL(string: urlString) {
            delegate?.didFindServer(at: url)
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        print("Failed to resolve: \(errorDict)")
        delegate?.didUpdateDiscoveryStatus("Resolution failed: \(errorDict)")
        
        // Try the next available service if we have one
        if let service = discoveredServices.first(where: { $0 != sender }) {
            connectToNetService(service)
        }
    }
} 