import XCTest
import flutter_control_center

/// Runtime tests of the storage protocol shared by the app and the Widget Extension.
/// The extension compiles the identical FlutterControlCenterStore.swift source.
final class RunnerTests: XCTestCase {
  private let group = "group.com.manishpanday.flutterControlCenterExample"
  private var store: FlutterControlCenterStore!

  override func setUp() {
    super.setUp()
    store = FlutterControlCenterStore(appGroup: group)
    XCTAssertNotNil(store)
    _ = store.drainActions()
    for kind in store.allStates().keys {
      store.removeState(kind: kind)
    }
  }

  func testRejectsEmptyGroup() {
    XCTAssertNil(FlutterControlCenterStore(appGroup: ""))
  }

  func testAppGroupContainerIsAccessible() {
    XCTAssertTrue(store.isAppGroupAccessible)
  }

  func testToggleStateRoundTrip() {
    XCTAssertNil(store.state(kind: "focus_mode"))
    XCTAssertTrue(store.isOn(kind: "focus_mode", defaultValue: true))
    store.setToggle(kind: "focus_mode", isOn: true, source: FlutterControlCenterStore.sourceControl)
    let state = store.state(kind: "focus_mode")
    XCTAssertEqual(state?["isOn"] as? Bool, true)
    XCTAssertEqual(state?["source"] as? String, "control")
    XCTAssertEqual(state?["kind"] as? String, "focus_mode")
    XCTAssertGreaterThan(state?["updatedAt"] as? Double ?? 0, 1_700_000_000_000)
    XCTAssertFalse(store.isOn(kind: "other", defaultValue: false))
    XCTAssertEqual(Set(store.allStates().keys), ["focus_mode"])
    store.removeState(kind: "focus_mode")
    XCTAssertNil(store.state(kind: "focus_mode"))
  }

  func testStateIsVisibleToASecondStoreInstance() {
    store.setToggle(kind: "shared", isOn: true, source: FlutterControlCenterStore.sourceApp)
    let other = FlutterControlCenterStore(appGroup: group)!
    XCTAssertEqual(other.state(kind: "shared")?["isOn"] as? Bool, true)
  }

  func testQueueDrainAndRemove() {
    let a = FlutterControlCenterStore.makeAction(
      kind: "start_timer", type: FlutterControlCenterStore.typeButton, action: "start_timer",
      value: nil, payload: ["minutes": "25"])
    let b = FlutterControlCenterStore.makeAction(
      kind: "focus_mode", type: FlutterControlCenterStore.typeToggle, action: nil, value: true,
      payload: [:])
    store.enqueue(action: a)
    store.enqueue(action: b)
    XCTAssertEqual(store.pendingActions().count, 2)
    store.removeAction(id: a["id"] as! String)
    let drained = store.drainActions()
    XCTAssertEqual(drained.count, 1)
    XCTAssertEqual(drained.first?["kind"] as? String, "focus_mode")
    XCTAssertEqual(drained.first?["value"] as? Bool, true)
    XCTAssertTrue(store.drainActions().isEmpty)
  }

  func testQueueIsCapped() {
    for index in 0..<(FlutterControlCenterStore.maxQueuedActions + 5) {
      store.enqueue(
        action: FlutterControlCenterStore.makeAction(
          kind: "k\(index)", type: FlutterControlCenterStore.typeButton, action: nil, value: nil,
          payload: [:]))
    }
    let queue = store.drainActions()
    XCTAssertEqual(queue.count, FlutterControlCenterStore.maxQueuedActions)
    XCTAssertEqual(queue.first?["kind"] as? String, "k5")
  }

  func testActionURLRoundTrip() throws {
    let action = FlutterControlCenterStore.makeAction(
      kind: "start_timer", type: FlutterControlCenterStore.typeButton, action: "start timer",
      value: nil, payload: ["minutes": "25", "note": "a&b=c"])
    let url = try XCTUnwrap(FlutterControlCenterStore.actionURL(scheme: "fccexample", action: action))
    XCTAssertEqual(url.scheme, "fccexample")
    XCTAssertEqual(url.host, "flutter-control-center")
    let parsed = try XCTUnwrap(FlutterControlCenterStore.parseActionURL(url))
    XCTAssertEqual(parsed["id"] as? String, action["id"] as? String)
    XCTAssertEqual(parsed["kind"] as? String, "start_timer")
    XCTAssertEqual(parsed["action"] as? String, "start timer")
    XCTAssertEqual(parsed["type"] as? String, "button")
    XCTAssertEqual(parsed["payload"] as? [String: String], ["minutes": "25", "note": "a&b=c"])
    XCTAssertEqual(
      parsed["timestamp"] as? Double, (action["timestamp"] as? Double).map { Double(Int64($0)) })
  }

  func testForeignURLsAreIgnored() {
    XCTAssertNil(FlutterControlCenterStore.parseActionURL(URL(string: "fccexample://other/path")!))
    XCTAssertNil(
      FlutterControlCenterStore.parseActionURL(
        URL(string: "fccexample://flutter-control-center/action?kind=x")!))
    XCTAssertNil(FlutterControlCenterStore.actionURL(scheme: "", action: [:]))
  }

  func testDarwinNotificationIsDelivered() {
    let expectation = expectation(description: "darwin notification")
    let box = Unmanaged.passRetained(ExpectationBox(expectation)).toOpaque()
    let name = FlutterControlCenterStore.notificationName(appGroup: group) as CFString
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), box,
      { _, observer, _, _, _ in
        guard let observer = observer else { return }
        Unmanaged<ExpectationBox>.fromOpaque(observer).takeUnretainedValue().expectation.fulfill()
      }, name, nil, .deliverImmediately)
    store.postChangeNotification()
    wait(for: [expectation], timeout: 5)
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), box)
    Unmanaged<ExpectationBox>.fromOpaque(box).release()
  }
}

private final class ExpectationBox {
  let expectation: XCTestExpectation
  init(_ expectation: XCTestExpectation) { self.expectation = expectation }
}
