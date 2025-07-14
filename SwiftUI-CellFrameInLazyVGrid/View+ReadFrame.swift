//
//  Copyright (c) 2021 IdeasOnCanvas GmbH. All rights reserved.
//

import Foundation
import SwiftUI


/// Modifier to get notified about frame changes of a SwiftUI View (in .global coordinate space)
public struct ReadFrame: ViewModifier {

    // MARK: - Properties

    public var coordinateSpace: CoordinateSpace = .global
    public let onChange: (CGRect) -> Void

    // MARK: - ViewModifier

    public func body(content: Content) -> some View {
        // In order to read a View's frame in runtime, we need to add GeometryReader as View's background or overlay.
        // Adding it as a background worked but only for reading the initial value and further changes were not observed (iOS 15.0).
        content
            .overlay(
                GeometryReader { proxy in
                    // We need to pass the value from within a @ViewBuilder closure somehow and the current best practise (iOS 15) is to use Color.clear and PreferenceKey.
                    Color.clear.preference(key: ReadFramePreferenceKey.self, value: proxy.frame(in: self.coordinateSpace))
                }
            )
            .onPreferenceChange(ReadFramePreferenceKey.self) {
                self.onChange($0)
            }
    }
}

// MARK: - View Convenience

public extension View {

    /// Observe view's frame in the provided coordinate space
    ///
    /// If no coordinate space is provided, `.global` is used.
    func onFrameChange(coordinateSpace: CoordinateSpace = .global, _ onChange: @escaping (CGRect) -> Void) -> some View {
        self.modifier(ReadFrame(coordinateSpace: coordinateSpace, onChange: onChange))
    }
}

// MARK: - Private

private struct ReadFramePreferenceKey: PreferenceKey {

    static let defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
