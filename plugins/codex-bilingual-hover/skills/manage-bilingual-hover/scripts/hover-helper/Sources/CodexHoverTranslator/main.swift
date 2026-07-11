import AppKit
import ApplicationServices
import CoreVideo
import ScreenCaptureKit
import SwiftUI
import Translation
import Vision

private enum AXTextReader {
    struct Target {
        let text: String
        let textFrame: CGRect
        let hoverRegion: CGRect
    }

    static func target(at point: CGPoint, codexOnly: Bool, helperBundleID: String?) -> Target? {
        let system = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &rawElement) == .success,
              let element = rawElement else { return nil }

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier ?? ""
        if bundleID == helperBundleID { return nil }
        if codexOnly && !isCodexProcess(app, bundleID: bundleID) { return nil }
        if isSuppressedChrome(element) { return nil }

        // A localized navigation control can expose an unrelated English
        // accessibility description (for example, the Chinese “插件” tab exposing
        // the host name “Codex”). Treat the visible localized label as authoritative
        // and do not fall back to ancestor metadata.
        if isInteractiveChrome(element) {
            let primary = primaryTextValues(of: element)
            if primary.contains(where: containsHan),
               !primary.contains(where: { normalize($0) != nil }) {
                return nil
            }
        }

        var roots = [element]
        var ancestor = element
        for _ in 0..<5 {
            guard let parent = elementAttribute(ancestor, kAXParentAttribute) else { break }
            roots.append(parent)
            ancestor = parent
        }

        var matches: [Target] = []
        for (index, root) in roots.enumerated() {
            collectMatches(
                from: root,
                containing: point,
                remainingDepth: max(24, index + 1),
                ancestorFrames: [],
                matches: &matches
            )
        }

        return matches
            .sorted {
                let leftArea = $0.textFrame.width * $0.textFrame.height
                let rightArea = $1.textFrame.width * $1.textFrame.height
                if leftArea == rightArea {
                    let leftRegionArea = $0.hoverRegion.width * $0.hoverRegion.height
                    let rightRegionArea = $1.hoverRegion.width * $1.hoverRegion.height
                    if leftRegionArea == rightRegionArea { return $0.text.count < $1.text.count }
                    return leftRegionArea > rightRegionArea
                }
                return leftArea < rightArea
            }
            .first
    }

    static func isPointInCodex(_ point: CGPoint, helperBundleID: String?) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &rawElement) == .success,
              let element = rawElement else { return false }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        let bundleID = app?.bundleIdentifier ?? ""
        if bundleID == helperBundleID { return false }
        return isCodexProcess(app, bundleID: bundleID)
    }

    static func shouldSuppressTranslation(at point: CGPoint, helperBundleID: String?) -> Bool {
        let system = AXUIElementCreateSystemWide()
        var rawElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &rawElement) == .success,
              let element = rawElement else { return true }
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        let app = NSRunningApplication(processIdentifier: pid)
        if app?.bundleIdentifier == helperBundleID { return true }
        return isSuppressedChrome(element)
    }

    static func isPluginSurfaceVisible() -> Bool {
        // A task can contain words such as "install" in its title, transcript, or
        // preview pane. Reject task chrome before evaluating any plugin signal.
        if containsCodexExactText(anyOf: ["任务操作", "Task actions"]) {
            return false
        }
        if containsCodexText(anyOf: [
            "浏览插件或技能",
            "Browse plugins or skills",
            "搜索插件",
            "Search plugins"
        ]) {
            return true
        }
        if containsCodexTopAction(anyOf: [
            "立即试用", "Try now", "安装插件", "Install plugin", "安装", "Install"
        ]) {
            return true
        }
        return containsCodexPluginBreadcrumb()
    }

    static func containsCodexText(anyOf needles: [String]) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return false
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var visited = 0
        return containsText(in: root, needles: needles, remainingDepth: 18, visited: &visited)
    }

    static func containsCodexExactText(anyOf labels: [String]) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return false
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let canonicalLabels = labels.map(canonicalHostLabel)
        var visited = 0
        return containsExactText(
            in: root,
            canonicalLabels: canonicalLabels,
            remainingDepth: 18,
            visited: &visited
        )
    }

    static func containsCodexTopAction(anyOf needles: [String]) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return false
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windowFrame = elementAttribute(root, kAXFocusedWindowAttribute).flatMap { frame(of: $0) }
        var visited = 0
        return containsTopAction(
            in: root,
            needles: needles,
            windowFrame: windowFrame,
            remainingDepth: 18,
            visited: &visited
        )
    }

    static func codexTopSurfaceTitle() -> String? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return nil
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windowFrame = elementAttribute(root, kAXFocusedWindowAttribute).flatMap { frame(of: $0) }
        var visited = 0
        var candidates: [(text: String, frame: CGRect)] = []
        collectTopEnglishTitles(
            in: root,
            windowFrame: windowFrame,
            remainingDepth: 18,
            visited: &visited,
            candidates: &candidates
        )
        return candidates
            .filter { isPlausiblePluginTitle($0.text) }
            .sorted {
                if abs($0.frame.minX - $1.frame.minX) < 1 { return $0.frame.width > $1.frame.width }
                return $0.frame.minX < $1.frame.minX
            }
            .first?.text
    }

    static func isPlausiblePluginTitle(_ value: String) -> Bool {
        guard let text = normalize(value), (2...80).contains(text.count) else { return false }
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        guard wordCount <= 12 else { return false }

        // These are host UI labels, never plugin names. Plugin titles themselves are
        // deliberately not enumerated because the catalog changes continuously.
        let hostLabels: Set<String> = [
            "chatgpt", "codex", "plugins", "skills", "plugin", "skill",
            "install", "install plugin", "try now", "add plugin", "back",
            "more", "settings", "create", "finder", "task actions",
            "new chat", "recent chats"
        ]
        return !hostLabels.contains(text.lowercased())
    }

    static func containsCodexPluginBreadcrumb() -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return false
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        let windowFrame = elementAttribute(root, kAXFocusedWindowAttribute).flatMap { frame(of: $0) }
        var visited = 0
        var markers: [CGRect] = []
        var titles: [(text: String, frame: CGRect)] = []
        var combinedBreadcrumb = false
        collectPluginBreadcrumbParts(
            in: root,
            windowFrame: windowFrame,
            remainingDepth: 18,
            visited: &visited,
            markers: &markers,
            titles: &titles,
            combinedBreadcrumb: &combinedBreadcrumb
        )
        if combinedBreadcrumb { return true }
        return markers.contains { marker in
            titles.contains { title in
                abs(marker.midY - title.frame.midY) <= 18 &&
                    title.frame.minX > marker.maxX &&
                    title.frame.minX - marker.maxX <= 600
            }
        }
    }

    static func findCodexText(_ needle: String) -> (element: AXUIElement, text: String, frame: CGRect)? {
        findApplicationText(bundleID: "com.openai.codex", needle: needle)
    }

    static func findApplicationText(
        bundleID: String,
        needle: String
    ) -> (element: AXUIElement, text: String, frame: CGRect)? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var visited = 0
        return findText(in: root, needle: needle, remainingDepth: 18, visited: &visited)
    }

    static func listCodexTexts(limit: Int) -> [(String, CGRect?)] {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first else {
            return []
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var visited = 0
        var seen = Set<String>()
        var results: [(String, CGRect?)] = []
        collectTextList(from: root, remainingDepth: 18, limit: limit, visited: &visited, seen: &seen, results: &results)
        return results
    }

    static func pressNearestAction(from element: AXUIElement) -> (depth: Int, result: AXError)? {
        var current = element
        for depth in 0..<7 {
            var actionNames: CFArray?
            if AXUIElementCopyActionNames(current, &actionNames) == .success,
               let names = actionNames as? [String],
               names.contains(kAXPressAction) {
                return (depth, AXUIElementPerformAction(current, kAXPressAction as CFString))
            }
            guard let parent = elementAttribute(current, kAXParentAttribute) else { return nil }
            current = parent
        }
        return nil
    }

    private static func isCodexProcess(_ app: NSRunningApplication?, bundleID: String) -> Bool {
        if bundleID.hasPrefix("com.openai.codex") { return true }
        let path = app?.bundleURL?.path ?? app?.executableURL?.path ?? ""
        return path.contains("/Applications/ChatGPT.app/") || path.contains("/Applications/Codex.app/")
    }

    private static func collectMatches(
        from element: AXUIElement,
        containing point: CGPoint,
        remainingDepth: Int,
        ancestorFrames: [CGRect],
        matches: inout [Target]
    ) {
        if isSuppressedChrome(element) { return }
        let elementFrame = frame(of: element)
        if let elementFrame, !elementFrame.contains(point) { return }

        let frames = elementFrame.map { ancestorFrames + [$0] } ?? ancestorFrames
        if let elementFrame {
            for text in textValues(of: element) {
                if let normalized = normalize(text) {
                    matches.append(
                        Target(
                            text: normalized,
                            textFrame: elementFrame,
                            hoverRegion: preferredHoverRegion(textFrame: elementFrame, frames: frames)
                        )
                    )
                }
            }
        }

        guard remainingDepth > 0 else { return }
        for child in children(of: element) {
            collectMatches(
                from: child,
                containing: point,
                remainingDepth: remainingDepth - 1,
                ancestorFrames: frames,
                matches: &matches
            )
        }
    }

    private static func preferredHoverRegion(textFrame: CGRect, frames: [CGRect]) -> CGRect {
        let rowLikeFrames = frames.filter { frame in
            frame.width >= max(80, textFrame.width) &&
                frame.height >= max(32, textFrame.height) &&
                frame.width <= 760 &&
                frame.height <= 170
        }
        if let row = rowLikeFrames.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            return row
        }
        return textFrame.insetBy(dx: -14, dy: -10)
    }

    private static func findText(
        in element: AXUIElement,
        needle: String,
        remainingDepth: Int,
        visited: inout Int
    ) -> (element: AXUIElement, text: String, frame: CGRect)? {
        visited += 1
        guard visited <= 12_000 else { return nil }
        for text in textValues(of: element) where text.localizedCaseInsensitiveContains(needle) {
            if let frame = frame(of: element) { return (element, text, frame) }
        }
        guard remainingDepth > 0 else { return nil }
        for child in children(of: element) {
            if let match = findText(in: child, needle: needle, remainingDepth: remainingDepth - 1, visited: &visited) {
                return match
            }
        }
        return nil
    }

    private static func containsText(
        in element: AXUIElement,
        needles: [String],
        remainingDepth: Int,
        visited: inout Int
    ) -> Bool {
        visited += 1
        guard visited <= 12_000 else { return false }
        for text in textValues(of: element) {
            if needles.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
                return true
            }
        }
        guard remainingDepth > 0 else { return false }
        for child in children(of: element) {
            if containsText(in: child, needles: needles, remainingDepth: remainingDepth - 1, visited: &visited) {
                return true
            }
        }
        return false
    }

    private static func containsExactText(
        in element: AXUIElement,
        canonicalLabels: [String],
        remainingDepth: Int,
        visited: inout Int
    ) -> Bool {
        visited += 1
        guard visited <= 12_000 else { return false }
        for text in textValues(of: element) {
            let label = canonicalHostLabel(text)
            if canonicalLabels.contains(where: { label.caseInsensitiveCompare($0) == .orderedSame }) {
                return true
            }
        }
        guard remainingDepth > 0 else { return false }
        for child in children(of: element) {
            if containsExactText(
                in: child,
                canonicalLabels: canonicalLabels,
                remainingDepth: remainingDepth - 1,
                visited: &visited
            ) {
                return true
            }
        }
        return false
    }

    private static func containsTopAction(
        in element: AXUIElement,
        needles: [String],
        windowFrame: CGRect?,
        remainingDepth: Int,
        visited: inout Int
    ) -> Bool {
        visited += 1
        guard visited <= 12_000 else { return false }
        if let frame = frame(of: element),
           isTopActionFrame(frame, relativeTo: windowFrame) {
            for text in textValues(of: element) {
                let label = canonicalHostLabel(text)
                if needles.contains(where: {
                    label.caseInsensitiveCompare(canonicalHostLabel($0)) == .orderedSame
                }) {
                    return true
                }
            }
        }
        guard remainingDepth > 0 else { return false }
        for child in children(of: element) {
            if containsTopAction(
                in: child,
                needles: needles,
                windowFrame: windowFrame,
                remainingDepth: remainingDepth - 1,
                visited: &visited
            ) {
                return true
            }
        }
        return false
    }

    private static func isTopActionFrame(_ frame: CGRect, relativeTo windowFrame: CGRect?) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        guard let windowFrame else { return frame.minY < 380 && frame.midX > 600 }
        let localY = frame.minY - windowFrame.minY
        let localMidX = frame.midX - windowFrame.minX
        return localY >= 0 && localY < 380 && localMidX > max(320, windowFrame.width * 0.55)
    }

    private static func collectPluginBreadcrumbParts(
        in element: AXUIElement,
        windowFrame: CGRect?,
        remainingDepth: Int,
        visited: inout Int,
        markers: inout [CGRect],
        titles: inout [(text: String, frame: CGRect)],
        combinedBreadcrumb: inout Bool
    ) {
        visited += 1
        guard visited <= 12_000 else { return }
        if let elementFrame = frame(of: element), isBreadcrumbFrame(elementFrame, relativeTo: windowFrame) {
            for value in textValues(of: element) {
                let label = canonicalHostLabel(value)
                if label.caseInsensitiveCompare("Plugins") == .orderedSame || label == "插件" {
                    markers.append(elementFrame)
                } else if isPlausiblePluginTitle(label) {
                    titles.append((label, elementFrame))
                }

                for prefix in ["Plugins ", "插件 "] where label.lowercased().hasPrefix(prefix.lowercased()) {
                    let remainder = String(label.dropFirst(prefix.count))
                    if isPlausiblePluginTitle(remainder) { combinedBreadcrumb = true }
                }
            }
        }
        guard remainingDepth > 0, !combinedBreadcrumb else { return }
        for child in children(of: element) {
            collectPluginBreadcrumbParts(
                in: child,
                windowFrame: windowFrame,
                remainingDepth: remainingDepth - 1,
                visited: &visited,
                markers: &markers,
                titles: &titles,
                combinedBreadcrumb: &combinedBreadcrumb
            )
        }
    }

    private static func isBreadcrumbFrame(_ frame: CGRect, relativeTo windowFrame: CGRect?) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.height <= 64 else { return false }
        guard let windowFrame else { return frame.minY >= 20 && frame.minY < 160 }
        let localY = frame.minY - windowFrame.minY
        return localY >= 0 && localY < 160
    }

    private static func canonicalHostLabel(_ value: String) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.drop(while: { !$0.isLetter && !$0.isNumber }))
    }

    private static func collectTopEnglishTitles(
        in element: AXUIElement,
        windowFrame: CGRect?,
        remainingDepth: Int,
        visited: inout Int,
        candidates: inout [(text: String, frame: CGRect)]
    ) {
        visited += 1
        guard visited <= 12_000 else { return }
        if let frame = frame(of: element),
           isTopTitleFrame(frame, relativeTo: windowFrame),
           frame.width >= 24, frame.width <= 600, frame.height > 0, frame.height <= 56 {
            for value in textValues(of: element) {
                if let text = normalize(value), text.count <= 120 {
                    candidates.append((text, frame))
                }
            }
        }
        guard remainingDepth > 0 else { return }
        for child in children(of: element) {
            collectTopEnglishTitles(
                in: child,
                windowFrame: windowFrame,
                remainingDepth: remainingDepth - 1,
                visited: &visited,
                candidates: &candidates
            )
        }
    }

    private static func isTopTitleFrame(_ frame: CGRect, relativeTo windowFrame: CGRect?) -> Bool {
        guard let windowFrame else {
            return frame.minY >= 20 && frame.minY < 360 && frame.minX > 120
        }
        let localX = frame.minX - windowFrame.minX
        let localY = frame.minY - windowFrame.minY
        return localY >= 20 && localY < 360 && localX > 120
    }

    private static func collectTextList(
        from element: AXUIElement,
        remainingDepth: Int,
        limit: Int,
        visited: inout Int,
        seen: inout Set<String>,
        results: inout [(String, CGRect?)]
    ) {
        visited += 1
        guard visited <= 12_000, results.count < limit else { return }
        for rawText in textValues(of: element) {
            let text = rawText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 300, seen.insert(text).inserted else { continue }
            results.append((text, frame(of: element)))
            if results.count >= limit { return }
        }
        guard remainingDepth > 0 else { return }
        for child in children(of: element) {
            collectTextList(
                from: child,
                remainingDepth: remainingDepth - 1,
                limit: limit,
                visited: &visited,
                seen: &seen,
                results: &results
            )
            if results.count >= limit { return }
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionAX = positionValue as! AXValue?,
              let sizeAX = sizeValue as! AXValue? else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAX, .cgPoint, &position),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func textValues(of element: AXUIElement) -> [String] {
        let attributes = [
            kAXValueAttribute,
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute
        ]
        var results: [String] = []
        for attribute in attributes {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { continue }
            if let string = value as? String {
                results.append(string)
            } else if let attributed = value as? NSAttributedString {
                results.append(attributed.string)
            } else if let strings = value as? [String] {
                results.append(contentsOf: strings)
            }
        }
        return results
    }

    private static func primaryTextValues(of element: AXUIElement) -> [String] {
        stringValues(of: element, attributes: [kAXValueAttribute, kAXTitleAttribute])
    }

    private static func stringValues(of element: AXUIElement, attributes: [String]) -> [String] {
        var results: [String] = []
        for attribute in attributes {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { continue }
            if let string = value as? String {
                results.append(string)
            } else if let attributed = value as? NSAttributedString {
                results.append(attributed.string)
            } else if let strings = value as? [String] {
                results.append(contentsOf: strings)
            }
        }
        return results
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func isInteractiveChrome(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return false }
        return [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole,
                kAXMenuButtonRole, kAXTabGroupRole, kAXToolbarRole].contains(role)
    }

    private static func isSuppressedChrome(_ element: AXUIElement) -> Bool {
        let suppressedRoles: Set<String> = [
            kAXMenuBarRole, kAXMenuBarItemRole, kAXMenuRole, kAXMenuItemRole
        ]
        var current: AXUIElement? = element
        for _ in 0..<8 {
            guard let item = current else { break }
            if let itemRole = role(of: item), suppressedRoles.contains(itemRole) { return true }
            current = elementAttribute(item, kAXParentAttribute)
        }
        return false
    }

    private static func containsHan(_ value: String) -> Bool {
        value.unicodeScalars.contains { (0x4E00...0x9FFF).contains(Int($0.value)) }
    }

    static func normalize(_ value: String) -> String? {
        let text = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...1200).contains(text.count) else { return nil }
        guard text.range(of: "[A-Za-z]", options: .regularExpression) != nil else { return nil }
        let hanCount = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count
        guard hanCount * 3 < text.count else { return nil }
        let protectedHostBrands: Set<String> = ["codex", "chatgpt", "openai"]
        if protectedHostBrands.contains(text.lowercased()) { return nil }
        return text
    }
}

private enum OCRTextReader {
    struct Line {
        let text: String
        let frame: CGRect
    }

    static func target(at point: CGPoint) async -> AXTextReader.Target? {
        guard CGPreflightScreenCaptureAccess() else { return nil }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ), let display = content.displays.first(where: { $0.frame.contains(point) }) ?? content.displays.first else {
            return nil
        }

        let displayFrame = display.frame
        let captureWidth = min(displayFrame.width, 1_400)
        let captureHeight = min(displayFrame.height, 500)
        let originX = max(displayFrame.minX, min(point.x - captureWidth / 2, displayFrame.maxX - captureWidth))
        let originY = max(displayFrame.minY, min(point.y - captureHeight / 2, displayFrame.maxY - captureHeight))
        let globalCaptureRect = CGRect(x: originX, y: originY, width: captureWidth, height: captureHeight)
        let localCaptureRect = globalCaptureRect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = localCaptureRect
        configuration.width = max(1, Int(localCaptureRect.width * 2))
        configuration.height = max(1, Int(localCaptureRect.height * 2))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) else { return nil }

        let lines = recognizedLines(in: image, screenRect: globalCaptureRect)
        return target(from: lines, at: point)
    }

    static func target(in image: CGImage, at point: CGPoint) -> AXTextReader.Target? {
        target(from: recognizedLines(in: image), at: point)
    }

    private static func target(from lines: [Line], at point: CGPoint) -> AXTextReader.Target? {
        guard !lines.isEmpty else { return nil }
        let anchor = lines
            .filter { $0.frame.insetBy(dx: -10, dy: -10).contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let anchor else { return nil }

        let sorted = lines.sorted {
            if abs($0.frame.minY - $1.frame.minY) < 4 { return $0.frame.minX < $1.frame.minX }
            return $0.frame.minY < $1.frame.minY
        }
        guard let anchorIndex = sorted.firstIndex(where: {
            $0.text == anchor.text && abs($0.frame.minX - anchor.frame.minX) < 1 && abs($0.frame.minY - anchor.frame.minY) < 1
        }) else { return nil }

        var lower = anchorIndex
        var upper = anchorIndex
        while lower > 0, related(sorted[lower - 1], sorted[lower]) { lower -= 1 }
        while upper + 1 < sorted.count, related(sorted[upper], sorted[upper + 1]) { upper += 1 }
        let paragraph = Array(sorted[lower...upper])
        let joined = paragraph.map(\.text).joined(separator: " ")
        guard let normalized = AXTextReader.normalize(joined) else { return nil }
        let region = paragraph.dropFirst().reduce(paragraph[0].frame) { $0.union($1.frame) }.insetBy(dx: -12, dy: -10)
        return AXTextReader.Target(text: normalized, textFrame: anchor.frame, hoverRegion: region)
    }

    static func recognizedLines(in image: CGImage, screenRect: CGRect? = nil) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return [] }

        let targetRect = screenRect ?? CGRect(x: 0, y: 0, width: image.width, height: image.height)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  let normalized = AXTextReader.normalize(candidate.string) else { return nil }
            let box = observation.boundingBox
            let frame = CGRect(
                x: targetRect.minX + box.minX * targetRect.width,
                y: targetRect.minY + (1 - box.maxY) * targetRect.height,
                width: box.width * targetRect.width,
                height: box.height * targetRect.height
            )
            return Line(text: normalized, frame: frame)
        }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private static func related(_ first: Line, _ second: Line) -> Bool {
        let verticalGap = max(0, second.frame.minY - first.frame.maxY)
        let allowedGap = max(30, max(first.frame.height, second.frame.height) * 1.8)
        let overlap = first.frame.intersection(second.frame).width
        let overlapRatio = overlap / max(1, min(first.frame.width, second.frame.width))
        return verticalGap <= allowedGap && (overlapRatio >= 0.25 || abs(first.frame.minX - second.frame.minX) <= 90)
    }
}

@main
@MainActor
final class HoverTranslatorApp: NSObject, NSApplicationDelegate {
    private let model = HoverTranslatorModel(codexOnly: !CommandLine.arguments.contains("--all-apps"))
    private var panel: NSPanel?
    private var hostingView: NSHostingView<TranslationTooltip>?
    private var lastAnchorPoint: NSPoint?
    private var statusItem: NSStatusItem?

    static func main() {
        if CommandLine.arguments.contains("--check-accessibility") {
            print(AXIsProcessTrusted() ? "granted" : "missing")
            return
        }
        if CommandLine.arguments.contains("--check-plugin-surface") {
            print(AXTextReader.isPluginSurfaceVisible() ? "visible" : "hidden")
            return
        }
        if CommandLine.arguments.contains("--debug-surface-signals") {
            let taskChrome = AXTextReader.containsCodexExactText(anyOf: ["任务操作", "Task actions"])
            let directory = AXTextReader.containsCodexText(anyOf: [
                "浏览插件或技能", "Browse plugins or skills", "搜索插件", "Search plugins"
            ])
            let detailAction = AXTextReader.containsCodexTopAction(anyOf: [
                "立即试用", "Try now", "安装插件", "Install plugin", "安装", "Install"
            ])
            let breadcrumb = AXTextReader.containsCodexPluginBreadcrumb()
            print("task-chrome\t\(taskChrome)")
            print("directory\t\(directory)")
            print("detail-action\t\(detailAction)")
            print("breadcrumb\t\(breadcrumb)")
            print("surface\t\(AXTextReader.isPluginSurfaceVisible())")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--classify-plugin-title"),
           CommandLine.arguments.indices.contains(index + 1) {
            print(AXTextReader.isPlausiblePluginTitle(CommandLine.arguments[index + 1]) ? "plugin-title" : "host-label")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--normalize-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            print(AXTextReader.normalize(CommandLine.arguments[index + 1]) ?? "rejected")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--tooltip-size"),
           CommandLine.arguments.indices.contains(index + 2) {
            _ = NSApplication.shared
            let previewModel = HoverTranslatorModel()
            previewModel.sourceText = CommandLine.arguments[index + 1]
            previewModel.translatedText = CommandLine.arguments[index + 2]
            let preview = NSHostingView(rootView: TranslationTooltip(model: previewModel))
            preview.layoutSubtreeIfNeeded()
            let size = preview.fittingSize
            print("\(Int(ceil(size.width)))\t\(Int(ceil(size.height)))")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ocr-image"),
           CommandLine.arguments.indices.contains(index + 1),
           let image = NSImage(contentsOfFile: CommandLine.arguments[index + 1]),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            for line in OCRTextReader.recognizedLines(in: cgImage) {
                print("\(line.frame.minX)\t\(line.frame.minY)\t\(line.frame.width)\t\(line.frame.height)\t\(line.text)")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--ocr-image-point"),
           CommandLine.arguments.indices.contains(index + 3),
           let x = Double(CommandLine.arguments[index + 2]),
           let y = Double(CommandLine.arguments[index + 3]),
           let image = NSImage(contentsOfFile: CommandLine.arguments[index + 1]),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            if let target = OCRTextReader.target(in: cgImage, at: CGPoint(x: x, y: y)) {
                print("found\t\(target.hoverRegion.minX)\t\(target.hoverRegion.minY)\t\(target.hoverRegion.width)\t\(target.hoverRegion.height)\t\(target.text)")
            } else {
                print("not-found")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--find-codex-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            let needle = CommandLine.arguments[index + 1]
            if let match = AXTextReader.findCodexText(needle) {
                print("found\t\(match.frame.origin.x)\t\(match.frame.origin.y)\t\(match.frame.width)\t\(match.frame.height)\t\(match.text)")
            } else {
                print("not-found")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--find-app-text"),
           CommandLine.arguments.indices.contains(index + 2) {
            let bundleID = CommandLine.arguments[index + 1]
            let needle = CommandLine.arguments[index + 2]
            if let match = AXTextReader.findApplicationText(bundleID: bundleID, needle: needle) {
                print("found\t\(match.frame.origin.x)\t\(match.frame.origin.y)\t\(match.frame.width)\t\(match.frame.height)\t\(match.text)")
            } else {
                print("not-found")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--hover-app-text"),
           CommandLine.arguments.indices.contains(index + 2) {
            let bundleID = CommandLine.arguments[index + 1]
            let needle = CommandLine.arguments[index + 2]
            guard let match = AXTextReader.findApplicationText(bundleID: bundleID, needle: needle) else {
                print("not-found")
                return
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
            Thread.sleep(forTimeInterval: 0.20)
            let center = CGPoint(x: match.frame.midX, y: match.frame.midY)
            CGWarpMouseCursorPosition(center)
            print("hovered\t\(center.x)\t\(center.y)\t\(match.text)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--press-app-text"),
           CommandLine.arguments.indices.contains(index + 2) {
            let bundleID = CommandLine.arguments[index + 1]
            let needle = CommandLine.arguments[index + 2]
            guard let match = AXTextReader.findApplicationText(bundleID: bundleID, needle: needle) else {
                print("not-found")
                return
            }
            if let press = AXTextReader.pressNearestAction(from: match.element) {
                print("pressed\t\(press.depth)\t\(press.result.rawValue)\t\(match.text)")
            } else {
                print("no-press-action\t\(match.text)")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--move-pointer-offset"),
           CommandLine.arguments.indices.contains(index + 2),
           let deltaX = Double(CommandLine.arguments[index + 1]),
           let deltaY = Double(CommandLine.arguments[index + 2]) {
            let current = CGEvent(source: nil)?.location ?? .zero
            let target = CGPoint(x: current.x + deltaX, y: current.y + deltaY)
            CGWarpMouseCursorPosition(target)
            print("moved\t\(target.x)\t\(target.y)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--hover-codex-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            let needle = CommandLine.arguments[index + 1]
            guard let match = AXTextReader.findCodexText(needle) else {
                print("not-found")
                return
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.activate()
            Thread.sleep(forTimeInterval: 0.20)
            let center = CGPoint(x: match.frame.midX, y: match.frame.midY)
            CGWarpMouseCursorPosition(center)
            print("hovered\t\(center.x)\t\(center.y)\t\(match.text)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--click-codex-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            let needle = CommandLine.arguments[index + 1]
            guard let match = AXTextReader.findCodexText(needle) else {
                print("not-found")
                return
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.activate()
            Thread.sleep(forTimeInterval: 0.20)
            let center = CGPoint(x: match.frame.midX, y: match.frame.midY)
            CGWarpMouseCursorPosition(center)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left)?.post(tap: .cghidEventTap)
            print("clicked\t\(center.x)\t\(center.y)\t\(match.text)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--press-codex-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            let needle = CommandLine.arguments[index + 1]
            guard let match = AXTextReader.findCodexText(needle) else {
                print("not-found")
                return
            }
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").first?.activate()
            if let press = AXTextReader.pressNearestAction(from: match.element) {
                print("pressed\t\(press.depth)\t\(press.result.rawValue)\t\(match.text)")
            } else {
                print("no-press-action\t\(match.text)")
            }
            return
        }
        if CommandLine.arguments.contains("--list-codex-texts") {
            for (text, frame) in AXTextReader.listCodexTexts(limit: 500) {
                if let frame {
                    print("\(frame.origin.x)\t\(frame.origin.y)\t\(frame.width)\t\(frame.height)\t\(text)")
                } else {
                    print("-\t-\t-\t-\t\(text)")
                }
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--find-helper-text"),
           CommandLine.arguments.indices.contains(index + 1) {
            let needle = CommandLine.arguments[index + 1]
            if let match = AXTextReader.findApplicationText(bundleID: "local.codex.bilingual-hover", needle: needle) {
                print("found\t\(match.frame.origin.x)\t\(match.frame.origin.y)\t\(match.frame.width)\t\(match.frame.height)\t\(match.text)")
            } else {
                print("not-found")
            }
            return
        }
        if CommandLine.arguments.contains("--sample-pointer") {
            let quartz = CGEvent(source: nil)?.location ?? .zero
            let cocoa = NSEvent.mouseLocation
            let text = AXTextReader.target(
                at: quartz,
                codexOnly: true,
                helperBundleID: "local.codex.bilingual-hover"
            )?.text ?? "not-found"
            print("quartz\t\(quartz.x)\t\(quartz.y)")
            print("cocoa\t\(cocoa.x)\t\(cocoa.y)")
            print("text\t\(text)")
            return
        }
        let app = NSApplication.shared
        let delegate = HoverTranslatorApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePanel()
        configureStatusItem()
        model.onShow = { [weak self] point in self?.showPanel(near: point) }
        model.onHide = { [weak self] in self?.hidePanel() }
        model.onLayoutChange = { [weak self] in
            DispatchQueue.main.async { self?.resizePanelToFit() }
        }
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    private func configurePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.ignoresMouseEvents = true
        // This accessory app stays inactive while Codex is frontmost. Native menu
        // suppression is handled by the pointer/AX checks in the polling loop.
        panel.hidesOnDeactivate = false
        let hostingView = NSHostingView(rootView: TranslationTooltip(model: model))
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = "译"
        item.button?.toolTip = "Codex 悬停翻译"

        let menu = NSMenu()
        let enabled = NSMenuItem(title: "启用悬停翻译", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabled.target = self
        enabled.state = .on
        menu.addItem(enabled)

        let codexOnly = NSMenuItem(title: "仅在 Codex 插件目录和详情页中翻译", action: #selector(toggleCodexOnly(_:)), keyEquivalent: "")
        codexOnly.target = self
        codexOnly.state = model.codexOnly ? .on : .off
        menu.addItem(codexOnly)

        menu.addItem(.separator())
        let permissions = NSMenuItem(title: "打开辅助功能设置…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)

        let screenCapture = NSMenuItem(title: "打开屏幕录制设置（详情页 OCR）…", action: #selector(openScreenCaptureSettings), keyEquivalent: "")
        screenCapture.target = self
        menu.addItem(screenCapture)

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        model.setEnabled(!model.enabled)
        sender.state = model.enabled ? .on : .off
    }

    @objc private func toggleCodexOnly(_ sender: NSMenuItem) {
        model.codexOnly.toggle()
        sender.state = model.codexOnly ? .on : .off
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openScreenCaptureSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showPanel(near mousePoint: NSPoint) {
        guard let panel else { return }
        lastAnchorPoint = mousePoint
        resizePanelToFit()
        positionPanel(near: mousePoint)
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        lastAnchorPoint = nil
        panel?.orderOut(nil)
    }

    private func resizePanelToFit() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fittingHeight = ceil(hostingView.fittingSize.height)
        let height = min(190, max(58, fittingHeight))
        guard abs(panel.frame.height - height) >= 0.5 else { return }
        panel.setContentSize(NSSize(width: 420, height: height))
        if panel.isVisible, let lastAnchorPoint {
            positionPanel(near: lastAnchorPoint)
        }
    }

    private func positionPanel(near mousePoint: NSPoint) {
        guard let panel else { return }
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePoint) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = mousePoint.x + 18
        var y = mousePoint.y - size.height - 14
        if x + size.width > visible.maxX { x = mousePoint.x - size.width - 18 }
        if y < visible.minY { y = mousePoint.y + 18 }
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        y = max(visible.minY + 8, min(y, visible.maxY - size.height - 8))

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
final class HoverTranslatorModel: ObservableObject {
    @Published var sourceText = "" {
        didSet { onLayoutChange?() }
    }
    @Published var translatedText = "" {
        didSet { onLayoutChange?() }
    }
    @Published var configuration: TranslationSession.Configuration?

    var enabled = true
    var codexOnly: Bool
    var onShow: ((NSPoint) -> Void)?
    var onHide: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    private var timer: Timer?
    private var candidateText = ""
    private var candidateRegion: CGRect?
    private var candidateSince = Date.distantPast
    private var activeText = ""
    private var activeRegion: CGRect?
    private var pluginSurfaceVisible = false
    private var nextPluginSurfaceCheck = Date.distantPast
    private var panelVisible = false
    private var showCount = 0
    private var hideCount = 0
    private var ocrAnchorPoint: CGPoint?
    private var ocrAnchorSince = Date.distantPast
    private var ocrInFlight = false
    private var ocrGeneration = 0
    private var wroteScreenCaptureMissing = false

    private let exactTranslations: [String: String] = [
        "Control Mac apps from ChatGPT": "通过 ChatGPT 控制 Mac 应用",
        "Control Chrome with ChatGPT": "通过 ChatGPT 控制 Chrome",
        "Create and edit spreadsheet files": "创建和编辑电子表格文件",
        "Create and edit presentations": "创建和编辑演示文稿",
        "Triage PRs, issues, CI, and publish code": "分类处理拉取请求、问题和持续集成，并发布代码",
        "Manage Google Calendar events": "管理 Google 日历事件",
        "Mac Computer Use lets ChatGPT use any app on your computer, including your web browsers and files you allow it to access. It may take screenshots or page content while working. You stay in control: you choose which apps to allow ChatGPT to access, you can stop actions at any time, and control whether we use screenshots for training.": "Mac 版 Computer Use 可让 ChatGPT 使用您电脑上的任何应用，包括您允许其访问的网页浏览器和文件。工作期间，它可能会截取屏幕截图或读取页面内容。控制权始终在您手中：您可以选择允许 ChatGPT 访问哪些应用，随时停止操作，并控制我们是否使用截图进行训练。",
        "Computer Use": "电脑控制",
        "Spreadsheets": "电子表格",
        "Presentations": "演示文稿",
        "Data Analytics": "数据分析"
    ]

    init(codexOnly: Bool = true) {
        self.codexOnly = codexOnly
    }

    func start() {
        requestAccessibilityPermission()
        writeDebug(event: "started", text: "")
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPointer() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { resetCandidate() }
    }

    func translate(using session: TranslationSession) async {
        let requestedText = sourceText
        guard !requestedText.isEmpty else { return }
        do {
            let response = try await session.translate(requestedText)
            guard sourceText == requestedText else { return }
            translatedText = response.targetText
            writeDebug(event: "translated", text: requestedText)
        } catch {
            guard sourceText == requestedText else { return }
            translatedText = "暂时无法翻译：\(error.localizedDescription)"
            writeDebug(event: "translation-error", text: requestedText)
        }
    }

    private func pollPointer() {
        guard enabled else { return }
        guard AXIsProcessTrusted() else {
            hidePanel()
            return
        }

        let now = Date()
        if codexOnly && now >= nextPluginSurfaceCheck {
            pluginSurfaceVisible = AXTextReader.isPluginSurfaceVisible()
            nextPluginSurfaceCheck = now.addingTimeInterval(0.40)
        }
        guard !codexOnly || pluginSurfaceVisible else {
            resetOCRTracking()
            resetCandidate()
            return
        }

        guard let quartzPoint = CGEvent(source: nil)?.location else {
            resetCandidate()
            return
        }

        // Native menu tracking sits above the Codex content while the underlying
        // plugin page remains visible. Clear any stale tooltip before considering
        // the previous active hover region and do not run OCR against menus.
        if AXTextReader.shouldSuppressTranslation(at: quartzPoint, helperBundleID: Bundle.main.bundleIdentifier) {
            resetCandidate()
            return
        }

        // Once a card/row has activated, pointer motion inside that region must not
        // retrigger, reposition, or briefly hide the tooltip.
        if let activeRegion, activeRegion.insetBy(dx: -6, dy: -6).contains(quartzPoint) {
            return
        }

        if activeRegion != nil {
            activeText = ""
            self.activeRegion = nil
            hidePanel()
        }

        guard let target = accessibilityTarget(at: quartzPoint) else {
            pollOCRFallback(at: quartzPoint, now: now)
            return
        }
        resetOCRTracking()

        if target.text != candidateText || !sameRegion(target.hoverRegion, candidateRegion) {
            candidateText = target.text
            candidateRegion = target.hoverRegion
            candidateSince = now
            writeDebug(event: "candidate", text: target.text)
            return
        }

        guard now.timeIntervalSince(candidateSince) >= 0.20 else { return }
        guard activeRegion == nil else { return }

        show(target: target)
    }

    private func show(target: AXTextReader.Target) {
        guard activeRegion == nil else { return }

        activeText = target.text
        activeRegion = target.hoverRegion
        sourceText = target.text
        translatedText = exactTranslations[target.text] ?? "正在翻译…"
        panelVisible = true
        showCount += 1
        writeDebug(event: "shown", text: target.text)
        onShow?(NSEvent.mouseLocation)

        if exactTranslations[target.text] == nil {
            if configuration == nil {
                configuration = .init(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "zh-Hans")
                )
            } else {
                configuration?.invalidate()
            }
        }
    }

    private func pollOCRFallback(at point: CGPoint, now: Date) {
        guard !codexOnly || AXTextReader.isPointInCodex(point, helperBundleID: Bundle.main.bundleIdentifier) else {
            resetCandidate()
            return
        }
        guard CGPreflightScreenCaptureAccess() else {
            resetCandidate()
            if !wroteScreenCaptureMissing {
                wroteScreenCaptureMissing = true
                writeDebug(event: "screen-capture-permission-required", text: "")
            }
            return
        }
        wroteScreenCaptureMissing = false

        if let anchor = ocrAnchorPoint, hypot(point.x - anchor.x, point.y - anchor.y) <= 8 {
            guard now.timeIntervalSince(ocrAnchorSince) >= 0.20, !ocrInFlight else { return }
        } else {
            resetCandidate()
            ocrAnchorPoint = point
            ocrAnchorSince = now
            return
        }

        ocrInFlight = true
        let requestedPoint = point
        let requestedGeneration = ocrGeneration
        let requestedSurfaceTitle = codexOnly ? AXTextReader.codexTopSurfaceTitle() : nil
        Task { [weak self] in
            let target = await OCRTextReader.target(at: requestedPoint)
            guard let self else { return }
            self.ocrInFlight = false
            guard self.ocrGeneration == requestedGeneration,
                  self.enabled, !self.codexOnly || self.pluginSurfaceVisible,
                  let currentPoint = CGEvent(source: nil)?.location,
                  !self.codexOnly || AXTextReader.isPointInCodex(currentPoint, helperBundleID: Bundle.main.bundleIdentifier),
                  hypot(currentPoint.x - requestedPoint.x, currentPoint.y - requestedPoint.y) <= 10 else { return }
            if self.codexOnly {
                guard AXTextReader.codexTopSurfaceTitle() == requestedSurfaceTitle else { return }
            }
            guard let target else {
                self.ocrAnchorSince = Date()
                return
            }
            self.ocrAnchorPoint = nil
            self.show(target: target)
        }
    }

    private func resetOCRTracking() {
        ocrGeneration &+= 1
        ocrAnchorPoint = nil
        ocrAnchorSince = .distantPast
    }

    private func resetCandidate() {
        if !candidateText.isEmpty { writeDebug(event: "cleared", text: candidateText) }
        candidateText = ""
        candidateRegion = nil
        activeText = ""
        activeRegion = nil
        resetOCRTracking()
        hidePanel()
    }

    private func hidePanel() {
        guard panelVisible else { return }
        panelVisible = false
        hideCount += 1
        writeDebug(event: "hidden", text: activeText)
        onHide?()
    }

    private func sameRegion(_ left: CGRect, _ right: CGRect?) -> Bool {
        guard let right else { return false }
        return abs(left.minX - right.minX) < 1 &&
            abs(left.minY - right.minY) < 1 &&
            abs(left.width - right.width) < 1 &&
            abs(left.height - right.height) < 1
    }

    private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func writeDebug(event: String, text: String) {
        let payload: [String: Any] = [
            "event": event,
            "timestamp": Date().timeIntervalSince1970,
            "accessibility": AXIsProcessTrusted(),
            "screenCapture": CGPreflightScreenCaptureAccess(),
            "showCount": showCount,
            "hideCount": hideCount,
            "panelVisible": panelVisible
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) else { return }
        try? data.write(to: URL(fileURLWithPath: "/tmp/codex-hover-translator-state.json"), options: .atomic)
    }

    private func accessibilityTarget(at point: CGPoint) -> AXTextReader.Target? {
        AXTextReader.target(at: point, codexOnly: codexOnly, helperBundleID: Bundle.main.bundleIdentifier)
    }
}

struct TranslationTooltip: View {
    @ObservedObject var model: HoverTranslatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.translatedText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.sourceText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .translationTask(model.configuration) { session in
            await model.translate(using: session)
        }
    }
}
