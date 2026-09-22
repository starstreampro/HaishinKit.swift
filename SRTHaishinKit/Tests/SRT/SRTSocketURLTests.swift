import Foundation
import Testing

import libsrt
@testable import SRTHaishinKit

@Suite actor SRTSocketURLTests {
    /// SRTO_TRANSTYPE resets latency/peerlatency/tlpktdrop to the transtype defaults, so it has
    /// to reach the socket before them no matter where it sits in the URL.
    @Test func transtypeIsAppliedFirst() {
        let after = SRTSocketURL(URL(string: "srt://host:9000?streamid=abc&latency=1500&mode=caller&transtype=live&tlpktdrop=1"))
        #expect(after?.options.first?.name.rawValue == "transtype")
        let before = SRTSocketURL(URL(string: "srt://host:9000?transtype=live&streamid=abc&latency=1500&tlpktdrop=1"))
        #expect(before?.options.first?.name.rawValue == "transtype")
        let none = SRTSocketURL(URL(string: "srt://host:9000?streamid=abc&latency=1500"))
        #expect(none?.options.map(\.name.rawValue) == ["streamid", "latency"])
    }

    @Test func urlOrderIsPreserved() {
        let url = SRTSocketURL(URL(string: "srt://host:9000?tlpktdrop=1&latency=1500&transtype=live&streamid=abc&maxbw=1310720"))
        #expect(url?.options.map(\.name.rawValue) == ["transtype", "tlpktdrop", "latency", "streamid", "maxbw"])
        #expect(url?.mode == .caller)
    }

    /// End to end against libsrt: the app's own URL shape must leave latency at 1500, not 120.
    @Test func latencySurvivesTranstypeOnRealSocket() {
        srt_startup()
        let socket = srt_create_socket()
        defer { srt_close(socket) }
        guard let url = SRTSocketURL(URL(string: "srt://host:9000?streamid=abc&latency=1500&mode=caller&transtype=live&maxbw=1310720&tlpktdrop=1")) else {
            Issue.record("url did not parse")
            return
        }
        for option in url.options where option.name.restriction == .pre {
            do {
                try option.setSockflag(socket)
            } catch {
                Issue.record("\(option.name.rawValue) rejected: \(error)")
            }
        }
        func read(_ name: SRTSocketOption.Name) -> Int? {
            do {
                return try SRTSocketOption(name: name, socket: socket).intValue
            } catch {
                Issue.record("\(name.rawValue) read failed: \(error)")
                return nil
            }
        }
        #expect(read(.latency) == 1500)
        #expect(read(.rcvlatency) == 1500)
        #expect(read(.peerlatency) == 1500)
        // SRTO_TRANSTYPE is set-only in libsrt (getOpt has no case for it), so it is not read back.
        #expect(read(.tlpktdrop) == 1)
    }
}
