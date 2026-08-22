import AppKit

_ = NSApplication.shared

func roundedFieldTextX(fontSize: CGFloat) -> (x: CGFloat, height: CGFloat) {
    let field = NSTextField(string: "Sample")
    field.font = .systemFont(ofSize: fontSize)
    field.isBezeled = true
    field.bezelStyle = .roundedBezel
    field.sizeToFit()
    let drawing = field.cell!.drawingRect(forBounds: field.bounds)
    let title = field.cell!.titleRect(forBounds: drawing)
    return (drawing.minX + title.minX, field.bounds.height)
}

func borderlessMenuLabelX(fontSize: CGFloat) -> (x: CGFloat, height: CGFloat) {
    let menu = NSPopUpButton(frame: .zero, pullsDown: false)
    menu.addItem(withTitle: "Sample")
    menu.font = .systemFont(ofSize: fontSize)
    menu.isBordered = false
    menu.sizeToFit()
    return (menu.cell!.titleRect(forBounds: menu.bounds).minX, menu.bounds.height)
}

let minFontSize = 10.0
let maxFontSize = 32.0
let fontStep = 2.0

print("appFontSize footnoteFontSize fieldTextX fieldHeight menuLabelX menuHeight")
for appFontSize in stride(from: minFontSize, through: maxFontSize, by: fontStep) {
    let footnoteFontSize = max(8, appFontSize - 3)
    let field = roundedFieldTextX(fontSize: footnoteFontSize)
    let menu = borderlessMenuLabelX(fontSize: footnoteFontSize)
    print(
        String(
            format: "%11.0f %16.0f %10.2f %11.1f %10.2f %10.1f",
            appFontSize, footnoteFontSize, field.x, field.height, menu.x, menu.height
        )
    )
}
