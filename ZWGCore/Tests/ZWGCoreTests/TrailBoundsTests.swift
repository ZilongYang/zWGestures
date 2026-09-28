import CoreGraphics
import Testing

@testable import ZWGCore

@Suite("叠加层：轨迹失效区域")
struct TrailBoundsTests {
    @Test("空点集没有区域 —— 必须与「零尺寸矩形」区分开")
    func emptyPointsHasNoRect() {
        #expect(TrailBounds.of(points: [], lineWidth: 5) == nil)
        #expect(TrailBounds.union(nil, nil) == nil)
    }

    @Test("单个点也有一块区域（圆头笔画）")
    func singlePointIsNotDegenerate() throws {
        let rect = try #require(TrailBounds.of(points: [CGPoint(x: 10, y: 20)], lineWidth: 5))
        // 半径 2.5 + 1 像素抗锯齿余量，所以是 7×7，中心在 (10,20)。
        #expect(rect.width == 7)
        #expect(rect.height == 7)
        #expect(rect.midX == 10)
        #expect(rect.midY == 20)
    }

    @Test("折线的包围盒被线宽撑开，且覆盖所有点")
    func polylineIsCovered() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: -50)]
        let rect = try #require(TrailBounds.of(points: points, lineWidth: 5))
        for point in points {
            #expect(rect.contains(point), "\(point) 应在失效区内")
        }
        // 线段端点之外还要留半个线宽以上。
        #expect(rect.minX <= -3.5)
        #expect(rect.maxX >= 103.5)
        #expect(rect.minY <= -53.5)
        #expect(rect.maxY >= 3.5)
    }

    @Test("合并：nil 视为「什么都没有」，两个区域取并集")
    func unionHandlesNil() throws {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 20, y: 20, width: 5, height: 5)
        #expect(TrailBounds.union(nil, a) == a)
        #expect(TrailBounds.union(a, nil) == a)
        let merged = try #require(TrailBounds.union(a, b))
        #expect(merged == a.union(b))
        #expect(merged.contains(CGPoint(x: 5, y: 5)))
        #expect(merged.contains(CGPoint(x: 22, y: 22)))
    }

    @Test("线宽越粗区域越大（否则描边边缘会被留在屏幕上）")
    func widerLineCoversMore() throws {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        let thin = try #require(TrailBounds.of(points: points, lineWidth: 1))
        let thick = try #require(TrailBounds.of(points: points, lineWidth: 20))
        #expect(thick.width > thin.width)
        #expect(thick.height > thin.height)
    }
}
