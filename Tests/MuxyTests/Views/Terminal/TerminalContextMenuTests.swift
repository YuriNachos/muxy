import AppKit
import Testing

@testable import Muxy

@Suite("Terminal context menu")
@MainActor
struct TerminalContextMenuTests {
    @Test("send to background invokes its action for a persistent terminal")
    func sendToBackgroundInvokesAction() throws {
        let flag = TerminalBackgroundActionFlag()
        let view = GhosttyTerminalNSView(
            workingDirectory: "/tmp",
            persistentSessionID: UUID()
        )
        view.onSendToBackground = {
            flag.didInvoke = true
        }

        let menu = view.makeContextMenu()
        let item = try #require(menu.items.first {
            $0.title == L10n.string("Send to Background")
        })

        #expect(item.isEnabled)

        _ = item.target?.perform(item.action, with: item)

        #expect(flag.didInvoke)
    }

    @Test("send to background is disabled without a persistent session")
    func sendToBackgroundRequiresPersistentSession() throws {
        let view = GhosttyTerminalNSView(workingDirectory: "/tmp")
        view.onSendToBackground = {}

        let menu = view.makeContextMenu()
        let item = try #require(menu.items.first {
            $0.title == L10n.string("Send to Background")
        })

        #expect(!item.isEnabled)
    }

    @Test("terminal settings item opens settings focused on Terminal")
    func terminalSettingsItemOpensTerminalSettings() throws {
        let notificationCenter = NotificationCenter()
        let coordinator = SettingsFocusCoordinator(notificationCenter: notificationCenter)
        let flag = TerminalSettingsOpenFlag()
        let observer = notificationCenter.addObserver(
            forName: .openSettingsModal,
            object: nil,
            queue: nil
        ) { _ in
            flag.didPost = true
        }
        defer { notificationCenter.removeObserver(observer) }
        let view = GhosttyTerminalNSView(workingDirectory: "/tmp")

        let menu = view.makeContextMenu(settingsFocusCoordinator: coordinator)
        let settingsIndex = try #require(menu.items.firstIndex {
            $0.title == L10n.string("Terminal Settings…")
        })
        let settingsItem = menu.items[settingsIndex]

        #expect(settingsIndex > 0)
        #expect(menu.items[settingsIndex - 1].isSeparatorItem)

        _ = settingsItem.target?.perform(settingsItem.action, with: settingsItem)

        #expect(flag.didPost)
        #expect(coordinator.consume(.terminal))
    }
}

private final class TerminalSettingsOpenFlag: @unchecked Sendable {
    var didPost = false
}

private final class TerminalBackgroundActionFlag {
    var didInvoke = false
}
