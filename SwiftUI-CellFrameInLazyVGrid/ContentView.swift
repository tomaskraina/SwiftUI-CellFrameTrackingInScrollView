//
//  ContentView.swift
//  SwiftUI-CellFrameInLazyVGrid
//
//  Created by Tom Kraina on 14.07.2025.
//

import Observation
import SwiftUI


struct ContentView: View {

    @State private var sidebarItems: [SidebarItem] = .make(count: 5)
    @State private var selectedSidebarItem: SidebarItem?
    @State private var displayedItems: [GridCellItem]?
    @State private var cellFrameTracker: CellFrameTracker<GridCellItem.ID> = .init()
    @State private var showInspector = false

    var body: some View {
        NavigationSplitView {
            List(self.sidebarItems, selection: self.$selectedSidebarItem) { item in
                Text("Items \(item.gridItemRange.lowerBound)+")
            }
            .task(id: self.selectedSidebarItem) {
                self.displayedItems = self.selectedSidebarItem?.gridCellItems
            }
            .navigationTitle("Ranges")
        } detail: {
            NavigationStack {
                GridContainer(items: self.displayedItems ?? [], cellFrameTracker: self.cellFrameTracker)
                    .inspector(isPresented: self.$showInspector) {
                        InspectorView(cellFrameTracker: self.cellFrameTracker)
                    }
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button("Print visible cells", systemImage: "printer") {
                                print("# Visible cell and frames:")
                                let keys = self.cellFrameTracker.visibleCellFrames.keys.sorted { $0.index < $1.index }
                                for key in keys {
                                    print("cell id=\(key.index) frame=\(self.cellFrameTracker.visibleCellFrames[key]?.debugDescription ?? "nil")")
                                }
                            }
                        }
                        ToolbarItem(placement: .automatic) {
                            Button("Toggle Inspector", systemImage: "sidebar.right") {
                                self.showInspector.toggle()
                            }
                        }
                    }
            }
        }
    }
}

// MARK: - GridContainer

struct GridContainer: View {

    let items: [GridCellItem]
    let cellFrameTracker: CellFrameTracker<GridCellItem.ID>
    let coordinateSpaceName: NamedCoordinateSpace = .named("GridContainer")

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                ForEach(self.items) { item in
                    GridCellItemView(item: item)
                        .trackCellFrame(id: item, in: self.coordinateSpaceName.coordinateSpace, using: self.cellFrameTracker)
                }
            }
            .padding()
        }
        .coordinateSpace(self.coordinateSpaceName)
    }
}

// MARK: - GridCellItemView

struct GridCellItemView: View {

    let item: GridCellItem

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 100, height: 100)

            Text("\(item.index)")
                .font(.title2)
                .fontWeight(.medium)
        }
    }
}

// MARK: - SidebarItem & GridCellItem

struct GridCellItem: Identifiable, Hashable, Equatable {

    let index: Int
    var id: Self { self }
}

struct SidebarItem: Identifiable, Hashable, Equatable {

    let index: Int
    var id: Self { self }

    var gridItemRange: Range<Int> {
        (index * 100)..<((index * 100) + 100)
    }

    var gridCellItems: [GridCellItem] {
        self.gridItemRange.map { GridCellItem(index: $0) }
    }

    static func make(count: Int) -> [Self] {
        (0..<count).map { SidebarItem(index: $0) }
    }
}

extension Array where Element == SidebarItem {

    static func make(count: Int) -> Self {
        SidebarItem.make(count: count)
    }
}

// MARK: CellFrameTracker

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

// MARK: - CellFrameTracking

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

// MARK: - InspectorView

struct InspectorView: View {

    let cellFrameTracker: CellFrameTracker<GridCellItem.ID>

    var body: some View {
        List {
            ForEach(self.sortedVisibleCells, id: \.key) { cell in
                HStack(alignment: .bottom, spacing: 4) {
                    Text("Item \(cell.key.index)")
                        .fontWeight(.medium)
                    Text(cell.value.debugDescription)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(.vertical, 2)
            }
        }
    }

    private var sortedVisibleCells: [(key: GridCellItem.ID, value: CGRect)] {
        self.cellFrameTracker.visibleCellFrames.sorted { $0.key.index < $1.key.index }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .frame(width: 550, height: 400)
}
