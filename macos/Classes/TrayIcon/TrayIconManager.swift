import AppKit

class TrayIconManager {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var menuItemClickHandler: ((String) -> Void)?
    
    func showTrayIcon(iconPath: String?, tooltip: String?) {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        
        if let iconPath = iconPath,
           let image = NSImage(contentsOfFile: iconPath) {
            image.size = NSSize(width: 18, height: 18)
            statusItem?.button?.image = image
        } else {
            statusItem?.button?.title = "MCP"
        }
        
        if let tooltip = tooltip {
            statusItem?.button?.toolTip = tooltip
        }
        
        setupMenu()
    }
    
    func hideTrayIcon() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            self.menu = nil
        }
    }
    
    func updateTooltip(_ tooltip: String) {
        statusItem?.button?.toolTip = tooltip
    }
    
    func setMenuItems(_ items: [[String: Any]], clickHandler: @escaping (String) -> Void) {
        menuItemClickHandler = clickHandler
        menu?.removeAllItems()
        
        for item in items {
            if let isSeparator = item["isSeparator"] as? Bool, isSeparator {
                menu?.addItem(NSMenuItem.separator())
            } else if let label = item["label"] as? String,
                      let id = item["id"] as? String {
                let menuItem = NSMenuItem(
                    title: label,
                    action: #selector(menuItemClicked(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = id
                
                if let disabled = item["disabled"] as? Bool {
                    menuItem.isEnabled = !disabled
                }
                
                menu?.addItem(menuItem)
            }
        }
    }
    
    private func setupMenu() {
        if menu == nil {
            menu = NSMenu()
            statusItem?.menu = menu
        }
    }
    
    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        if let itemId = sender.representedObject as? String {
            menuItemClickHandler?(itemId)
        }
    }
}