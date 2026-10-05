import Foundation

let args = CommandLine.arguments
let source = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let original = try PropertyListSerialization.propertyList(from: source, options: [], format: nil) as! [String: Any]
let cursors = original["Cursors"] as! [String: Any]
let name = cursors.keys.sorted()[0]
for (kind, field, value) in [("bad-hotspot", "HotSpotX", -1 as Any),
                            ("bad-image", "Representations", [Data("invalid PNG".utf8)] as Any),
                            ("bad-frames", "FrameCount", 1.5 as Any)] {
    var cape = original, changed = cursors, entry = cursors[name] as! [String: Any]
    entry[field] = value
    changed[name] = entry
    cape["Cursors"] = changed
    let data = try PropertyListSerialization.data(fromPropertyList: cape, format: .binary, options: 0)
    try data.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent("\(kind).cape"))
}
