// SampleCallStackSymbols.swift
// Test fixtures for FrameBuilder and related tests.

enum SampleCallStackSymbols {

    // MARK: - macOS debug-symbolicated fixture
    // Simulates a stack from a macOS Sphinx app crash (in-app frames from "Sphinx" image)
    static let macOSDebugStack: [String] = [
        "0   Sphinx                             0x000000010012abcd $s6Sphinx14SomeManagerC13handleRequestyyF + 44",
        "1   Sphinx                             0x000000010012ef01 $s6Sphinx22DashboardViewControllerC11viewDidLoadyyF + 128",
        "2   AppKit                             0x00007fff3a1b2c34 -[NSViewController viewDidLoad] + 87",
        "3   AppKit                             0x00007fff3a1b3456 -[NSViewController _sendViewDidLoad] + 99",
        "4   CoreFoundation                     0x00007fff205b789a __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__ + 17",
        "5   CoreFoundation                     0x00007fff205b1234 __CFRunLoopDoSource0 + 180",
        "6   libsystem_pthread.dylib            0x00007fff61234abc _pthread_start + 224",
    ]

    // MARK: - macOS stripped/release fixture (no symbols)
    static let macOSStrippedStack: [String] = [
        "0   Sphinx                             0x000000010012abcd 0x100000000 + 76476",
        "1   Sphinx                             0x000000010012ef01 0x100000000 + 77569",
        "2   AppKit                             0x00007fff3a1b2c34 0x7fff3a000000 + 715828",
        "3   libsystem_pthread.dylib            0x00007fff61234abc 0x7fff61200000 + 210620",
    ]

    // MARK: - iOS debug fixture
    static let iOSDebugStack: [String] = [
        "0   sphinx                             0x0000000100123abc $s6sphinx15ChatViewControllerC14sendMessageyyF + 60",
        "1   sphinx                             0x0000000100124def $s6sphinx16MessagesViewModelC11handleSendyyF + 88",
        "2   UIKitCore                          0x000000019b1234ab -[UIButton sendAction:to:from:forEvent:] + 96",
        "3   UIKitCore                          0x000000019b1244ab -[UIControl sendActionsForControlEvents:] + 116",
        "4   libdispatch.dylib                  0x0000000192ab1234 _dispatch_main_queue_callback_4CF + 44",
    ]

    // MARK: - Expected ErrorReport JSON matching Hive contract
    static let expectedReportJSON = """
    {
      "exceptionType": "NSInvalidArgumentException",
      "message": "Test exception reason",
      "repository": "stakwork/sphinx-mac-v2",
      "stackTrace": "0   Sphinx   0x1234 function + 0"
    }
    """
}
