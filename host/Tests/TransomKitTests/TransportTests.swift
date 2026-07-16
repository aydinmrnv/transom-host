import Testing

@testable import TransomKit

/// The private-address gate is the security note's enforcement point, so its
/// classification is pure and tested. A false positive here would let the host
/// bind somewhere the internet can reach.
@Suite("PrivateAddress")
struct PrivateAddressTests {

    @Test("private ranges are accepted")
    func privateAccepted() {
        for ip in [
            "10.0.0.1", "10.255.255.255", "192.168.0.200", "192.168.1.1",
            "172.16.0.1", "172.31.255.255", "127.0.0.1", "169.254.1.1",
        ] {
            #expect(PrivateAddress.isPrivateIPv4(ip), "\(ip) should be private")
        }
    }

    @Test("public and out-of-range addresses are rejected")
    func publicRejected() {
        for ip in [
            "8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1", "192.169.0.1",
            "11.0.0.1", "169.253.0.1", "203.0.113.5",
        ] {
            #expect(!PrivateAddress.isPrivateIPv4(ip), "\(ip) should be public")
        }
    }

    @Test("malformed input is rejected, not crashed")
    func malformedRejected() {
        for ip in ["", "10.0.0", "10.0.0.0.0", "10.0.0.256", "hello", "10.0.0.x", "::1"] {
            #expect(!PrivateAddress.isPrivateIPv4(ip), "\(ip) should be rejected")
        }
    }
}
