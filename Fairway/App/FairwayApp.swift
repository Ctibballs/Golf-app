import SwiftUI
import GolfKit

@main
struct FairwayApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Fairway — \(DemoData.golfCourse.name)")
        }
    }
}
