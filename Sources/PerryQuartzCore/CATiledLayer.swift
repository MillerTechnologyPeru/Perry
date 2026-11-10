import CPerryGeometry
import PerryObjCInterop

// CATiledLayer: a layer that draws its content in tiles, at levels of
// detail, as a map or a large image needs. It keeps its tile size and
// levels, and draws its content as an ordinary layer does, in one piece.

@ObjCClass("CATiledLayer")
open class CATiledLayer: CALayer {
    var tileSizeValue = CGSize(width: 256, height: 256)
    var levels = 1
    var levelsBias = 0

    @ObjCMethod("tileSize") func tileSize() -> CGSize { tileSizeValue }
    @ObjCMethod("setTileSize:") func setTileSize(_ size: CGSize) { tileSizeValue = size }
    @ObjCMethod("levelsOfDetail") func levelsOfDetail() -> Int { levels }
    @ObjCMethod("setLevelsOfDetail:") func setLevelsOfDetail(_ levels: Int) { self.levels = levels }
    @ObjCMethod("levelsOfDetailBias") func levelsOfDetailBias() -> Int { levelsBias }
    @ObjCMethod("setLevelsOfDetailBias:") func setLevelsOfDetailBias(_ bias: Int) { levelsBias = bias }

    /// Tiles fade in over this long: they do not, as they draw at once.
    @ObjCClassMethod("fadeDuration") static func fadeDuration(_ cls: ObjCClass) -> Double { 0 }
}
