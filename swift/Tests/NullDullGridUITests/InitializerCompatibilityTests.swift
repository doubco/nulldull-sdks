import NullDullGrid
import NullDullGridUI
import XCTest

@available(iOS 16, macOS 13, tvOS 16, *)
@MainActor
final class InitializerCompatibilityTests: XCTestCase {
  func testSwift030InitializerReferencesCompile() {
    _ = PublicGridPage.init(summary:document:assets:)
    _ = GridView.init(document:resolveAsset:width:initialWidth:layout:breakpointId:theme:customNodes:embed:embedLoading:messages:label:dynamicType:)
    _ = PublishedGridPageView.init(page:width:initialWidth:theme:customNodes:embed:embedLoading:messages:dynamicType:)
  }
}
