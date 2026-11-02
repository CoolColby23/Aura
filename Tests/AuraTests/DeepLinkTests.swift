import Foundation
import Testing

@testable import Aura

struct DeepLinkTests {
    @Test func widgetDestinationAndUnknownLinks() throws {
        #expect(AuraDeepLink(url: try #require(URL(string: "aura://now-playing"))) == .nowPlaying)
        #expect(AuraDeepLink(url: try #require(URL(string: "https://now-playing"))) == nil)
        #expect(AuraDeepLink(url: try #require(URL(string: "aura://unknown"))) == nil)
    }
}
