import AppKit
let title = "合并上线"
let measured = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
precondition(ButtonTitleLayout.width(for: title) >= measured + 24, "four-character Chinese title has full text space")
precondition(ButtonTitleLayout.width(for: "A") >= 64, "short title retains useful touch target")
let long = String(repeating: "字", count: 20)
precondition(ButtonTitleLayout.width(for: long) <= 124, "long Chinese title cannot consume whole strip")
precondition(Array(repeating: long, count: 5).map(ButtonTitleLayout.width).reduce(0, +) <= 620, "five long titles have bounded combined width")
print("PASS: 4 title layout checks; no Touch Bar presentation or input events")
