#  SwiftUI-CellFrameInLazyVGrid

This project explores how to track appearance (onAppear), disappearance (onDisappear), and frames of items in SwiftUI's `LazyVGrid`.

Tracking is done using a combination of `CellFrameTracker` and `CellFrameTracking ViewModifier`.

## Screenshots

![iPadOS 18](https://github.com/tomaskraina/SwiftUI-CellFrameTrackingInScrollView/blob/main/Screenshot%20-%20iPadOS%2018.png)

![macOS 15](https://github.com/tomaskraina/SwiftUI-CellFrameTrackingInScrollView/blob/main/Screenshot%20-%20macOS%2025.png)

## Usage:

```swift
struct ContentView: View {

    @State private var cellFrameTracker: CellFrameTracker<GridCellItem.ID>
    let items: [GridCellItem]
    let coordinateSpaceName: NamedCoordinateSpace = .named("GridContainer")

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(self.items) { item in
                    GridCellItemView(item: item)
                        .trackCellFrame(id: item, in: self.coordinateSpaceName.coordinateSpace, using: self.cellFrameTracker)
                }
            }
        }
        .coordinateSpace(self.coordinateSpaceName)
    }
}
```

### `CellFrameTracker`

```swift
@Observable
final class CellFrameTracker<ItemID: Hashable> {

    private(set) var cellFrames: [ItemID: CGRect] = [:]
    var visibleCellIDs: Set<ItemID> = []

    /// Returns frames only for documents that are currently visible (appeared but not disappeared)
    var visibleCellFrames: [ItemID: CGRect] {
        self.cellFrames.filter { self.visibleCellIDs.contains($0.key) }
    }

    func trackAppeared(id: ItemID) {
        self.visibleCellIDs.insert(id)
    }

    func trackDisappeared(id: ItemID) {
        self.visibleCellIDs.remove(id)
    }

    func trackCellFrame(_ frame: CGRect, for id: ItemID) {
        self.cellFrames[id] = frame
    }
}
``` 

### `CellFrameTracking`

```swift
extension View {

    func trackCellFrame<ItemID: Hashable>(id itemID: ItemID, in coordinateSpace: CoordinateSpace, using tracker: CellFrameTracker<ItemID>) -> some View {
        self.modifier(CellFrameTracking(itemID: itemID, coordinateSpace: coordinateSpace, tracker: tracker))
    }
}

private struct CellFrameTracking<ItemID: Hashable>: ViewModifier {

    let itemID: ItemID
    let coordinateSpace: CoordinateSpace
    let tracker: CellFrameTracker<ItemID>
    let visibilityThreshold: CGFloat = 0.01 // 0.01 = 1% of visible height

    func body(content: Content) -> some View {
        content
            .onFrameChange(coordinateSpace: self.coordinateSpace) {
                self.tracker.trackCellFrame($0, for: self.itemID)
            }
            // Compared to 'onDisappear', 'onScrollVisibilityChange' report precisely when the cells go offscreen when scrolling.
            // However, 'onScrollVisibilityChange' is not called when cells are reloaded due to grid items changing.
            .onScrollVisibilityChange(threshold: self.visibilityThreshold) { isVisible in
                print("CellFrameTracking.onScrollVisibilityChange: isVisible=\(isVisible) id=\(itemID)")
                if isVisible {
                    self.tracker.trackAppeared(id: self.itemID)
                } else {
                    self.tracker.trackDisappeared(id: self.itemID)
                }
            }
            .onAppear {
                print("CellFrameTracking.onAppear: id=\(itemID)")
                self.tracker.trackAppeared(id: self.itemID)
            }
            // When scrolling ScrollView/LazyVGrid, 'onDisappear' is called not exactly when the cells move offscreen
            // but later at a point where the the cells are probably recycled, just before new row of cells appear on screen.
            // So 'onDisappear' doesn't accurately represent the moment the cells move offscreen.
            .onDisappear {
                print("CellFrameTracking.onDisappear: id=\(itemID)")
                self.tracker.trackDisappeared(id: self.itemID)
            }
    }
}
```
